import SwiftUI
import GRDB

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
    @State private var selection: Int64?
    @State private var editor: StockAdjustContext?
    @State private var confirmDelete = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
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

                SectionHeading(title: "Stock on hand", count: balances.count)
                if balances.isEmpty {
                    Text("No products yet. Add products first.")
                        .font(DS.Font.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    balancesTable
                }

                SectionHeading(title: "Recent movements", count: movements.count)
                if movements.isEmpty {
                    Text("Stock movements appear here once production, sales or adjustments are recorded.")
                        .font(DS.Font.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    movementsTable
                }
            }
            .padding(DS.Spacing.xl)
            .frame(maxWidth: 1280)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(DS.Color.contentBackground)
        .navigationTitle("Stock")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    editor = StockAdjustContext()
                } label: {
                    Label("Adjust Stock", systemImage: "plus")
                }
                Button(role: .destructive) {
                    confirmDelete = confirmDelete
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .disabled(true)
                .hidden()
            }
        }
        .sheet(item: $editor) { context in
            StockAdjustView(context: context) { reload() }
        }
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
        Table(of: StockMovementRow.self) {
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
            ForEach(movements) { (row: StockMovementRow) in
                TableRow(row)
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

    private func reload() {
        do {
            let loaded = try db.dbQueue.read { db -> ([StockBalanceRow], [StockMovementRow]) in
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
                    let value = rate.map { Int64((Double(qty) * Double($0) / 1000).rounded()) } ?? 0
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
        let tonnes = Double(tonnesText.replacingOccurrences(of: ",", with: ".")) ?? 0
        return Int64((tonnes * 1000).rounded())
    }

    private var signedKg: Int64 {
        switch type {
        case .wastage, .adjustmentOut: -qtyKg
        default: qtyKg
        }
    }

    private var canSave: Bool {
        productId != nil && qtyKg > 0
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
                Button("Save") { save() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSave)
            }
            .padding(DS.Spacing.lg)
        }
        .frame(width: 480)
        .padding(.top, DS.Spacing.s)
        .task { loadProducts() }
    }

    private func loadProducts() {
        do {
            products = try db.dbQueue.read { db in
                try Product.filter(Column("isActive") == true).order(Column("sortOrder"), Column("name")).fetchAll(db)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func save() {
        guard let productID = productId else { return }
        do {
            try db.dbQueue.write { db in
                var movement = StockMovement(
                    productId: productID,
                    date: .now,
                    type: type,
                    qtyKg: signedKg,
                    remarks: trimmedNil(remarks)
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