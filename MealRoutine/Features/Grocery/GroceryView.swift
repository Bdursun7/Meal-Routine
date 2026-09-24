import SwiftData
import SwiftUI

struct GroceryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var weeks: [PlanWeek]
    @State private var viewModel = GroceryViewModel()

    var body: some View {
        @Bindable var viewModel = self.viewModel
        let fullList = viewModel.presentation(weeks: weeks)
        let list = viewModel.applyingSearch(to: fullList)
        NavigationStack {
            List {
                if fullList.isEmpty {
                    Section {
                        WarmEmptyState(
                            title: "Market henüz dolmadı",
                            message: "Haftanın yemekleri hazır olunca malzemeler burada, reyona göre toplanır.",
                            symbolName: "cart",
                            accentSymbolName: "leaf.fill",
                            actionTitle: "Listeyi oluştur",
                            action: { viewModel.rebuild(in: modelContext) }
                        )
                        .listRowBackground(Theme.bgCream)
                    }
                } else if list.isEmpty {
                    Section {
                        WarmEmptyState(
                            title: "Sonuç yok",
                            message: "Bu aramayla eşleşen malzeme yok.",
                            symbolName: "magnifyingglass",
                            accentSymbolName: "cart",
                            isCompact: true
                        )
                        .listRowBackground(Theme.bgCream)
                    }
                } else {
                    marketSections(list)
                }
            }
            .refreshable {
                viewModel.rebuild(in: modelContext)
            }
            .mealCanvas()
            .navigationTitle("Market")
            .searchable(
                text: $viewModel.searchText,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Malzeme ara"
            )
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
            Analytics.track(.groceryOpened)
        }
    }

    @ViewBuilder
    private func marketSections(_ list: GroceryListPresentation) -> some View {
        Section {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "cart.fill")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 44, height: 44)
                    .background(
                        Theme.accent.opacity(0.12),
                        in: RoundedRectangle(cornerRadius: Theme.chipRadius, style: .continuous)
                    )
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(list.checkedCount)/\(list.totalCount) alındı")
                        .font(.headline)
                        .foregroundStyle(Theme.textCharcoal)
                    Text(progressDetail(list))
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    ThinSageProgress(
                        value: Double(list.checkedCount),
                        total: Double(max(list.totalCount, 1))
                    )
                }
            }
            .padding(.vertical, 6)
            .listRowBackground(Theme.card)
        }
        if list.conflictCount > 0 {
            Section {
                Label(
                    "Aynı malzeme uyumsuz birimlerde. Bu satırlar birbirine katılmadı.",
                    systemImage: "exclamationmark.triangle"
                )
                .font(.subheadline)
                .foregroundStyle(.orange)
            }
        }
        ForEach(list.openSections) { section in
            Section {
                aisleHeader(section, in: list)
                    .listRowInsets(EdgeInsets(top: 14, leading: 16, bottom: 6, trailing: 16))
                    .listRowBackground(Theme.bgCream)
                    .listRowSeparator(.hidden)
                ForEach(section.rows) { row in
                    groceryRow(row)
                        .listRowBackground(Theme.cardSurface)
                }
            }
        }
        if !list.checked.isEmpty {
            Section("Alındı") {
                ForEach(list.checked) { row in
                    groceryRow(row, showsAisle: true)
                        .listRowBackground(Theme.card)
                }
            }
        }
        Section {
            Text("Aynı malzeme kimliği toplanır. Her akşam kendi porsiyonuna göre ölçeklenir; bu, ev halkı ya da tarifte kaydettiğin akşamdır. Eş anlamlı birimler birleşir; gram–kilogram ve mililitre–litre çevrilir. Alınan ürünler listenin altına iner.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func aisleHeader(_ section: GrocerySectionPresentation, in list: GroceryListPresentation) -> some View {
        let done = list.checked.filter { $0.category == section.category }.count
        let total = section.rows.count + done
        let tint = section.category == .produce || section.category == .protein
            ? Theme.accent.opacity(0.15)
            : Theme.sage.opacity(0.22)
        return HStack(alignment: .center, spacing: 12) {
            Image(systemName: section.category.symbolName)
                .font(.body.weight(.semibold))
                .foregroundStyle(section.category == .produce || section.category == .protein ? Theme.accent : Theme.sage)
                .frame(width: 36, height: 36)
                .background(tint, in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(section.category.title)
                        .font(.headline)
                        .foregroundStyle(Theme.textCharcoal)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    Text("\(done)/\(total)")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.secondaryText)
                }
                ThinSageProgress(value: Double(done), total: Double(max(total, 1)), height: 6)
            }
        }
        .textCase(nil)
        .padding(.vertical, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(section.category.title). \(done) / \(total) alındı")
    }

    private func groceryAccessibilityLabel(_ row: GroceryRowPresentation) -> String {
        if row.isChecked { return "\(row.name) alındı" }
        if let remaining = row.remainingDetail {
            return "\(row.name), \(remaining)"
        }
        return "\(row.name) alınacak"
    }

    private func progressDetail(_ list: GroceryListPresentation) -> String {
        let remaining = list.totalCount - list.checkedCount
        if remaining == 0 { return "Liste tamam" }
        return "\(remaining) ürün · \(list.openSections.count) grup kaldı"
    }

    private var alertIsPresented: Binding<Bool> {
        Binding(
            get: { viewModel.errorMessage != nil },
            set: { isPresented in
                if !isPresented { viewModel.errorMessage = nil }
            }
        )
    }

    private func groceryRow(_ row: GroceryRowPresentation, showsAisle: Bool = false) -> some View {
        @Bindable var viewModel = self.viewModel
        return HStack(alignment: .top, spacing: 12) {
            Button {
                viewModel.toggle(row.id, in: modelContext)
            }             label: {
                MealCheckBox(isChecked: row.isChecked)
                    .frame(minWidth: 44, minHeight: 44)
            }
            .buttonStyle(.borderless)
            .sensoryFeedback(.selection, trigger: row.isChecked)
            .accessibilityLabel(groceryAccessibilityLabel(row))
            .accessibilityHint(row.isChecked ? "İşareti kaldırır" : "Alındı olarak işaretler")

            VStack(alignment: .leading, spacing: 2) {
                Text(row.name)
                    .strikethrough(row.isChecked)
                    .foregroundStyle(row.isChecked ? Theme.secondaryText : Theme.textCharcoal)
                    .fixedSize(horizontal: false, vertical: true)
                GroceryQuantityControl(row: row, viewModel: viewModel)
                if let remaining = row.remainingDetail, !row.isChecked {
                    Text(remaining)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if row.hasUnitConflict {
                    Text("Birim çakışması")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                }
                if showsAisle {
                    Text(row.category.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
        return NavigationStack {
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
        .presentationBackground(Theme.canvas)
        .mealAppearance()
    }
}

private struct GroceryQuantityControl: View {
    var row: GroceryRowPresentation
    @Bindable var viewModel: GroceryViewModel
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        if viewModel.editingID == row.id {
            VStack(alignment: .leading, spacing: 8) {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 4) {
                        amountField
                        Text(row.unitLabel)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    HStack(spacing: 8) {
                        amountField
                        Text(row.unitLabel)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                HStack(spacing: 12) {
                    Button("Kaydet") {
                        viewModel.commitQuantity(in: modelContext)
                    }
                    .font(.subheadline.weight(.semibold))
                    .frame(minHeight: 44)
                    .accessibilityHint("Miktarı kaydeder. Birim aynı kalır.")
                    Button("Vazgeç") {
                        viewModel.cancelQuantityEdit()
                    }
                    .font(.subheadline)
                    .frame(minHeight: 44)
                }
            }
        } else if row.canEditQuantity {
            Button {
                viewModel.beginQuantityEdit(row)
            } label: {
                Text(row.detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(minHeight: 44, alignment: .leading)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("\(row.name) miktarı \(row.detail)")
            .accessibilityHint("Miktarı düzenler, birim aynı kalır")
        } else {
            Text(row.detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var amountField: some View {
        TextField("Miktar", text: $viewModel.editingQuantity)
            .keyboardType(.decimalPad)
            .textFieldStyle(.roundedBorder)
            .frame(maxWidth: 140)
            .accessibilityLabel("Yeni miktar")
    }
}
