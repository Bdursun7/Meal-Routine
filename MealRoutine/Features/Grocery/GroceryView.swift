import SwiftData
import SwiftUI

struct GroceryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var weeks: [PlanWeek]
    @State private var viewModel = GroceryViewModel()

    var body: some View {
        @Bindable var viewModel = self.viewModel
        let rows = viewModel.rows(weeks: weeks)
        NavigationStack {
            Group {
                if rows.isEmpty {
                    ContentUnavailableView {
                        Label("Market listesi boş", systemImage: "cart")
                    } description: {
                        Text("Bu haftanın yemeklerinden malzeme çıkmadı.")
                    } actions: {
                        Button("Listeyi oluştur") {
                            viewModel.rebuild(in: modelContext)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.accent)
                    }
                } else {
                    List {
                        if viewModel.conflictCount(in: rows) > 0 {
                            Section {
                                Label(
                                    "Aynı malzeme farklı birimlerde. Miktarlar toplanmadı; satırlar ayrı duruyor.",
                                    systemImage: "exclamationmark.triangle"
                                )
                                .font(.subheadline)
                                .foregroundStyle(.orange)
                            }
                        }
                        Section {
                            ForEach(rows) { row in
                                groceryRow(row)
                            }
                        } footer: {
                            Text("Aynı malzeme kimliği ve birim toplanır. Ev halkına göre ölçeklenir.")
                        }
                    }
                    .refreshable {
                        viewModel.rebuild(in: modelContext)
                    }
                }
            }
            .navigationTitle("Market")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        viewModel.isPresentingAdd = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Elle malzeme ekle")
                }
            }
            .sheet(isPresented: $viewModel.isPresentingAdd) {
                addSheet
            }
            .alert("Market listesi güncellenemedi", isPresented: alertIsPresented) {
                Button("Tamam", role: .cancel) {}
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
        }
        .onAppear {
            viewModel.rebuild(in: modelContext)
        }
    }

    private var alertIsPresented: Binding<Bool> {
        Binding(
            get: { viewModel.errorMessage != nil },
            set: { isPresented in
                if !isPresented { viewModel.errorMessage = nil }
            }
        )
    }

    private func groceryRow(_ row: GroceryRowPresentation) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Button {
                viewModel.toggle(row.id, in: modelContext)
            } label: {
                Image(systemName: row.isChecked ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(row.isChecked ? Theme.accent : Color.secondary)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(row.isChecked ? "Alındı" : "Alınacak")

            VStack(alignment: .leading, spacing: 2) {
                Text(row.name)
                    .strikethrough(row.isChecked)
                    .foregroundStyle(row.isChecked ? .secondary : .primary)
                Text(row.detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if row.hasUnitConflict {
                    Text("Birim çakışması")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                }
                if row.isManual {
                    Text("Elle eklendi")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .swipeActions {
            if row.isManual {
                Button(role: .destructive) {
                    viewModel.delete(row.id, in: modelContext)
                } label: {
                    Label("Sil", systemImage: "trash")
                }
            }
        }
    }

    private var addSheet: some View {
        @Bindable var viewModel = self.viewModel
        NavigationStack {
            Form {
                TextField("Malzeme", text: $viewModel.draftName)
                TextField("Miktar", text: $viewModel.draftQuantity)
                    .keyboardType(.decimalPad)
                Picker("Birim", selection: $viewModel.draftUnit) {
                    ForEach(GroceryViewModel.manualUnits, id: \.self) { unit in
                        Text(UnitLabels.turkish(unit)).tag(unit)
                    }
                }
            }
            .navigationTitle("Malzeme ekle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vazgeç") { viewModel.isPresentingAdd = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Ekle") { viewModel.addManual(in: modelContext) }
                        .disabled(viewModel.draftName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }
}
