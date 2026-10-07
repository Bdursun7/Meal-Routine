import SwiftData
import SwiftUI

struct PantryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var items: [PantryItem]
    @State private var showingAdd = false
    @State private var search = ""
    @State private var errorMessage: String?
    @State private var refreshing = false
    @State private var loadFailed = false
    @State private var finished: PantryItem?
    @State private var editing: PantryItem?
    @State private var session = HouseholdSession.shared

    private var householdID: UUID? { HouseholdSession.shared.snapshot.household?.id }

    private var visible: [PantryItem] {
        items.filter { item in
            item.householdID == householdID &&
            (search.isEmpty || item.displayName.localizedCaseInsensitiveContains(search))
        }.sorted {
            if $0.isLowStock != $1.isLowStock { return $0.isLowStock }
            return $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
        }
    }

    private var awaitingResolution: Bool {
        PendingOperationStore.items(in: modelContext).contains { PantrySync.isPantry($0) && $0.status == .requiresResolution }
    }

    var body: some View {
        List {
            if !SyncEngine.shared.online || session.syncState == .offline {
                Section {
                    Text(PantryCopy.offline)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            if awaitingResolution {
                Section {
                    Text(PantryCopy.conflict)
                        .font(.subheadline.weight(.semibold))
                    Button(PantryCopy.useServer) {
                        dropConflicts()
                        Task { await refreshFromServer() }
                    }
                }
            }
            if refreshing && visible.isEmpty && !loadFailed {
                Section {
                    HStack {
                        ProgressView()
                        Text(PantryCopy.loading)
                    }
                    .accessibilityLabel(PantryCopy.loading)
                }
            } else if loadFailed && visible.isEmpty {
                ContentUnavailableView {
                    Label("Pantry yüklenemedi", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(PantryCopy.loadFailed)
                } actions: {
                    Button("Yeniden dene") { Task { await refreshFromServer() } }
                }
            } else if visible.isEmpty {
                ContentUnavailableView {
                    Label("Pantry boş", systemImage: "shippingbox")
                } description: {
                    Text(PantryCopy.empty)
                } actions: {
                    Button("Malzeme ekle") { showingAdd = true }
                }
            } else {
                ForEach(visible) { item in row(item) }
                    .onDelete(perform: delete)
            }
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
            }
        }
        .sheet(isPresented: $showingAdd) {
            PantryForm(item: nil) { name, quantity, unit, location, minimum, date, confirmSeparate in
                add(name: name, quantity: quantity, unit: unit, location: location, minimum: minimum, date: date, confirmSeparate: confirmSeparate)
            }
        }
        .sheet(item: $editing) { item in
            PantryForm(item: item) { name, quantity, unit, location, minimum, date, confirmSeparate in
                edit(item, name: name, quantity: quantity, unit: unit, location: location, minimum: minimum, date: date, confirmSeparate: confirmSeparate)
            }
            .id(item.persistentModelID)
        }
        .sheet(isPresented: Binding(get: { session.offersPantryTransfer }, set: { if !$0 { session.offersPantryTransfer = false } })) {
            PantryTransferSheet { choice in
                let touched = PantryTransferApply.apply(choice, householdID: householdID ?? UUID(), in: modelContext)
                if let householdID, choice != .keepSeparate {
                    for item in touched {
                        sync(item, action: item.revision > 1 ? "update" : "create", householdID: householdID)
                    }
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
        .alert("Pantry güncellenemedi", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("Tamam", role: .cancel) {}
        } message: { Text(errorMessage ?? "") }
        .task {
            session.offerPantryTransferIfNeeded(in: modelContext)
            await refreshFromServer()
        }
        .refreshable { await refreshFromServer() }
    }

    @ViewBuilder
    private func row(_ item: PantryItem) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text(item.displayName).font(.headline)
                    Spacer()
                    if item.isLowStock { Text("Azaldı").font(.caption.weight(.semibold)).foregroundStyle(.orange) }
                    if item.isExpiredOrNear { Text("Tarih yaklaşıyor").font(.caption.weight(.semibold)).foregroundStyle(.orange) }
                }
                HStack {
                    Text(QuantityFormat.quantityAndUnit(quantity: item.quantity, unit: item.unit))
                    Text("· \(item.location.title)")
                    Spacer()
                    if let minimum = item.minimumQuantity {
                        Text("Min \(QuantityFormat.quantityAndUnit(quantity: minimum, unit: item.unit))")
                    }
                    if let date = item.bestBefore {
                        Text(date.formatted(date: .abbreviated, time: .omitted))
                            .foregroundStyle(item.isExpiredOrNear ? .orange : .secondary)
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            HStack(spacing: 10) {
                Button("−") { change(item, by: -1) }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("Miktarı bir azalt")
                Button("+") { change(item, by: 1) }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("Miktarı bir artır")
                Spacer()
                Button("Düzenle") { editing = item }
                    .font(.footnote.weight(.semibold))
                    .buttonStyle(.borderless)
                    .accessibilityHint("Açılır. Miktar ancak Kaydet ile yazılır.")
                Button("Bitti") { markFinished(item) }
                    .font(.footnote.weight(.semibold))
                    .buttonStyle(.borderless)
                    .accessibilityHint("Seçenekleri gösterir. İptal miktarı değiştirmez.")
            }
        }
        .padding(.vertical, 5)
        .swipeActions {
            Button(role: .destructive) { delete(item) } label: { Label("Sil", systemImage: "trash") }
        }
    }

    /// Opens the finished choices. Stock is unchanged until the user picks one.
    private func markFinished(_ item: PantryItem) {
        finished = item
    }

    private func finish(_ item: PantryItem, choice: PantryFinishedChoice) {
        let recorded = item.quantity
        finished = nil
        item.quantity = PantryFinishedFlow.quantity(current: recorded, choice: choice)
        switch choice {
        case .deleteItem:
            // The delete request is the sync. A separate zero-update would race it on revision.
            delete(item)
        case .addToMarket:
            commitFinishedStock(item)
            addMarket(name: item.displayName, ingredientId: item.ingredientID, quantity: recorded > 0 ? recorded : 1, unit: item.unit)
        case .missingAgainstMinimum:
            commitFinishedStock(item)
            guard let missing = PantryFinishedMath.shortage(quantity: 0, minimum: item.minimumQuantity) else {
                errorMessage = PantryCopy.noMinimum
                return
            }
            if missing > 0 {
                addMarket(name: item.displayName, ingredientId: item.ingredientID, quantity: missing, unit: item.unit)
            }
        }
    }

    private func commitFinishedStock(_ item: PantryItem) {
        item.revision += 1
        item.updatedAt = .now
        try? modelContext.save()
        syncUpdate(item)
    }

    private func addMarket(name: String, ingredientId: String, quantity: Double, unit: String) {
        do {
            try GroceryListService.addManual(name: name, quantity: quantity, unit: unit, ingredientId: ingredientId, in: modelContext)
        } catch {
            errorMessage = "Önce bu haftanın planını kur. Market listesi o zaman açılır."
        }
    }

    private func add(name: String, quantity: Double, unit: String, location: PantryLocation, minimum: Double?, date: Date?, confirmSeparate: Bool) {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, quantity >= 0 else { return }
        let ingredientID = clean.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        let peers = visible.filter { $0.ingredientID == ingredientID }
        let match = peers.first { PantryUnitPolicy.compatible($0.unit, unit) }
        switch PantryUnitPolicy.decision(
            existingUnit: match?.unit ?? peers.first?.unit,
            existingQuantity: match?.quantity ?? 0,
            incomingUnit: unit,
            incomingQuantity: quantity,
            confirmSeparate: confirmSeparate || match != nil
        ) {
        case .invalid:
            errorMessage = PantryCopy.unitMismatch
        case .choiceRequired:
            errorMessage = PantryCopy.unitChoice
        case .merge(let total, let storedUnit):
            guard let match else { return }
            match.quantity = total
            match.unit = storedUnit
            match.location = location
            match.minimumQuantity = minimum
            match.bestBefore = date
            match.revision += 1
            match.updatedAt = .now
            try? modelContext.save()
            syncUpdate(match)
        case .separate:
            let item = PantryItem(
                householdID: householdID,
                ingredientID: ingredientID,
                displayName: clean,
                quantity: quantity,
                unit: UnitNormalization.parse(unit).code,
                location: location,
                minimumQuantity: minimum,
                bestBefore: date
            )
            modelContext.insert(item)
            try? modelContext.save()
            syncCreate(item, confirmSeparate: confirmSeparate)
        }
    }

    private func edit(_ item: PantryItem, name: String, quantity: Double, unit: String, location: PantryLocation, minimum: Double?, date: Date?, confirmSeparate: Bool) {
        guard quantity.isFinite, quantity >= 0 else { return }
        if !PantryUnitPolicy.isKnown(unit) && !confirmSeparate {
            errorMessage = PantryCopy.unitMismatch
            return
        }
        if !PantryUnitPolicy.compatible(item.unit, unit) && !confirmSeparate {
            errorMessage = PantryCopy.unitChoice
            return
        }
        let canonical = UnitNormalization.parse(unit).code
        var storedQuantity = quantity
        if PantryUnitPolicy.compatible(item.unit, unit), item.unit != canonical, abs(quantity - item.quantity) < 0.001,
           let converted = PantryUnitPolicy.converted(item.quantity, from: item.unit, to: canonical) {
            storedQuantity = converted
        }
        item.displayName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        item.quantity = storedQuantity
        item.unit = canonical
        item.location = location
        item.minimumQuantity = minimum
        item.bestBefore = date
        item.revision += 1
        item.updatedAt = .now
        try? modelContext.save()
        syncUpdate(item)
    }

    private func change(_ item: PantryItem, by amount: Double) {
        item.quantity = max(0, item.quantity + amount)
        item.revision += 1
        item.updatedAt = .now
        try? modelContext.save()
        syncUpdate(item)
    }

    private func delete(_ item: PantryItem) {
        syncDelete(item)
        modelContext.delete(item)
        try? modelContext.save()
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets where visible.indices.contains(index) { delete(visible[index]) }
    }

    private func remote(_ item: PantryItem, revision: Int? = nil) -> PantryRemoteItem? {
        guard let householdID else { return nil }
        return PantryRemoteItem(
            id: item.uuid,
            householdId: householdID,
            ingredientId: item.ingredientID,
            displayName: item.displayName,
            quantity: item.quantity,
            unit: item.unit,
            location: item.location,
            minimumQuantity: item.minimumQuantity,
            bestBefore: item.bestBefore.map { $0.formatted(.iso8601.year().month().day()) },
            revision: revision ?? item.revision,
            createdAt: nil,
            updatedAt: item.updatedAt
        )
    }

    private func sync(_ item: PantryItem, action: String, householdID: UUID) {
        if action == "create" { syncCreate(item, confirmSeparate: true) }
        else { syncUpdate(item) }
    }

    private func syncCreate(_ item: PantryItem, confirmSeparate: Bool) {
        guard let householdID, let api = PantrySync.repository(), let remote = remote(item) else { return }
        let key = UUID()
        Task { @MainActor in
            do {
                let saved = try await api.create(householdId: householdID, item: remote, idempotencyKey: key.uuidString, confirmSeparate: confirmSeparate)
                item.uuid = saved.id
                item.revision = saved.revision
                item.updatedAt = saved.updatedAt ?? .now
                try? modelContext.save()
                loadFailed = false
            } catch PantrySyncError.unitChoice where !confirmSeparate {
                errorMessage = PantryCopy.unitChoice
            } catch PantrySyncError.conflict {
                PantrySync.enqueue(action: "create", householdID: householdID, item: remote, in: modelContext, status: .requiresResolution, id: key, confirmSeparate: confirmSeparate)
                errorMessage = PantryCopy.conflict
            } catch {
                PantrySync.enqueue(action: "create", householdID: householdID, item: remote, in: modelContext, status: .pending, id: key, confirmSeparate: confirmSeparate)
                errorMessage = PantryCopy.saveFailed
            }
        }
    }

    private func syncUpdate(_ item: PantryItem) {
        guard let householdID, let api = PantrySync.repository(), let remote = remote(item, revision: max(1, item.revision - 1)) else { return }
        let key = UUID()
        Task { @MainActor in
            do {
                let saved = try await api.update(householdId: householdID, item: remote, idempotencyKey: key.uuidString)
                item.revision = saved.revision
                item.updatedAt = saved.updatedAt ?? .now
                try? modelContext.save()
            } catch PantrySyncError.conflict {
                PantrySync.enqueue(action: "update", householdID: householdID, item: remote, in: modelContext, status: .requiresResolution, id: key)
                errorMessage = PantryCopy.conflict
            } catch {
                PantrySync.enqueue(action: "update", householdID: householdID, item: remote, in: modelContext, status: .pending, id: key)
                errorMessage = PantryCopy.saveFailed
            }
        }
    }

    private func syncDelete(_ item: PantryItem) {
        guard let householdID, let api = PantrySync.repository(), let remote = remote(item) else { return }
        let key = UUID()
        Task {
            do { try await api.delete(householdId: householdID, item: remote, idempotencyKey: key.uuidString) }
            catch PantrySyncError.conflict {
                await MainActor.run {
                    PantrySync.enqueue(action: "delete", householdID: householdID, item: remote, in: modelContext, status: .requiresResolution, id: key)
                    errorMessage = PantryCopy.conflict
                }
            } catch {
                await MainActor.run {
                    PantrySync.enqueue(action: "delete", householdID: householdID, item: remote, in: modelContext, status: .pending, id: key)
                }
            }
        }
    }

    private func refreshFromServer() async {
        guard let householdID, let api = PantrySync.repository() else { return }
        refreshing = true
        defer { refreshing = false }
        await HouseholdSession.shared.drainPending(in: modelContext)
        do {
            let remoteItems = try await api.list(householdId: householdID)
            for item in remoteItems {
                if let local = items.first(where: { $0.uuid == item.id }) {
                    local.ingredientID = item.ingredientId
                    local.displayName = item.displayName
                    local.quantity = item.quantity
                    local.unit = item.unit
                    local.location = item.location
                    local.minimumQuantity = item.minimumQuantity
                    local.bestBefore = item.bestBefore.flatMap { Self.parseDay($0) }
                    local.revision = item.revision
                    local.updatedAt = item.updatedAt ?? Date()
                } else {
                    modelContext.insert(PantryItem(
                        uuid: item.id,
                        householdID: householdID,
                        ingredientID: item.ingredientId,
                        displayName: item.displayName,
                        quantity: item.quantity,
                        unit: item.unit,
                        location: item.location,
                        minimumQuantity: item.minimumQuantity,
                        bestBefore: item.bestBefore.flatMap { Self.parseDay($0) },
                        revision: item.revision,
                        updatedAt: item.updatedAt ?? Date()
                    ))
                }
            }
            try? modelContext.save()
            loadFailed = false
        } catch {
            loadFailed = true
            errorMessage = SyncEngine.shared.online ? "Pantry yenilenemedi. Son kayıtlar gösteriliyor." : PantryCopy.offline
        }
    }

    private func dropConflicts() {
        let kept = PendingOperationStore.items(in: modelContext).filter { !PantrySync.isPantry($0) || $0.status != .requiresResolution }
        PendingOperationStore.replace(kept, in: modelContext)
    }

    private static func parseDay(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        return formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
}

struct PantryTransferSheet: View {
    @Environment(\.dismiss) private var dismiss
    var onChoose: (PantryTransferChoice) -> Void

    var body: some View {
        NavigationStack {
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
                Spacer()
            }
            .padding()
            .navigationTitle(PantryCopy.transferTitle)
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium])
    }

    private func choose(_ choice: PantryTransferChoice) {
        onChoose(choice)
        dismiss()
    }
}

/// Values shown in the pantry sheet. Built from the item up front so a reused sheet
/// cannot open on an empty amount, and so opening the sheet never writes stock.
struct PantryFormDraft: Equatable {
    var name: String
    var quantityText: String
    var unit: String
    var customUnit: String
    var markIncompatible: Bool
    var location: PantryLocation
    var hasMinimum: Bool
    var minimumText: String
    var hasDate: Bool
    var date: Date

    static let empty = PantryFormDraft(
        name: "",
        quantityText: "",
        unit: "piece",
        customUnit: "",
        markIncompatible: false,
        location: .pantry,
        hasMinimum: false,
        minimumText: "",
        hasDate: false,
        date: Date(timeIntervalSince1970: 0)
    )

    static func loaded(from item: PantryItem?) -> PantryFormDraft {
        guard let item else {
            var draft = empty
            draft.date = Date()
            return draft
        }
        return loaded(
            name: item.displayName,
            quantity: item.quantity,
            unit: item.unit,
            location: item.location,
            minimumQuantity: item.minimumQuantity,
            bestBefore: item.bestBefore
        )
    }

    static func loaded(
        name: String,
        quantity: Double,
        unit: String,
        location: PantryLocation,
        minimumQuantity: Double?,
        bestBefore: Date?,
        pickerUnits: [String] = GroceryViewModel.manualUnits
    ) -> PantryFormDraft {
        var draft = empty
        draft.date = Date()
        draft.name = name
        draft.quantityText = QuantityFormat.string(quantity)
        draft.location = location
        let canonical = UnitNormalization.parse(unit).code
        if PantryUnitPolicy.isKnown(unit), pickerUnits.contains(canonical) {
            draft.unit = canonical
            draft.markIncompatible = false
        } else {
            draft.markIncompatible = true
            draft.customUnit = unit
        }
        if let minimumQuantity {
            draft.hasMinimum = true
            draft.minimumText = QuantityFormat.string(minimumQuantity)
        }
        if let bestBefore {
            draft.hasDate = true
            draft.date = bestBefore
        }
        return draft
    }

    var resolvedUnit: String { markIncompatible ? customUnit : unit }

    /// Nil when the field is empty or not a finite, non-negative number. Never substitutes 0.
    var quantityToSave: Double? { Self.parseQuantity(quantityText) }

    var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && quantityToSave != nil
            && !resolvedUnit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static func parseQuantity(_ text: String) -> Double? {
        GroceryQuantityEdit.parse(text)
    }
}

private struct PantryForm: View {
    @Environment(\.dismiss) private var dismiss
    var item: PantryItem?
    @State private var draft: PantryFormDraft
    var onSave: (String, Double, String, PantryLocation, Double?, Date?, Bool) -> Void

    init(item: PantryItem?, onSave: @escaping (String, Double, String, PantryLocation, Double?, Date?, Bool) -> Void) {
        self.item = item
        self.onSave = onSave
        _draft = State(initialValue: PantryFormDraft.loaded(from: item))
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Malzeme", text: $draft.name)
                TextField("Miktar", text: $draft.quantityText).keyboardType(.decimalPad)
                if draft.markIncompatible {
                    TextField("Uyumsuz birim", text: $draft.customUnit)
                } else {
                    Picker("Birim", selection: $draft.unit) {
                        ForEach(GroceryViewModel.manualUnits, id: \.self) { code in
                            Text(UnitLabels.turkish(code)).tag(code)
                        }
                    }
                }
                Toggle("Uyumsuz birim", isOn: $draft.markIncompatible)
                Picker("Konum", selection: $draft.location) { ForEach(PantryLocation.allCases) { Text($0.title).tag($0) } }
                Toggle("Minimum miktar", isOn: $draft.hasMinimum)
                if draft.hasMinimum { TextField("Minimum", text: $draft.minimumText).keyboardType(.decimalPad) }
                Toggle("Son kullanma tarihi", isOn: $draft.hasDate)
                if draft.hasDate { DatePicker("Tarih", selection: $draft.date, displayedComponents: .date) }
            }
            .navigationTitle(item == nil ? "Pantry malzemesi" : "Malzemeyi düzenle")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("İptal") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(item == nil ? "Ekle" : "Kaydet") { save() }
                        .disabled(!draft.canSave)
                }
            }
            .task(id: item?.persistentModelID) { reload() }
            .onChange(of: item?.persistentModelID) { _, _ in reload() }
        }
    }

    private func reload() {
        draft = PantryFormDraft.loaded(from: item)
    }

    private func save() {
        guard let value = draft.quantityToSave else { return }
        let minValue = draft.hasMinimum ? PantryFormDraft.parseQuantity(draft.minimumText) : nil
        onSave(draft.name, value, draft.resolvedUnit, draft.location, minValue, draft.hasDate ? draft.date : nil, draft.markIncompatible)
        dismiss()
    }
}
