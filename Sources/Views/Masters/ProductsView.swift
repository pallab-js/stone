import SwiftUI
import GRDB

struct ProductRowModel: Identifiable, Equatable {
    var product: Product
    var ratePaisePerTonne: Int64?
    var id: Int64 { product.id ?? 0 }
}

struct ProductsView: View {
    @Environment(\.appDatabase) private var db
    @State private var rows: [ProductRowModel] = []
    @State private var search = ""
    @State private var selection: ProductRowModel.ID?
    @State private var editor: ProductEditorContext?
    @State private var confirmDelete = false
    @State private var errorMessage: String?

    private var filteredRows: [ProductRowModel] {
        guard !search.isEmpty else { return rows }
        return rows.filter {
            $0.product.name.localizedCaseInsensitiveContains(search)
                || $0.product.code.lowercased().contains(search.lowercased())
        }
    }

    var body: some View {
        Group {
            if filteredRows.isEmpty {
                EmptyStateView(
                    icon: "cube.box",
                    title: search.isEmpty ? "No products yet" : "No matches for “\(search)”",
                    message: "Define the aggregates you crush and sell — Stone Dust, 6mm, 10mm, 20mm, 40mm, GSB, M-Sand. Add your first product to begin."
                )
            } else {
                table
            }
        }
        .searchable(text: $search, prompt: "Search products")
        .navigationTitle("Products")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    editor = ProductEditorContext(product: nil, ratePaisePerTonne: nil)
                } label: {
                    Label("Add Product", systemImage: "plus")
                }
                Button {
                    if let row = selectedRow { startEditing(row) }
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
                .disabled(selection == nil)
                Button(role: .destructive) {
                    confirmDelete = true
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .disabled(selection == nil)
            }
        }
        .sheet(item: $editor) { context in
            ProductEditorView(context: context) {
                reload()
            }
        }
        .destructiveConfirmation(
            title: "Delete product?",
            message: "This removes the product record. Existing invoices keep their own snapshots.",
            destructiveLabel: "Delete",
            isPresented: $confirmDelete
        ) { deleteSelected() }
        .alert("Something went wrong", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .task { reload() }
    }

    @ViewBuilder
    private var table: some View {
        Table(of: ProductRowModel.self, selection: $selection) {
            TableColumn("Code") { row in
                Text(row.product.code)
                    .font(DS.Font.bodySemibold)
            }
            .width(min: 70, ideal: 90)
            TableColumn("Product") { row in
                Text(row.product.name)
            }
            TableColumn("Category") { row in
                Text(row.product.category.capitalized)
                    .foregroundStyle(.secondary)
            }
            TableColumn("HSN") { row in
                Text(row.product.hsn)
                    .font(DS.Font.captionMono)
                    .foregroundStyle(.secondary)
            }
            TableColumn("GST") { row in
                Text(Format.percent(bps: row.product.gstRateBps))
            }
            .width(min: 55, ideal: 64)
            TableColumn("Rate/tonne") { row in
                if let rate = row.ratePaisePerTonne {
                    Text(Format.inr(rate))
                        .font(DS.Font.tableValue)
                } else {
                    Text("—")
                        .foregroundStyle(.tertiary)
                }
            }
            .width(min: 100, ideal: 120)
            TableColumn("Status") { row in
                Badge(
                    text: row.product.isActive ? "Active" : "Inactive",
                    tint: DS.Color.status(row.product.isActive)
                )
            }
            .width(min: 80, ideal: 90)
        } rows: {
            ForEach(filteredRows) { (row: ProductRowModel) in
                TableRow(row)
                    .contextMenu { rowContextMenu(row) }
            }
        }
        .alternatingRowBackgrounds()
        .contextMenu(forSelectionType: ProductRowModel.ID?.self) { selections in
            if let first = selections.first, let id = first, let row = rows.first(where: { $0.id == id }) {
                Button("Edit") { startEditing(row) }
            }
            Button("Delete", role: .destructive) { confirmDelete = true }
        }
    }

    private var selectedRow: ProductRowModel? {
        guard let selection else { return nil }
        return rows.first { $0.id == selection }
    }

    private func startEditing(_ row: ProductRowModel) {
        editor = ProductEditorContext(product: row.product, ratePaisePerTonne: row.ratePaisePerTonne)
    }

    private func rowContextMenu(_ row: ProductRowModel) -> some View {
        Group {
            Button("Edit") { startEditing(row) }
            Button("Delete", role: .destructive) {
                selection = row.id
                confirmDelete = true
            }
        }
    }

