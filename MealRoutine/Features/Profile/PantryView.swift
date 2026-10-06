import SwiftData
import SwiftUI

struct PantryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var items: [PantryItem]
    @State private var showingAdd = false
    @State private var search = ""
    @State private var errorMessage: String?
    @State private var refreshing = false

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

    var body: some View {
        List {
            if visible.isEmpty {
                ContentUnavailableView {
                    Label("Pantry boş", systemImage: "shippingbox")
                } description: {
                    Text("Evdeki malzemelerini ekle. Planını ve marketini daha doğru hazırlayalım.")
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
                if refreshing { ProgressView().controlSize(.small) }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingAdd = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Pantry malzemesi ekle")
            }
        }
        .sheet(isPresented: $showingAdd) {
            PantryAddView { name, quantity, unit, location, minimum, date in
                add(name: name, quantity: quantity, unit: unit, location: location, minimum: minimum, date: date)
            }
        }
        .alert("Pantry güncellenemedi", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("Tamam", role: .cancel) {}
        } message: { Text(errorMessage ?? "") }
        .task { await refreshFromServer() }
        .refreshable { await refreshFromServer() }
    }

    @ViewBuilder
    private func row(_ item: PantryItem) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(item.displayName).font(.headline)
                Spacer()
                if item.isLowStock { Text("Azaldı").font(.caption.weight(.semibold)).foregroundStyle(.orange) }
            }
            HStack {
                Text(QuantityFormat.quantityAndUnit(quantity: item.quantity, unit: item.unit))
                Text("· \(item.location.title)")
                Spacer()
                if let date = item.bestBefore { Text(date.formatted(date: .abbreviated, time: .omitted)).foregroundStyle(item.isExpiredOrNear ? .orange : .secondary) }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                Button("−") { change(item, by: -1) }.buttonStyle(.bordered)
                Button("+") { change(item, by: 1) }.buttonStyle(.bordered)
                Spacer()
                Button("Bitti") { change(item, by: -item.quantity) }.font(.footnote.weight(.semibold))
            }
        }
        .padding(.vertical, 5)
        .swipeActions {
            Button(role: .destructive) { delete(item) } label: { Label("Sil", systemImage: "trash") }
        }
    }

    private func add(name: String, quantity: Double, unit: String, location: PantryLocation, minimum: Double?, date: Date?) {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, quantity >= 0 else { return }
        let item = PantryItem(
            householdID: householdID,
            ingredientID: clean.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current),
            displayName: clean,
            quantity: quantity,
            unit: unit,
            location: location,
            minimumQuantity: minimum,
            bestBefore: date
        )
        modelContext.insert(item)
        try? modelContext.save()
        syncCreate(item)
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

    private func api() -> PantryRepository? {
        guard let baseURL = MealRoutineConfig.apiBaseURL, AuthServices.sharedTokens.load() != nil else { return nil }
        return PantryRepository(client: APIClient(baseURL: baseURL, tokens: AuthServices.sharedTokens, refreshGate: AuthServices.refreshGate, expiry: AuthServices.expiry))
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

    private func syncCreate(_ item: PantryItem) {
        guard let householdID, let api = api(), let remote = remote(item) else { return }
        Task { @MainActor in
            do {
                let saved = try await api.create(householdId: householdID, item: remote)
                item.uuid = saved.id
                item.revision = saved.revision
                item.updatedAt = saved.updatedAt ?? .now
                try? modelContext.save()
            } catch { enqueue(.create, householdID, remote); errorMessage = "Sunucuya kaydedilemedi. Yerel kopya korunuyor; bağlantı gelince tekrar denenecek." }
        }
    }

    private func syncUpdate(_ item: PantryItem) {
        guard let householdID, let api = api(), let remote = remote(item, revision: max(1, item.revision - 1)) else { return }
        Task { @MainActor in
            do {
                let saved = try await api.update(householdId: householdID, item: remote)
                item.revision = saved.revision
                item.updatedAt = saved.updatedAt ?? .now
                try? modelContext.save()
            } catch { enqueue(.update, householdID, remote); errorMessage = "Bu malzeme başka bir cihazda güncellendi veya bağlantı kesildi." }
        }
    }

    private func syncDelete(_ item: PantryItem) {
        guard let householdID, let api = api(), let remote = remote(item) else { return }
        Task { do { try await api.delete(householdId: householdID, item: remote) } catch { await MainActor.run { enqueue(.delete, householdID, remote) } } }
    }

    private func refreshFromServer() async {
        guard let householdID, let api = api() else { return }
        refreshing = true
        defer { refreshing = false }
        do {
            await drainPending(householdID: householdID, api: api)
            for item in try await api.list(householdId: householdID) {
                if let local = items.first(where: { $0.uuid == item.id }) {
                    local.ingredientID = item.ingredientId
                    local.displayName = item.displayName
                    local.quantity = item.quantity
                    local.unit = item.unit
                    local.location = item.location
                    local.minimumQuantity = item.minimumQuantity
                    local.revision = item.revision
                    local.updatedAt = item.updatedAt ?? Date()
                } else {
                    modelContext.insert(PantryItem(uuid: item.id, householdID: householdID, ingredientID: item.ingredientId, displayName: item.displayName, quantity: item.quantity, unit: item.unit, location: item.location, minimumQuantity: item.minimumQuantity, bestBefore: item.bestBefore.flatMap { ISO8601DateFormatter().date(from: $0) }, revision: item.revision, updatedAt: item.updatedAt ?? Date()))
                }
            }
            try? modelContext.save()
        } catch { errorMessage = "Pantry yenilenemedi. Son kayıtlar gösteriliyor." }
    }

    private enum PantryAction: String { case create, update, delete }
    private func enqueue(_ action: PantryAction, _ householdID: UUID, _ item: PantryRemoteItem) {
        guard let payload = try? JSONEncoder().encode(PantryQueuedPayload(action: action.rawValue, householdID: householdID, item: item)) else { return }
        PendingOperationStore.upsert(SyncWorkItem(id: UUID(), entityType: "pantry", entityId: item.id.uuidString, operationType: action.rawValue, payload: payload, createdAt: .now, retryCount: 0, status: .pending), in: modelContext)
    }

    private func drainPending(householdID: UUID, api: PantryRepository) async {
        let queued = PendingOperationStore.items(in: modelContext).filter { $0.entityType == "pantry" }
        guard !queued.isEmpty else { return }
        var remaining = PendingOperationStore.items(in: modelContext).filter { $0.entityType != "pantry" }
        for work in queued {
            guard let payload = try? JSONDecoder().decode(PantryQueuedPayload.self, from: work.payload), payload.householdID == householdID else { remaining.append(work); continue }
            do {
                switch PantryAction(rawValue: payload.action) {
                case .create: _ = try await api.create(householdId: householdID, item: payload.item)
                case .update: _ = try await api.update(householdId: householdID, item: payload.item)
                case .delete: try await api.delete(householdId: householdID, item: payload.item)
                case nil: break
                }
            } catch { remaining.append(work) }
        }
        PendingOperationStore.replace(remaining, in: modelContext)
    }
}

