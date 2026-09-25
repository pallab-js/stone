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
    @State private var errorMessage: String?

    var body: some View {
        MasterListView(
            rows: rows,
            navigationTitle: "Products",
            searchPrompt: "Search products",
            addLabel: "Add Product",
            emptyIcon: "cube.box",
            emptyTitle: "No products yet",
            emptyMessage: "Define the aggregates you crush and sell — Stone Dust, 6mm, 10mm, 20mm, 40mm, GSB, M-Sand. Add your first product to begin.",
            deleteConfirmationTitle: "Delete product?",
            deleteConfirmationMessage: "Unused products are removed. Products that appear in stock, production or invoice records are deactivated instead — existing records keep their snapshots.",
            filter: { row, query in
                row.product.name.localizedCaseInsensitiveContains(query)
                    || row.product.code.lowercased().contains(query.lowercased())
            },
            deactivationMessage: { row in
                "“\(row.product.name)” is used by stock, production or invoice records, so it was deactivated instead of deleted."
            },
            makeNewContext: { ProductEditorContext(product: nil, ratePaisePerTonne: nil) },
            makeEditContext: { ProductEditorContext(product: $0.product, ratePaisePerTonne: $0.ratePaisePerTonne) },
            editorSheet: { context, onSave in
                ProductEditorView(context: context, onSave: onSave)
            },
            deleteEntity: { database, id in
                try MasterDeletion.delete(Product.self, id: id, db: database)
            },
            table: productTable,
            onReload: { await reload() }
        )
        .alert("Something went wrong", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func productTable(
        _ selection: Binding<Int64?>,
        _ rows: [ProductRowModel],
        _ startEditing: @escaping (ProductRowModel) -> Void,
        _ deleteRow: @escaping (ProductRowModel) -> Void
    ) -> some View {
        Table(of: ProductRowModel.self, selection: selection) {
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
            ForEach(rows) { (row: ProductRowModel) in
                TableRow(row)
                    .contextMenu {
                        Button("Edit") { startEditing(row) }
                        Button("Delete", role: .destructive) { deleteRow(row) }
                    }
            }
        }
        .alternatingRowBackgrounds()
        .contextMenu(forSelectionType: Int64.self) { selections in
            if let id = selections.first, let row = rows.first(where: { $0.id == id }) {
                Button("Edit") { startEditing(row) }
                Button("Delete", role: .destructive) { deleteRow(row) }
            }
        }
    }

    private func reload() async {
        do {
            rows = try await db.readAsync { db in
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
            // %.2f, not %.0f: rates are stored in paise, so rounding to whole
            // rupees here would silently rewrite e.g. ₹6500.50 on every edit-save.
            initialValue: context.ratePaisePerTonne.map { String(format: "%.2f", Double($0) / 100.0) } ?? ""
        )
    }

    private var ratePaise: Int64? {
        guard let value = Format.parse(ratePerTonne) else { return nil }
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
                Button("Save") { Task { await save() } }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSave)
            }
            .padding(DS.Spacing.lg)
        }
        .frame(width: DS.SheetWidth.editor)
        .padding(.top, DS.Spacing.s)
    }

    private func save() async {
        let formCode = code.trimmingCharacters(in: .whitespaces).uppercased()
        let formName = name.trimmingCharacters(in: .whitespaces)
        let formCategory = category
        let formUnit = unit
        let formHsn = hsn.trimmingCharacters(in: .whitespaces)
        let formGstRateBps = gstRateBps
        let formSortOrder = sortOrder
        let formIsActive = isActive
        let formCftFactor = Format.parse(cftFactor)
        let formRatePaise = ratePaise
        let existingProduct = context.product
        do {
            try await db.writeAsync { db in
                var product = existingProduct ?? Product(code: "", name: "")
                product.code = formCode
                product.name = formName
                product.category = formCategory
                product.unit = formUnit
                product.hsn = formHsn
                product.gstRateBps = formGstRateBps
                product.sortOrder = formSortOrder
                product.isActive = formIsActive
                product.cftFactor = formCftFactor
                if product.id == nil {
                    product.createdAt = .now
                }
                product.updatedAt = .now
                try product.save(db)

                if let productID = product.id, let rate = formRatePaise {
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