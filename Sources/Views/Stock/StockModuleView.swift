import SwiftUI
import GRDB
import Charts

struct StockBalanceRow: Identifiable, Equatable {
    var id: Int64 { productId }
    var productId: Int64
    var name: String
    var code: String
    var isActive: Bool
    var qtyKg: Int64
    var valuePaise: Int64
    var unitRatePaise: Int64?
}

struct StockMovementRow: Identifiable, Equatable {
    var id: Int64 { movement.id ?? 0 }
    var movement: StockMovement
    var productName: String
}

struct StockModuleView: View {
    @Environment(\.appDatabase) private var db
    @State private var balances: [StockBalanceRow] = []
    @State private var movements: [StockMovementRow] = []
    @State private var movementSelection: StockMovementRow.ID?
    @State private var editor: StockAdjustContext?
    @State private var confirmDelete = false
    @State private var errorMessage: String?
    @State private var searchText = ""
    @State private var loaded = false

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xl) {
            PageHeader(
                title: "Stock",
                subtitle: "Live stock on hand per product and the full movement ledger."
            )

            KPIValueCard(
                title: "Total stock value",
                value: Format.inr(totalValuePaise),
                footnote: "\(Format.tonnesLabel(totalKg)) on hand across \(balances.count) products",
                icon: "shippingbox.fill",
                tint: DS.Color.accent
            )

            if !topValuation.isEmpty {
                CardContainer {
                    VStack(alignment: .leading, spacing: DS.Spacing.m) {
                        SectionHeading(title: "Valuation by product", count: topValuation.count)
                        Chart(topValuation) { row in
                            BarMark(
                                x: .value("Value", Double(row.valuePaise) / 100),
                                y: .value("Product", row.name)
                            )
                            .foregroundStyle(DS.Color.accent.opacity(0.85))
                            .cornerRadius(3)
                        }
                        .chartXAxis {
                            AxisMarks { value in
                                AxisGridLine()
                                if let rupees = value.as(Double.self) {
                                    AxisValueLabel {
                                        Text(Format.inrCompact(Int64(rupees * 100)))
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                        .chartYAxis {
                            AxisMarks { _ in
                                AxisValueLabel()
                                    .font(DS.Font.footnote)
                            }
                        }
                        .frame(height: 200)
                    }
                }
            }

            VStack(alignment: .leading, spacing: DS.Spacing.s) {
                SectionHeading(title: "Stock on hand", count: balances.count)
                if balances.isEmpty {
                    InlineEmptyState(
                        icon: "shippingbox",
                        title: "No stock on hand",
                        message: "Add products, then record production or opening stock to see live balances here."
                    )
                } else {
                    balancesTable
                }
            }

            VStack(alignment: .leading, spacing: DS.Spacing.s) {
                SectionHeading(title: "Recent movements", count: filteredMovements.count)
                if movements.isEmpty {
                    InlineEmptyState(
                        icon: "arrow.left.arrow.right",
                        title: "No movements yet",
                        message: "Stock movements appear here once production, sales or adjustments are recorded."
                    )
                } else if filteredMovements.isEmpty {
                    InlineEmptyState(
                        icon: "magnifyingglass",
                        title: "No matching movements",
                        message: "Nothing matches “\(searchText)”. Try product, type or remarks."
                    )
                } else {
                    movementsTable
                        .frame(maxHeight: .infinity)
                }
            }
        }
        .padding(DS.Spacing.xl)
        .frame(maxWidth: 1280)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(DS.Color.contentBackground)
        .navigationTitle("Stock")
        .loadingOverlay(!loaded)
        .searchable(text: $searchText, placement: .toolbar, prompt: "Search product, type or remarks")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    editor = StockAdjustContext()
                } label: {
                    Label("Adjust Stock", systemImage: "plus")
                }
                .keyboardShortcut("n", modifiers: .command)
                Button(role: .destructive) {
                    confirmDelete = true
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .keyboardShortcut(.delete, modifiers: [])
                .disabled(movementSelection == nil)
            }
        }
        .confirmationDialog(
            "Delete stock movement?",
            isPresented: $confirmDelete,
            titleVisibility: .visible
        ) {
            Button("Delete Movement", role: .destructive) { Task { await deleteSelected() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the movement from the stock ledger. Movements linked to a production batch or sales invoice cannot be deleted here.")
        }
        .sheet(item: $editor) { context in
            StockAdjustView(context: context) { Task { await reload() } }
        }
        .alert("Something went wrong", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .task { await reload(); loaded = true }
    }

    @ViewBuilder
    private var balancesTable: some View {
        Table(of: StockBalanceRow.self) {
            TableColumn("Product") { row in
                HStack(spacing: DS.Spacing.s) {
                    Text(row.name)
                        .font(DS.Font.bodySemibold)
                    if !row.isActive {
                        Badge(text: "Inactive", tint: DS.Color.warning)
                    }
                }
            }
            TableColumn("Code") { row in
                Text(row.code)
                    .font(DS.Font.captionMono)
                    .foregroundStyle(.secondary)
            }
            .width(min: 70, ideal: 90)
            TableColumn("On hand") { row in
                Text(Format.tonnesLabel(row.qtyKg))
                    .font(DS.Font.tableValue)
            }
            .width(min: 100, ideal: 120)
            TableColumn("Rate/tonne") { row in
                if let rate = row.unitRatePaise {
                    Text(Format.inr(rate))
                        .foregroundStyle(.secondary)
                } else {
                    Text("—").foregroundStyle(.tertiary)
                }
            }
            .width(min: 110, ideal: 130)
            TableColumn("Value") { row in
                Text(Format.inr(row.valuePaise))
                    .foregroundStyle(.secondary)
            }
            .width(min: 120, ideal: 140)
        } rows: {
            ForEach(balances) { (row: StockBalanceRow) in
                TableRow(row)
            }
        }
        .alternatingRowBackgrounds()
    }

    @ViewBuilder
    private var movementsTable: some View {
        Table(of: StockMovementRow.self, selection: $movementSelection) {
            TableColumn("Date") { row in
                Text(Format.shortDate(row.movement.date))
                    .foregroundStyle(.secondary)
            }
            .width(min: 90, ideal: 104)
            TableColumn("Product") { row in
                Text(row.productName)
            }
            TableColumn("Type") { row in
                Badge(text: row.movement.type.label, tint: tint(for: row.movement.type))
            }
            .width(min: 110, ideal: 130)
            TableColumn("Quantity") { row in
                Text(signedQuantity(row.movement.qtyKg))
                    .font(DS.Font.tableValue)
                    .foregroundStyle(row.movement.qtyKg < 0 ? DS.Color.danger : DS.Color.success)
            }
            .width(min: 100, ideal: 120)
            TableColumn("Remarks") { row in
                Text(row.movement.remarks ?? "")
                    .font(DS.Font.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        } rows: {
            ForEach(filteredMovements) { (row: StockMovementRow) in
                TableRow(row)
                    .contextMenu {
                        Button("Delete movement", role: .destructive) {
                            movementSelection = row.id
                            confirmDelete = true
                        }
                    }
            }
        }
        .alternatingRowBackgrounds()
    }

    private var totalKg: Int64 {
        balances.reduce(0) { $0 + $1.qtyKg }
    }

    private var totalValuePaise: Int64 {
        balances.reduce(0) { $0 + $1.valuePaise }
    }

    private var topValuation: [StockBalanceRow] {
        Array(
            balances
                .filter { $0.valuePaise > 0 }
                .sorted { $0.valuePaise > $1.valuePaise }
                .prefix(8)
        )
    }

    private var filteredMovements: [StockMovementRow] {
        guard !searchText.isEmpty else { return movements }
        let query = searchText.trimmingCharacters(in: .whitespaces).localizedLowercase
        return movements.filter { row in
            row.productName.localizedLowercase.contains(query)
                || row.movement.type.label.localizedLowercase.contains(query)
                || (row.movement.remarks ?? "").localizedLowercase.contains(query)
        }
    }

    private func deleteSelected() async {
        guard let selectedID = movementSelection,
              let row = movements.first(where: { $0.id == selectedID }) else { return }
        guard row.movement.refId == nil else {
            errorMessage = "This movement belongs to a production batch or sales invoice and can't be deleted here. Edit or delete the source record instead."
            movementSelection = nil
            return
        }
        let movementCopy = row.movement
        let balanceRows = balances
        do {
            try await db.writeAsync { db in
                if movementCopy.qtyKg > 0 {
                    // Deleting a credit (opening/adjustment-in) removes stock;
                    // block if what remains on hand can't absorb it.
                    try StockGate.requireForRemoval(
                        db: db,
                        removingKg: movementCopy.qtyKg,
                        productID: movementCopy.productId,
                        productName: { pid in balanceRows.first(where: { $0.productId == pid })?.name }
                    )
                }
                try StockMovement.deleteOne(db, key: movementCopy.id ?? 0)
            }
            movementSelection = nil
            await reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func signedQuantity(_ kg: Int64) -> String {
        let sign = kg < 0 ? "−" : "+"
        return "\(sign)\(Format.tonnesLabel(abs(kg)))"
    }

    private func tint(for type: StockMovement.MoveType) -> SwiftUI.Color {
        switch type {
        case .production: DS.Color.info
        case .sale, .wastage, .adjustmentOut: DS.Color.danger
        case .opening, .adjustmentIn: DS.Color.success
        }
    }

    private func reload() async {
        do {
            let loaded = try await db.readAsync { db -> ([StockBalanceRow], [StockMovementRow]) in
                struct BalanceRow: Decodable, FetchableRecord {
                    var productId: Int64
                    var qtyKg: Int64
                }
                let balances = try BalanceRow.fetchAll(
                    db,
                    sql: "SELECT productId, SUM(qtyKg) AS qtyKg FROM stockMovements GROUP BY productId"
                )
                let products = try Product.order(Column("sortOrder"), Column("name")).fetchAll(db)
                let allRates = try ProductRate.order(Column("id")).fetchAll(db)
                var latest: [Int64: Int64] = [:]
                for rate in allRates {
                    latest[rate.productId] = rate.ratePaisePerTonne
                }
                var balanceByProduct: [Int64: Int64] = [:]
                for balance in balances {
                    balanceByProduct[balance.productId] = balance.qtyKg
                }
                let stockRows = products.map { product in
                    let qty = balanceByProduct[product.id ?? 0] ?? 0
                    let rate = latest[product.id ?? 0]
                    let value = rate.map { StockValuation.value(ratePaisePerTonne: $0, qtyKg: qty) } ?? 0
                    return StockBalanceRow(
                        productId: product.id ?? 0,
                        name: product.name,
                        code: product.code,
                        isActive: product.isActive,
                        qtyKg: qty,
                        valuePaise: value,
                        unitRatePaise: rate
                    )
                }

                let movementRows = try StockMovement.order(Column("date").desc, Column("id").desc).limit(300).fetchAll(db)
                let productName = Dictionary(uniqueKeysWithValues: products.compactMap { product in
                    product.id.map { ($0, product.name) }
                })
                let moves = movementRows.map { movement in
                    StockMovementRow(
                        movement: movement,
                        productName: productName[movement.productId] ?? "Product #\(movement.productId)"
                    )
                }
                return (stockRows, moves)
            }
            balances = loaded.0
            movements = loaded.1
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct StockAdjustContext: Identifiable {
    let id = UUID()
    let productId: Int64?
    let type: StockMovement.MoveType
    let qtyKg: Int64

    init(productId: Int64? = nil, type: StockMovement.MoveType = .adjustmentIn, qtyKg: Int64 = 0) {
        self.productId = productId
        self.type = type
        self.qtyKg = qtyKg
    }
}

struct StockAdjustView: View {
    @Environment(\.appDatabase) private var db
    @Environment(\.dismiss) private var dismiss
    let context: StockAdjustContext
    let onSave: () -> Void

    @State private var productId: Int64?
    @State private var type: StockMovement.MoveType
    @State private var tonnesText: String
    @State private var remarks: String
    @State private var products: [Product] = []
    @State private var errorMessage: String?

    init(context: StockAdjustContext, onSave: @escaping () -> Void) {
        self.context = context
        self.onSave = onSave
        _productId = State(initialValue: context.productId)
        _type = State(initialValue: context.type)
        _tonnesText = State(initialValue: context.qtyKg > 0 ? String(format: "%.3f", Double(context.qtyKg) / 1000) : "")
        _remarks = State(initialValue: "")
    }

    private var qtyKg: Int64 {
        Format.kg(fromTonnes: tonnesText)
    }

    private var signedKg: Int64 {
        switch type {
        case .wastage, .adjustmentOut: -qtyKg
        default: qtyKg
        }
    }

    private var canSave: Bool {
        productId != nil && qtyKg > 0 && type != .sale && type != .production
    }

    var body: some View {
        VStack(spacing: 0) {
            Text("Adjust Stock")
                .font(DS.Font.sectionTitle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding([.top, .horizontal], DS.Spacing.lg)
                .padding(.bottom, DS.Spacing.s)

            Form {
                Section("Adjustment") {
                    Picker("Product", selection: $productId) {
                        Text("Select product").tag(Int64?.none)
                        ForEach(products) { product in
                            Text(product.name).tag(Int64?(product.id ?? 0))
                        }
                    }
                    Picker("Type", selection: $type) {
                        Text("Opening Stock").tag(StockMovement.MoveType.opening)
                        Text("Wastage").tag(StockMovement.MoveType.wastage)
                        Text("Adjustment In").tag(StockMovement.MoveType.adjustmentIn)
                        Text("Adjustment Out").tag(StockMovement.MoveType.adjustmentOut)
                    }
                    TextField("Quantity (tonnes)", text: $tonnesText)
                    TextField("Remarks", text: $remarks)
                    Text("Effect: \(signedKg < 0 ? "−" : "+")\(Format.tonnesLabel(abs(signedKg)))")
                        .font(DS.Font.footnote)
                        .foregroundStyle(signedKg < 0 ? DS.Color.danger : DS.Color.success)
                }
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
        .task { await loadProducts() }
    }

    private func loadProducts() async {
        do {
            products = try await db.readAsync { db in
                try Product.filter(Column("isActive") == true).order(Column("sortOrder"), Column("name")).fetchAll(db)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func save() async {
        guard let productID = productId else { return }
        let formType = type
        let formQtyKg = qtyKg
        let formSignedKg = signedKg
        let formRemarks = trimmedNil(remarks)
        let productRows = products
        do {
            try await db.writeAsync { db in
                if formType == .wastage || formType == .adjustmentOut {
                    try StockGate.requireForRemoval(
                        db: db,
                        removingKg: formQtyKg,
                        productID: productID,
                        productName: { pid in productRows.first(where: { $0.id == pid })?.name }
                    )
                }
                var movement = StockMovement(
                    productId: productID,
                    date: .now,
                    type: formType,
                    qtyKg: formSignedKg,
                    remarks: formRemarks
                )
                try movement.insert(db)
            }
            onSave()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func trimmedNil(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}