    private func deleteSelected() {
        guard let id = selection,
              let row = rows.first(where: { $0.id == id }),
              let productID = row.product.id else { return }
        do {
            try db.dbQueue.write { db in
                try Product.deleteOne(db, key: productID)
            }
            reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func reload() {
        do {
            rows = try db.dbQueue.read { db in
                let products = try Product.order(Column("sortOrder"), Column("name")).fetchAll(db)
                let rates = try ProductRate.order(Column("id")).fetchAll(db)
                var latest: [Int64: Int64] = [:]
                for rate in rates {
                    latest[rate.productId] = rate.ratePaisePerTonne
                }
                return products.map { ProductRowModel(product: $0, ratePaisePerTonne: latest[$0.id ?? 0]) }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct ProductEditorContext: Identifiable {
    let id = UUID()
    let product: Product?
    let ratePaisePerTonne: Int64?
}

struct ProductEditorView: View {
    @Environment(\.appDatabase) private var db
    @Environment(\.dismiss) private var dismiss
    let context: ProductEditorContext
    let onSave: () -> Void

    @State private var code: String
    @State private var name: String
    @State private var category: String
    @State private var unit: String
    @State private var hsn: String
    @State private var gstRateBps: Int
    @State private var sortOrder: Int
    @State private var isActive: Bool
    @State private var cftFactor: String
    @State private var ratePerTonne: String
    @State private var errorMessage: String?

    private static let categories = ["aggregate", "msand", "gsb", "other"]
    private static let gstRates = [0, 5, 12, 18]

    init(context: ProductEditorContext, onSave: @escaping () -> Void) {
        self.context = context
        self.onSave = onSave
        let product = context.product ?? Product(code: "", name: "")
        _code = State(initialValue: product.code)
        _name = State(initialValue: product.name)
        _category = State(initialValue: product.category)
        _unit = State(initialValue: product.unit)
        _hsn = State(initialValue: product.hsn)
        _gstRateBps = State(initialValue: product.gstRateBps)
        _sortOrder = State(initialValue: product.sortOrder)
        _isActive = State(initialValue: product.isActive)
        _cftFactor = State(
            initialValue: product.cftFactor.map { String(format: "%.2f", $0) } ?? ""
        )
        _ratePerTonne = State(
            initialValue: context.ratePaisePerTonne.map { String(format: "%.0f", Double($0) / 100.0) } ?? ""
        )
    }

    private var ratePaise: Int64? {
        guard let value = Double(ratePerTonne.trimmingCharacters(in: .whitespaces)) else { return nil }
        return Int64((value * 100).rounded())
    }

    private var canSave: Bool {
        !code.trimmingCharacters(in: .whitespaces).isEmpty
            && !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            Text(context.product == nil ? "Add Product" : "Edit Product")
                .font(DS.Font.sectionTitle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding([.top, .horizontal], DS.Spacing.lg)
                .padding(.bottom, DS.Spacing.m)

            Form {
                TextField("Material code", text: $code)
                    .textFieldStyle(.roundedBorder)
                TextField("Product name", text: $name)
                    .textFieldStyle(.roundedBorder)
                Picker("Category", selection: $category) {
                    ForEach(Self.categories, id: \.self) { Text($0.capitalized) }
                }
                Picker("GST rate", selection: $gstRateBps) {
                    ForEach(Self.gstRates, id: \.self) { rate in
                        Text("\(rate)%").tag(rate * 100)
                    }
                }
                TextField("HSN code", text: $hsn)
                    .textFieldStyle(.roundedBorder)
                TextField("Rate per tonne (₹)", text: $ratePerTonne)
                    .textFieldStyle(.roundedBorder)
                TextField("cft conversion factor", text: $cftFactor)
                    .textFieldStyle(.roundedBorder)
                Toggle("In active use", isOn: $isActive)
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)

            HStack {
                if let errorMessage {
                    Text(errorMessage)
                        .font(DS.Font.footnote)
                        .foregroundStyle(DS.Color.danger)
                        .lineLimit(2)
                }
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") { save() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSave)
            }
            .padding(DS.Spacing.lg)
        }
        .frame(width: 460)
        .padding(.top, DS.Spacing.s)
    }

    private func save() {
        do {
            try db.dbQueue.write { db in
                var product = context.product ?? Product(code: "", name: "")
                product.code = code.trimmingCharacters(in: .whitespaces).uppercased()
                product.name = name.trimmingCharacters(in: .whitespaces)
                product.category = category
                product.unit = unit
                product.hsn = hsn.trimmingCharacters(in: .whitespaces)
                product.gstRateBps = gstRateBps
                product.sortOrder = sortOrder
                product.isActive = isActive
                product.cftFactor = Double(cftFactor)
                if product.id == nil {
                    product.createdAt = .now
                }
                product.updatedAt = .now
                try product.save(db)

                if let productID = product.id, let rate = ratePaise {
                    let day = Calendar.current.startOfDay(for: .now)
                    if let existing = try ProductRate
                        .filter(Column("productId") == productID && Column("effectiveDate") == day)
                        .fetchOne(db)
                    {
                        var updated = existing
                        updated.ratePaisePerTonne = rate
                        try updated.update(db)
                    } else {
                        var newRate = ProductRate(productId: productID, effectiveDate: day, ratePaisePerTonne: rate)
                        try newRate.insert(db)
                    }
                }
            }
            onSave()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}