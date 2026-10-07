import SwiftData
import SwiftUI

/// What the pantry sheet hands back. `ingredientId` is a dictionary id or a `custom:<uuid>`,
/// never text folded from the name.
struct PantryFormResult: Equatable, Identifiable {
    var ingredientId: String
    var name: String
    var isNewCustom: Bool
    var quantity: Double
    var unit: String
    var location: PantryLocation
    var minimum: Double?
    var dateType: PantryDateType?
    var dateValue: Date?

    var id: String { "\(ingredientId)|\(unit)" }
}

struct PantryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Query private var items: [PantryItem]
    @Query private var operations: [PendingOperation]
    @State private var showingAdd = false
    @State private var search = ""
    @State private var errorMessage: String?
    @State private var refreshing = false
    @State private var loadedOnce = false
    @State private var loadFailed = false
    @State private var finished: PantryItem?
    @State private var editing: PantryItem?
    @State private var separatePrompt: PantryFormResult?
    @State private var session = HouseholdSession.shared

    private var householdID: UUID? { session.snapshot.household?.id }
    private var syncsHousehold: Bool { householdID != nil && PantryOutbox.syncsHousehold }

    private var scoped: [PantryItem] { items.filter { $0.householdID == householdID } }

    private var visible: [PantryItem] {
        scoped.filter { search.isEmpty || $0.displayName.localizedCaseInsensitiveContains(search) }
            .sorted {
                if $0.isLowStock != $1.isLowStock { return $0.isLowStock }
                return $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
            }
    }

    private var pantryOperations: [SyncWorkItem] {
        operations.map(\.workItem).filter { item in
            PantrySync.isPantry(item) && PantrySync.payload(of: item)?.householdID == householdID
        }
    }

    private var marks: [String: PantrySyncMark] { PantryOutbox.marks(pantryOperations) }

    private var conflicts: [PantryConflictSummary] {
        var seen = Set<String>()
        return pantryOperations.compactMap { operation in
            guard operation.status == .requiresResolution, !seen.contains(operation.entityId) else { return nil }
            seen.insert(operation.entityId)
            let payloads = pantryOperations.filter { $0.entityId == operation.entityId }.compactMap(PantrySync.payload(of:))
            let server = payloads.first { $0.serverItem != nil || $0.serverDeleted || $0.rejection == "pantry_unit_choice" }
            return PantryConflictSummary(
                entityId: operation.entityId,
                name: payloads.last?.item?.displayName ?? server?.serverItem?.displayName ?? "Malzeme",
                mine: payloads.last,
                server: server
            )
        }
    }

    private var hasFailed: Bool { pantryOperations.contains { $0.status == .failed } }

    private var isOffline: Bool { !SyncEngine.shared.online || session.syncState == .offline }

    var body: some View {
        List {
            statusSections
            content
        }
        .navigationTitle("Pantry")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $search, prompt: "Malzeme ara")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                if refreshing { ProgressView().controlSize(.small).accessibilityLabel(PantryCopy.loading) }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingAdd = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Pantry malzemesi ekle")
                    .accessibilityIdentifier("pantry.add")
            }
        }
        .sheet(isPresented: $showingAdd) {
            PantryForm(item: nil, householdID: householdID) { add($0, confirmSeparate: false) }
        }
        .sheet(item: $editing) { item in
            PantryForm(item: item, householdID: householdID) { edit(item, with: $0) }
                .id(item.persistentModelID)
        }
        .sheet(isPresented: Binding(get: { session.offersPantryTransfer }, set: { if !$0 { session.offersPantryTransfer = false } })) {
            PantryTransferSheet { choice in
                if let householdID, choice != .keepSeparate {
                    PantryTransferApply.apply(choice, householdID: householdID, in: modelContext)
                    flush()
                }
                session.resolvePantryTransfer()
            }
        }
        .confirmationDialog(
            PantryCopy.finishedTitle,
            isPresented: Binding(get: { finished != nil }, set: { if !$0 { finished = nil } }),
            titleVisibility: .visible,
            presenting: finished
        ) { item in
            Button(PantryCopy.addToMarket) { finish(item, choice: .addToMarket) }
            Button(PantryCopy.missingMinimum) { finish(item, choice: .missingAgainstMinimum) }
            Button(PantryCopy.deleteItem, role: .destructive) { finish(item, choice: .deleteItem) }
        } message: { _ in
            Text(PantryCopy.finishedMessage)
        }
        .alert(
            PantryCopy.unitChoice,
            isPresented: Binding(get: { separatePrompt != nil }, set: { if !$0 { separatePrompt = nil } }),
            presenting: separatePrompt
        ) { result in
            Button(PantryCopy.separateUnit) {
                separatePrompt = nil
                add(result, confirmSeparate: true)
            }
            Button("Vazgeç", role: .cancel) { separatePrompt = nil }
        } message: { result in
            Text("\(result.name) başka bir birimle kayıtlı. Birimler birbirine çevrilemiyor; ayrı satır olarak ekleyebilirsin.")
        }
        .alert("Pantry güncellenemedi", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("Tamam", role: .cancel) {}
        } message: { Text(errorMessage ?? "") }
        .task(id: householdID) {
            session.offerPantryTransferIfNeeded(in: modelContext)
            await refreshFromServer()
        }
        .refreshable { await refreshFromServer() }
    }

    @ViewBuilder
    private var statusSections: some View {
        if householdID == nil {
            Section {
                Label("Kişisel pantry yalnız bu telefonda durur. Ev halkı kurarsan aktarıp aktarmayacağını sen seçersin.", systemImage: "iphone")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } else if syncsHousehold && isOffline {
            Section {
                Label(PantryCopy.offline, systemImage: "wifi.slash")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        ForEach(conflicts) { conflict in
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Label(PantryCopy.conflict, systemImage: "exclamationmark.arrow.triangle.2.circlepath")
                        .font(.subheadline.weight(.semibold))
                    Text(conflict.name).font(.headline)
                    Text(conflict.serverLine).font(.footnote).foregroundStyle(.secondary)
                    Text(conflict.mineLine).font(.footnote).foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                Button(PantryCopy.useServer) {
                    PantryOutbox.useServer(entityId: conflict.entityId, in: modelContext)
                    Task { await refreshFromServer() }
                }
                Button(PantryCopy.reapplyMine) {
                    PantryOutbox.reapply(entityId: conflict.entityId, in: modelContext)
                    flush()
                }
            }
        }
        if hasFailed {
            Section {
                Label(PantryCopy.failedMessage, systemImage: "xmark.icloud")
                    .font(.subheadline)
                Button(PantryCopy.retry) {
                    PantryOutbox.retryFailed(in: modelContext)
                    flush()
                }
                Button(PantryCopy.discardFailed, role: .destructive) {
                    PantryOutbox.discardFailed(in: modelContext)
                    Task { await refreshFromServer() }
                }
            }
        }
        if loadFailed && !scoped.isEmpty {
            Section {
                Label(PantryCopy.refreshFailed, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                Button(PantryCopy.retry) { Task { await refreshFromServer() } }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if syncsHousehold && !loadedOnce && scoped.isEmpty {
            Section {
                HStack(spacing: 12) {
                    ProgressView()
                    Text(PantryCopy.loading)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(PantryCopy.loading)
            }
        } else if loadFailed && scoped.isEmpty {
            ContentUnavailableView {
                Label(PantryCopy.loadFailedTitle, systemImage: "wifi.exclamationmark")
            } description: {
                Text(PantryCopy.loadFailed)
            } actions: {
                Button(PantryCopy.retry) { Task { await refreshFromServer() } }
                    .accessibilityIdentifier("pantry.retry")
            }
        } else if scoped.isEmpty {
            ContentUnavailableView {
                Label(PantryCopy.emptyTitle, systemImage: "shippingbox")
            } description: {
                Text(PantryCopy.empty)
            } actions: {
                Button(PantryCopy.addIngredient) { showingAdd = true }
            }
        } else if visible.isEmpty {
            ContentUnavailableView.search(text: search)
        } else {
            ForEach(visible) { item in row(item) }
                .onDelete(perform: delete)
        }
    }

    private func presentation(_ item: PantryItem) -> PantryRowPresentation {
        PantryRowPresentation.make(
            name: item.displayName,
            ingredientResolved: item.ingredientResolved,
            quantity: item.quantity,
            unit: item.unit,
            location: item.location,
            minimumQuantity: item.minimumQuantity,
            dateType: item.dateType,
            dateValue: item.dateValue,
            sync: marks[item.uuid.uuidString.lowercased()] ?? .synced
        )
    }

    @ViewBuilder
    private func row(_ item: PantryItem) -> some View {
        let shown = presentation(item)
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text(shown.title).font(.headline)
                Text("\(shown.amount) · \(shown.location)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let minimum = shown.minimum {
                    Text(minimum).font(.footnote).foregroundStyle(.secondary)
                }
                if let date = shown.date {
                    Text(date).font(.footnote).foregroundStyle(.secondary)
                }
                if !shown.badges.isEmpty {
                    FlowLayout(spacing: 6) {
                        ForEach(shown.badges, id: \.self) { badge in
                            Label(badge.text, systemImage: badge.symbol)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(color(badge.tone))
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(shown.accessibilityLabel)
            controls(item)
        }
        .padding(.vertical, 5)
        .swipeActions {
            Button(role: .destructive) { delete(item) } label: { Label("Sil", systemImage: "trash") }
        }
    }

    @ViewBuilder
    private func controls(_ item: PantryItem) -> some View {
        let stepper = HStack(spacing: 10) {
            Button("−") { change(item, by: -1) }
                .buttonStyle(.bordered)
                .accessibilityLabel("Miktarı bir azalt")
            Button("+") { change(item, by: 1) }
                .buttonStyle(.bordered)
                .accessibilityLabel("Miktarı bir artır")
        }
        let actions = Group {
            Button("Düzenle") { editing = item }
                .font(.footnote.weight(.semibold))
                .buttonStyle(.borderless)
                .accessibilityHint("Açılır. Miktar ancak Kaydet ile yazılır.")
            Button("Bitti") { finished = item }
                .font(.footnote.weight(.semibold))
                .buttonStyle(.borderless)
                .accessibilityHint("Seçenekleri gösterir. İptal miktarı değiştirmez.")
        }
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 10) {
                stepper
                HStack(spacing: 16) { actions }
            }
        } else {
            HStack(spacing: 10) {
                stepper
                Spacer()
                actions
            }
        }
    }

    private func color(_ tone: PantryBadgeTone) -> Color {
        switch tone {
        case .critical: .red
        case .warning: .orange
        case .info: .secondary
        }
    }

    // MARK: Writes

    private func write(_ action: PantryOutbox.Action, _ item: PantryItem, baseVersion: Int?, confirmSeparate: Bool = false) {
        if PantryOutbox.record(action, item, baseVersion: baseVersion, confirmSeparate: confirmSeparate, in: modelContext) {
            flush()
        }
    }

    private func flush() {
        Task { @MainActor in
            if await PantryOutbox.flush(in: modelContext) { errorMessage = PantryCopy.conflict }
        }
    }

    private func finish(_ item: PantryItem, choice: PantryFinishedChoice) {
        let recorded = item.quantity
        finished = nil
        switch choice {
        case .deleteItem:
            // The delete is the only write; a zero-update first would race it on version.
            delete(item)
        case .addToMarket:
            commitQuantity(item, PantryFinishedFlow.quantity(current: recorded, choice: choice))
            addMarket(name: item.displayName, ingredientId: item.ingredientID, quantity: recorded > 0 ? recorded : 1, unit: item.unit)
        case .missingAgainstMinimum:
            commitQuantity(item, PantryFinishedFlow.quantity(current: recorded, choice: choice))
            guard let missing = PantryFinishedMath.shortage(quantity: 0, minimum: item.minimumQuantity) else {
                errorMessage = PantryCopy.noMinimum
                return
            }
            if missing > 0 {
                addMarket(name: item.displayName, ingredientId: item.ingredientID, quantity: missing, unit: item.unit)
            }
        }
    }

    private func commitQuantity(_ item: PantryItem, _ quantity: Double) {
        let base = item.revision
        item.quantity = quantity
        item.revision += 1
        item.updatedAt = .now
        try? modelContext.save()
        write(.update, item, baseVersion: base)
    }

    private func addMarket(name: String, ingredientId: String, quantity: Double, unit: String) {
        do {
            try GroceryListService.addManual(name: name, quantity: quantity, unit: unit, ingredientId: ingredientId, in: modelContext)
        } catch {
            errorMessage = "Önce bu haftanın planını kur. Market listesi o zaman açılır."
        }
    }

    private func add(_ result: PantryFormResult, confirmSeparate: Bool) {
        guard result.quantity.isFinite, result.quantity >= 0 else { return }
        let dictionary = IngredientDictionary.shared
        let peers = scoped.filter { dictionary.canonicalId($0.ingredientID) == result.ingredientId }
        let match = peers.first { PantryUnitPolicy.compatible($0.unit, result.unit) }
        switch PantryUnitPolicy.decision(
            existingUnit: match?.unit ?? peers.first?.unit,
            existingQuantity: match?.quantity ?? 0,
            incomingUnit: result.unit,
            incomingQuantity: result.quantity,
            confirmSeparate: confirmSeparate
        ) {
        case .invalid:
            errorMessage = PantryCopy.unknownUnit
        case .choiceRequired:
            separatePrompt = result
        case .merge(let total, let storedUnit):
            guard let match else { return }
            let base = match.revision
            match.quantity = total
            match.unit = storedUnit
            match.location = result.location
            if let minimum = result.minimum {
                match.minimumQuantity = PantryUnitPolicy.converted(minimum, from: result.unit, to: storedUnit) ?? minimum
            }
            // Merged stock keeps the earlier date so a warning is never hidden by the newer pack.
            if let type = result.dateType, let value = result.dateValue, match.dateValue.map({ value < $0 }) ?? true {
                match.setDate(type, value)
            }
            match.revision += 1
            match.updatedAt = .now
            try? modelContext.save()
            write(.update, match, baseVersion: base)
        case .separate:
            let item = PantryItem(
                householdID: householdID,
                ingredientID: result.ingredientId,
                displayName: result.name,
                quantity: result.quantity,
                unit: UnitNormalization.parse(result.unit).code,
                location: result.location,
                minimumQuantity: result.minimum,
                dateType: result.dateType,
                dateValue: result.dateValue
            )
            modelContext.insert(item)
            try? modelContext.save()
            if result.isNewCustom {
                PantryIngredientStore.remember(IngredientEntry(id: result.ingredientId, name: result.name), householdID: householdID)
            }
            write(.create, item, baseVersion: nil, confirmSeparate: confirmSeparate || !peers.isEmpty)
        }
    }

    private func edit(_ item: PantryItem, with result: PantryFormResult) {
        guard result.quantity.isFinite, result.quantity >= 0 else { return }
        guard PantryUnitPolicy.isKnown(result.unit) else {
            errorMessage = PantryCopy.unknownUnit
            return
        }
        let dictionary = IngredientDictionary.shared
        let duplicate = scoped.contains { other in
            other.uuid != item.uuid
                && dictionary.canonicalId(other.ingredientID) == result.ingredientId
                && PantryUnitPolicy.compatible(other.unit, result.unit)
        }
        if duplicate {
            errorMessage = PantryCopy.duplicateRow
            return
        }
        let wasOnServer = item.ingredientResolved
        let base = item.revision
        item.quantity = PantryUnitPolicy.editedQuantity(previousQuantity: item.quantity, previousUnit: item.unit, typedQuantity: result.quantity, newUnit: result.unit)
        item.ingredientID = result.ingredientId
        item.displayName = result.name.trimmingCharacters(in: .whitespacesAndNewlines)
        item.unit = UnitNormalization.parse(result.unit).code
        item.location = result.location
        item.minimumQuantity = result.minimum
        item.setDate(result.dateType, result.dateValue)
        item.revision += 1
        item.updatedAt = .now
        try? modelContext.save()
        if result.isNewCustom {
            PantryIngredientStore.remember(IngredientEntry(id: result.ingredientId, name: result.name), householdID: householdID)
        }
        if wasOnServer {
            write(.update, item, baseVersion: base)
        } else {
            // A row the server never accepted (it had no dictionary id) is created now that it has one.
            item.revision = 1
            try? modelContext.save()
            write(.create, item, baseVersion: nil, confirmSeparate: true)
        }
    }

    private func change(_ item: PantryItem, by amount: Double) {
        commitQuantity(item, max(0, item.quantity + amount))
    }

    private func delete(_ item: PantryItem) {
        if item.ingredientResolved { write(.delete, item, baseVersion: item.revision) }
        modelContext.delete(item)
        try? modelContext.save()
    }

    private func delete(at offsets: IndexSet) {
        let rows = visible
        for index in offsets where rows.indices.contains(index) { delete(rows[index]) }
    }

    private func refreshFromServer() async {
        guard let householdID, syncsHousehold else {
            loadedOnce = true
            loadFailed = false
            return
        }
        refreshing = true
        defer {
            refreshing = false
            loadedOnce = true
        }
        if await PantryOutbox.flush(in: modelContext) { errorMessage = PantryCopy.conflict }
        do {
            try await PantryCache.refresh(householdID: householdID, in: modelContext)
            loadFailed = false
        } catch {
            loadFailed = true
        }
    }
}

private struct PantryConflictSummary: Identifiable {
    var entityId: String
    var name: String
    var mine: PantryQueuedPayload?
    var server: PantryQueuedPayload?

    var id: String { entityId }

    var serverLine: String {
        if server?.serverDeleted == true { return "Sunucuda: silinmiş" }
        if server?.rejection == "pantry_unit_choice" { return "Sunucuda: bu malzeme başka bir birimle kayıtlı" }
        guard let item = server?.serverItem else { return "Sunucuda: güncel hali yükleniyor" }
        return "Sunucuda: \(Self.describe(item))"
    }

    var mineLine: String {
        guard let mine else { return "Senin değişikliğin: —" }
        if mine.action == "delete" { return "Senin değişikliğin: sil" }
        guard let item = mine.item else { return "Senin değişikliğin: —" }
        return "Senin değişikliğin: \(Self.describe(item))"
    }

    private static func describe(_ item: PantryRemoteItem) -> String {
        "\(QuantityFormat.quantityAndUnit(quantity: item.quantity, unit: item.unit)) · \(item.location.title)"
    }
}

/// Controlled ingredient choice: dictionary rows and this household's own ingredients.
/// A new ingredient gets a random `custom:<uuid>` id only after the user confirms.
struct PantryIngredientPicker: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var items: [PantryItem]
    @State private var query: String
    @State private var confirmingCustom = false
    var householdID: UUID?
    var onPick: (IngredientEntry, Bool) -> Void

    init(query: String = "", householdID: UUID?, onPick: @escaping (IngredientEntry, Bool) -> Void) {
        _query = State(initialValue: query)
        self.householdID = householdID
        self.onPick = onPick
    }

    private var trimmed: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var customs: [IngredientEntry] { PantryIngredientStore.customs(householdID: householdID, items: items) }

    private var results: [IngredientEntry] { IngredientDictionary.shared.search(trimmed, including: customs, limit: 40) }

    private var hasExactName: Bool {
        let folded = IngredientDictionary.fold(trimmed)
        return results.contains { entry in ([entry.name] + entry.synonyms).contains { IngredientDictionary.fold($0) == folded } }
    }

    var body: some View {
        List {
            if !trimmed.isEmpty && !hasExactName {
                Section {
                    Button { confirmingCustom = true } label: {
                        Label("“\(trimmed)” — \(PantryCopy.createCustom)", systemImage: "plus.circle")
                    }
                    .accessibilityIdentifier("pantry.ingredient.create")
                } footer: {
                    Text(PantryCopy.unmatchedHint)
                }
            }
            Section {
                if results.isEmpty {
                    Text("Sözlükte eşleşen malzeme yok.").foregroundStyle(.secondary)
                }
                ForEach(results) { entry in
                    Button { pick(entry, isNew: false) } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.name).foregroundStyle(.primary)
                            if IngredientDictionary.isCustom(entry.id) {
                                Text("Ev halkının malzemesi").font(.caption).foregroundStyle(.secondary)
                            } else if !entry.synonyms.isEmpty {
                                Text(entry.synonyms.joined(separator: ", ")).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(PantryCopy.pickIngredient)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Malzeme ara")
        .alert(PantryCopy.createCustom, isPresented: $confirmingCustom) {
            Button(PantryCopy.createCustom) {
                pick(IngredientEntry(id: IngredientDictionary.newCustomId(), name: trimmed), isNew: true)
            }
            Button("Vazgeç", role: .cancel) {}
        } message: {
            Text("“\(trimmed)”. \(PantryCopy.createCustomMessage)")
        }
    }

    private func pick(_ entry: IngredientEntry, isNew: Bool) {
        onPick(entry, isNew)
        dismiss()
    }
}

struct PantryTransferSheet: View {
    @Environment(\.dismiss) private var dismiss
    var onChoose: (PantryTransferChoice) -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(PantryCopy.transferMessage)
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)
                    Button(PantryCopy.transferMove) { choose(.move) }
                        .buttonStyle(.borderedProminent)
                    Button(PantryCopy.transferCopy) { choose(.copy) }
                        .buttonStyle(.bordered)
                    Button(PantryCopy.transferKeep) { choose(.keepSeparate) }
                        .buttonStyle(.bordered)
                }
                .padding()
            }
            .navigationTitle(PantryCopy.transferTitle)
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
    }

    private func choose(_ choice: PantryTransferChoice) {
        onChoose(choice)
        dismiss()
    }
}

private struct PantryForm: View {
    @Environment(\.dismiss) private var dismiss
    var item: PantryItem?
    var householdID: UUID?
    @State private var draft: PantryFormDraft
    var onSave: (PantryFormResult) -> Void

    init(item: PantryItem?, householdID: UUID?, onSave: @escaping (PantryFormResult) -> Void) {
        self.item = item
        self.householdID = householdID
        self.onSave = onSave
        _draft = State(initialValue: Self.draft(for: item))
    }

    private static func draft(for item: PantryItem?) -> PantryFormDraft {
        guard let item else {
            var draft = PantryFormDraft.empty
            draft.date = Date()
            return draft
        }
        return PantryFormDraft.loaded(
            ingredientId: item.ingredientID,
            name: item.displayName,
            quantity: item.quantity,
            unit: item.unit,
            location: item.location,
            minimumQuantity: item.minimumQuantity,
            dateType: item.dateType,
            dateValue: item.dateValue
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Malzeme") {
                    NavigationLink {
                        PantryIngredientPicker(query: draft.name, householdID: householdID) { entry, isNew in
                            draft.choose(entry, isNewCustom: isNew)
                        }
                    } label: {
                        LabeledContent("Malzeme", value: draft.ingredientId == nil ? PantryCopy.pickIngredient : draft.name)
                    }
                    .accessibilityIdentifier("pantry.form.ingredient")
                    if draft.ingredientId == nil && item != nil {
                        Text(PantryCopy.unmatchedHint).font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Section("Miktar") {
                    TextField("Miktar", text: $draft.quantityText)
                        .keyboardType(.decimalPad)
                    Picker("Birim", selection: $draft.unit) {
                        if draft.unit.isEmpty { Text("Birim seç").tag("") }
                        ForEach(PantryUnitPolicy.pickerUnits, id: \.self) { code in
                            Text(UnitLabels.turkish(code)).tag(code)
                        }
                    }
                    if let legacy = draft.legacyUnit, draft.unit.isEmpty {
                        Text("Kayıtlı birim “\(legacy)” tanınmıyor. Listeden bilinen bir birim seç.")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                    Picker("Konum", selection: $draft.location) {
                        ForEach(PantryLocation.allCases) { Text($0.title).tag($0) }
                    }
                }
                Section {
                    Toggle("Minimum miktar", isOn: $draft.hasMinimum)
                    if draft.hasMinimum {
                        TextField("Minimum (\(UnitLabels.turkish(draft.unit)))", text: $draft.minimumText)
                            .keyboardType(.decimalPad)
                    }
                } footer: {
                    Text("Minimum, miktarla aynı birimdedir. Altına inince satırda “Azaldı” görünür.")
                }
                Section {
                    Toggle("Tarih ekle", isOn: $draft.hasDate)
                    if draft.hasDate {
                        Picker("Tarih türü", selection: $draft.dateType) {
                            ForEach(PantryDateType.allCases) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.inline)
                        DatePicker("Tarih", selection: $draft.date, displayedComponents: .date)
                            .environment(\.locale, Locale(identifier: "tr_TR"))
                    }
                } header: {
                    Text(PantryCopy.dateSection)
                } footer: {
                    Text(PantryCopy.dateFooter)
                }
            }
            .navigationTitle(item == nil ? "Pantry malzemesi" : "Malzemeyi düzenle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("İptal") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(item == nil ? "Ekle" : "Kaydet") { save() }
                        .disabled(!draft.canSave)
                }
            }
        }
    }

    private func save() {
        guard let quantity = draft.quantityToSave, let ingredientId = draft.ingredientId else { return }
        onSave(PantryFormResult(
            ingredientId: ingredientId,
            name: draft.name.trimmingCharacters(in: .whitespacesAndNewlines),
            isNewCustom: draft.isNewCustom,
            quantity: quantity,
            unit: draft.unit,
            location: draft.location,
            minimum: draft.minimumToSave,
            dateType: draft.hasDate ? draft.dateType : nil,
            dateValue: draft.hasDate ? Calendar.current.startOfDay(for: draft.date) : nil
        ))
        dismiss()
    }
}