private struct PantryQueuedPayload: Codable {
    var action: String
    var householdID: UUID
    var item: PantryRemoteItem
}

private struct PantryAddView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var quantity = ""
    @State private var unit = "piece"
    @State private var location: PantryLocation = .pantry
    @State private var hasMinimum = false
    @State private var minimum = ""
    @State private var hasDate = false
    @State private var date = Date()
    var onSave: (String, Double, String, PantryLocation, Double?, Date?) -> Void

    var body: some View {
        NavigationStack {
            Form {
                TextField("Malzeme", text: $name)
                TextField("Miktar", text: $quantity).keyboardType(.decimalPad)
                TextField("Birim (adet, g, kg, ml)", text: $unit)
                Picker("Konum", selection: $location) { ForEach(PantryLocation.allCases) { Text($0.title).tag($0) } }
                Toggle("Minimum miktar", isOn: $hasMinimum)
                if hasMinimum { TextField("Minimum", text: $minimum).keyboardType(.decimalPad) }
                Toggle("Son kullanma tarihi", isOn: $hasDate)
                if hasDate { DatePicker("Tarih", selection: $date, displayedComponents: .date) }
            }
            .navigationTitle("Pantry malzemesi")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("İptal") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Ekle") {
                        guard let value = Double(quantity.replacingOccurrences(of: ",", with: ".")) else { return }
                        let minValue = hasMinimum ? Double(minimum.replacingOccurrences(of: ",", with: ".")) : nil
                        onSave(name, value, unit, location, minValue, hasDate ? date : nil)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || Double(quantity.replacingOccurrences(of: ",", with: ".")) == nil)
                }
            }
        }
    }
}
