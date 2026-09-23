import SwiftUI
import GRDB

struct ProductReportRow: Identifiable, Equatable {
    var id: Int64 { productId }
    var productId: Int64
    var name: String
    var producedKg: Int64
    var soldKg: Int64
    var onHandKg: Int64
}

struct CategoryReportRow: Identifiable, Equatable {
    var id: String { Purchase.Category(rawValue: category)?.label ?? category }
    var category: String
    var amountPaise: Int64
}

struct AgingBucketRow: Identifiable, Equatable {
    var id: String { label }
    var label: String
    var count: Int
    var amountPaise: Int64
}

struct AgingCustomerRow: Identifiable, Equatable {
    var id: Int64 { customerId }
    var customerId: Int64
    var name: String
    var amountPaise: Int64
    var ageDays: Int
}

struct ReportsModuleView: View {
    @Environment(\.appDatabase) private var db
    @State private var startDate: Date
    @State private var endDate: Date
    @State private var data: ReportData = ReportData()
    @State private var errorMessage: String?

    init() {
        let calendar = Calendar.current
        let start = calendar.date(from: calendar.dateComponents([.year, .month], from: .now)) ?? .now
        self._startDate = State(initialValue: start)
        self._endDate = State(initialValue: .now)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Spacing.xl) {
                PageHeader(
                    title: "Reports",
                    subtitle: "Period-based production, sales, expenses and GST summaries."
                )

                HStack(spacing: DS.Spacing.m) {
                    DatePicker("From", selection: $startDate, displayedComponents: .date)
                    DatePicker("To", selection: $endDate, displayedComponents: .date)
                    Button("Refresh") { reload() }
                        .buttonStyle(.borderedProminent)
                }
                .onChange(of: startDate) { _, _ in reload() }
                .onChange(of: endDate) { _, _ in reload() }

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 215), spacing: DS.Spacing.m, alignment: .top)],
                    spacing: DS.Spacing.m
                ) {
                    KPIValueCard(
                        title: "Production",
                        value: Format.tonnesLabel(data.producedKg),
                        icon: "gearshape.2.fill",
                        tint: DS.Color.info
                    )
                    KPIValueCard(
                        title: "Sales",
                        value: Format.inr(data.salesPaise),
                        footnote: "\(Format.tonnesLabel(data.soldKg)) sold",
                        icon: "doc.text.fill",
                        tint: DS.Color.success
                    )
                    KPIValueCard(
                        title: "Expenses",
                        value: Format.inr(data.expensesPaise),
                        icon: "cart.fill",
                        tint: DS.Color.warning
                    )
                    KPIValueCard(
                        title: "Collected",
                        value: Format.inr(data.collectedPaise),
                        icon: "indianrupeesign.circle.fill",
                        tint: DS.Color.info
                    )
                }

                CardContainer {
                    VStack(alignment: .leading, spacing: DS.Spacing.m) {
                        SectionHeading(title: "Mini P&L")
                        plRow("Sales", data.salesPaise, tint: .primary)
                        plRow("Expenses", data.expensesPaise, tint: .primary)
                        Divider()
                        HStack {
                            Text("Net")
                                .font(DS.Font.bodySemibold)
                            Spacer()
                            Text(Format.inr(data.netPaise))
                                .font(DS.Font.kpiValue)
                                .foregroundStyle(data.netPaise >= 0 ? DS.Color.success : DS.Color.danger)
                        }
                    }
                }

                HStack(alignment: .top, spacing: DS.Spacing.m) {
                    CardContainer {
                        VStack(alignment: .leading, spacing: DS.Spacing.m) {
                            SectionHeading(title: "GST summary")
                            gstRow("Taxable value", data.taxablePaise, tint: .primary)
                            gstRow("CGST", data.cgstPaise, tint: DS.Color.info)
                            gstRow("SGST", data.sgstPaise, tint: DS.Color.info)
                            gstRow("IGST", data.igstPaise, tint: DS.Color.info)
                            Divider()
                            HStack {
                                Text("Invoices")
                                Spacer()
                                Text("\(data.invoiceCount)")
                                    .font(DS.Font.tableValue)
                            }
                        }
                    }
                    .frame(width: 320)

                    CardContainer {
                        VStack(alignment: .leading, spacing: DS.Spacing.m) {
                            SectionHeading(title: "Expenses by category", count: data.expenseByCategory.count)
                            ForEach(data.expenseByCategory) { row in
                                HStack {
                                    Badge(
                                        text: Purchase.Category(rawValue: row.category)?.label ?? row.category,
                                        tint: DS.Color.warning
                                    )
                                    Spacer()
                                    Text(Format.inr(row.amountPaise))
                                        .font(DS.Font.tableValue)
                                }
                                .padding(.vertical, DS.Spacing.xs)
                            }
                        }
                    }
                    .frame(maxWidth: 420)
                }

                HStack(alignment: .top, spacing: DS.Spacing.m) {
                    CardContainer {
                        VStack(alignment: .leading, spacing: DS.Spacing.m) {
                            SectionHeading(title: "Receivables aging")
                            ForEach(data.agingBuckets) { bucket in
                                HStack {
                                    Badge(text: bucket.label, tint: DS.Color.warning)
                                    Spacer()
                                    Text("\(bucket.count)")
                                        .font(DS.Font.footnote)
                                        .foregroundStyle(.secondary)
                                    Text(Format.inr(bucket.amountPaise))
                                        .font(DS.Font.tableValue)
                                        .frame(minWidth: 110, alignment: .trailing)
                                }
                                .padding(.vertical, DS.Spacing.xs)
                            }
                            if data.agingBuckets.allSatisfy({ $0.count == 0 }) {
                                Text("No outstanding invoices for the current data.")
                                    .font(DS.Font.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .frame(width: 420)

                    CardContainer {
                        VStack(alignment: .leading, spacing: DS.Spacing.m) {
                            SectionHeading(title: "Customers with outstanding", count: data.agingCustomers.count)
                            ForEach(data.agingCustomers.prefix(8)) { row in
                                HStack(spacing: DS.Spacing.m) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(row.name)
                                            .font(DS.Font.bodySemibold)
                                        Text("\(row.ageDays) days outstanding")
                                            .font(DS.Font.footnote)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text(Format.inr(row.amountPaise))
                                        .font(DS.Font.tableValue)
                                }
                                .padding(.vertical, DS.Spacing.xs)
                            }
                            if data.agingCustomers.isEmpty {
                                Text("All invoices are settled.")
                                    .font(DS.Font.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .frame(maxWidth: 460)
                }

                SectionHeading(title: "Production & sales by product", count: data.byProduct.count)
                productTable
            }
            .padding(DS.Spacing.xl)
            .frame(maxWidth: 1280)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(DS.Color.contentBackground)
        .navigationTitle("Reports")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    exportCSV()
                } label: {
                    Label("Export CSV", systemImage: "square.and.arrow.up")
                }
                .disabled(data.byProduct.isEmpty && data.expenseByCategory.isEmpty)
            }
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
    private var productTable: some View {
        Table(of: ProductReportRow.self) {
            TableColumn("Product") { row in
                Text(row.name)
            }
            TableColumn("Produced") { row in
                Text(Format.tonnesLabel(row.producedKg))
                    .font(DS.Font.tableValue)
            }
            .width(min: 100, ideal: 120)
            TableColumn("Sold") { row in
                Text(Format.tonnesLabel(row.soldKg))
                    .font(DS.Font.tableValue)
            }
            .width(min: 100, ideal: 120)
            TableColumn("On hand") { row in
                Text(Format.tonnesLabel(row.onHandKg))
                    .foregroundStyle(.secondary)
            }
            .width(min: 100, ideal: 120)
        } rows: {
            ForEach(data.byProduct) { (row: ProductReportRow) in
                TableRow(row)
            }
        }
        .alternatingRowBackgrounds()
    }

    private func gstRow(_ title: String, _ paise: Int64, tint: SwiftUI.Color) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(Format.inr(paise))
                .font(DS.Font.tableValue)
                .foregroundStyle(tint)
        }
    }

    private func plRow(_ title: String, _ paise: Int64, tint: SwiftUI.Color) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(Format.inr(paise))
                .font(DS.Font.tableValue)
                .foregroundStyle(tint)
        }
    }

    private func exportCSV() {
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_IN")
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let from = Calendar.current.startOfDay(for: startDate)

        var rows: [[String]] = []
        rows.append(["PaashERP Report"])
        rows.append(["Period", dateFormatter.string(from: startDate), dateFormatter.string(from: endDate)])
        rows.append(["Production (t)", Format.tonnes(data.producedKg)])
        rows.append(["Sold (t)", Format.tonnes(data.soldKg)])
        rows.append(["Sales (₹)", Format.rupeesWithoutSymbol(data.salesPaise)])
        rows.append(["Expenses (₹)", Format.rupeesWithoutSymbol(data.expensesPaise)])
        rows.append(["Collected (₹)", Format.rupeesWithoutSymbol(data.collectedPaise)])
        rows.append(["Invoices", "\(data.invoiceCount)"])
        rows.append(["Taxable", Format.rupeesWithoutSymbol(data.taxablePaise)])
        rows.append(["CGST", Format.rupeesWithoutSymbol(data.cgstPaise)])
        rows.append(["SGST", Format.rupeesWithoutSymbol(data.sgstPaise)])
        rows.append(["IGST", Format.rupeesWithoutSymbol(data.igstPaise)])
        rows.append([])

        rows.append(["Expense by Category"])
        rows.append(["Category", "Amount (₹)"])
        for row in data.expenseByCategory {
            rows.append([Purchase.Category(rawValue: row.category)?.label ?? row.category, Format.rupeesWithoutSymbol(row.amountPaise)])
        }
        rows.append([])

        rows.append(["Production & Sales by Product"])
        rows.append(["Product", "Produced (t)", "Sold (t)", "On Hand (t)"])
        for row in data.byProduct {
            rows.append([
                row.name,
                Format.tonnes(row.producedKg),
                Format.tonnes(row.soldKg),
                Format.tonnes(row.onHandKg)
            ])
        }

        let content = CSVWriter.string(headers: [], rows: rows)
        let name = "paasherp-report-\(dateFormatter.string(from: from)).csv"
        DocumentExport.saveCSV(content, suggestedName: name)
    }

    private func reload() {
        let from = Calendar.current.startOfDay(for: startDate)
        let to = Calendar.current.startOfDay(for: endDate)
        let next = Calendar.current.date(byAdding: .day, value: 1, to: to) ?? to
        do {
            data = try db.dbQueue.read { db in
                var report = ReportData()

                struct AggRow: Decodable, FetchableRecord {
                    var productId: Int64
                    var qtyKg: Int64
                }
                report.producedKg = try Int64.fetchOne(
                    db,
                    sql: "SELECT COALESCE(SUM(qtyKg), 0) FROM stockMovements WHERE type = ? AND date >= ? AND date < ?",
                    arguments: [StockMovement.MoveType.production.rawValue, from, next]
                ) ?? 0
                report.soldKg = try Int64.fetchOne(
                    db,
                    sql: "SELECT COALESCE(SUM(-qtyKg), 0) FROM stockMovements WHERE type = ? AND date >= ? AND date < ?",
                    arguments: [StockMovement.MoveType.sale.rawValue, from, next]
                ) ?? 0
                report.salesPaise = try Int64.fetchOne(
                    db,
                    sql: "SELECT COALESCE(SUM(grandTotalPaise), 0) FROM salesInvoices WHERE date >= ? AND date < ?",
                    arguments: [from, next]
                ) ?? 0
                report.expensesPaise = try Int64.fetchOne(
                    db,
                    sql: "SELECT COALESCE(SUM(amountPaise), 0) FROM purchases WHERE date >= ? AND date < ?",
                    arguments: [from, next]
                ) ?? 0
                report.collectedPaise = try Int64.fetchOne(
                    db,
                    sql: "SELECT COALESCE(SUM(amountPaise), 0) FROM payments WHERE partyType = ? AND date >= ? AND date < ?",
                    arguments: [Payment.PartyType.customer.rawValue, from, next]
                ) ?? 0

                report.invoiceCount = try SalesInvoice.filter(Column("date") >= from && Column("date") < next).fetchCount(db)
                report.taxablePaise = try Int64.fetchOne(
                    db,
                    sql: "SELECT COALESCE(SUM(subtotalPaise), 0) FROM salesInvoices WHERE date >= ? AND date < ?",
                    arguments: [from, next]
                ) ?? 0
                report.cgstPaise = try Int64.fetchOne(
                    db,
                    sql: "SELECT COALESCE(SUM(cgstPaise), 0) FROM salesInvoices WHERE date >= ? AND date < ?",
                    arguments: [from, next]
                ) ?? 0
                report.sgstPaise = try Int64.fetchOne(
                    db,
                    sql: "SELECT COALESCE(SUM(sgstPaise), 0) FROM salesInvoices WHERE date >= ? AND date < ?",
                    arguments: [from, next]
                ) ?? 0
                report.igstPaise = try Int64.fetchOne(
                    db,
                    sql: "SELECT COALESCE(SUM(igstPaise), 0) FROM salesInvoices WHERE date >= ? AND date < ?",
                    arguments: [from, next]
                ) ?? 0

                struct CatRow: Decodable, FetchableRecord {
                    var category: String
                    var amountPaise: Int64
                }
                let catRows = try CatRow.fetchAll(
                    db,
                    sql: "SELECT category, SUM(amountPaise) AS amountPaise FROM purchases WHERE date >= ? AND date < ? GROUP BY category",
                    arguments: [from, next]
                )
                report.expenseByCategory = catRows.map { CategoryReportRow(category: $0.category, amountPaise: $0.amountPaise) }
                    .sorted { $0.amountPaise > $1.amountPaise }

                let produced = try AggRow.fetchAll(
                    db,
                    sql: "SELECT productId, SUM(qtyKg) AS qtyKg FROM stockMovements WHERE type = ? AND date >= ? AND date < ? GROUP BY productId",
                    arguments: [StockMovement.MoveType.production.rawValue, from, next]
                )
                let sold = try AggRow.fetchAll(
                    db,
                    sql: "SELECT productId, SUM(-qtyKg) AS qtyKg FROM stockMovements WHERE type = ? AND date >= ? AND date < ? GROUP BY productId",
                    arguments: [StockMovement.MoveType.sale.rawValue, from, next]
                )
                let onHand = try AggRow.fetchAll(
                    db,
                    sql: "SELECT productId, SUM(qtyKg) AS qtyKg FROM stockMovements GROUP BY productId"
                )
                let products = try Product.order(Column("sortOrder"), Column("name")).fetchAll(db)
                func lookup(_ rows: [AggRow], _ id: Int64) -> Int64 {
                    rows.first { $0.productId == id }?.qtyKg ?? 0
                }
                report.byProduct = products.map { product in
                    let id = product.id ?? 0
                    return ProductReportRow(
                        productId: id,
                        name: product.name,
                        producedKg: lookup(produced, id),
                        soldKg: lookup(sold, id),
                        onHandKg: lookup(onHand, id)
                    )
                }

                let allInvoices = try SalesInvoice.fetchAll(db)
                struct PaidRow: Decodable, FetchableRecord {
                    var invoiceId: Int64
                    var amountPaise: Int64
                }
                let paidRows = try PaidRow.fetchAll(
                    db,
                    sql: "SELECT invoiceId, SUM(amountPaise) AS amountPaise FROM payments WHERE partyType = ? AND invoiceId IS NOT NULL GROUP BY invoiceId",
                    arguments: [Payment.PartyType.customer.rawValue]
                )
                var paidByInvoice: [Int64: Int64] = [:]
                for row in paidRows {
                    paidByInvoice[row.invoiceId] = row.amountPaise
                }
                let calendar = Calendar.current
                let today = calendar.startOfDay(for: .now)
                var buckets = [
                    AgingBucketRow(label: "0–30 days", count: 0, amountPaise: 0),
                    AgingBucketRow(label: "31–60 days", count: 0, amountPaise: 0),
                    AgingBucketRow(label: "61–90 days", count: 0, amountPaise: 0),
                    AgingBucketRow(label: "90+ days", count: 0, amountPaise: 0)
                ]
                var customerTotals: [Int64: (amount: Int64, age: Int)] = [:]
                for invoice in allInvoices {
                    let due = invoice.grandTotalPaise - (paidByInvoice[invoice.id ?? 0] ?? 0)
                    guard due > 0 else { continue }
                    let days = calendar.dateComponents(
                        [.day],
                        from: calendar.startOfDay(for: invoice.date),
                        to: today
                    ).day ?? 0
                    let index = days <= 30 ? 0 : (days <= 60 ? 1 : (days <= 90 ? 2 : 3))
                    buckets[index].count += 1
                    buckets[index].amountPaise += due
                    var current = customerTotals[invoice.customerId] ?? (amount: 0, age: 0)
                    current.amount += due
                    if days > current.age { current.age = days }
                    customerTotals[invoice.customerId] = current
                }
                let allCustomers = try Customer.fetchAll(db)
                var nameById: [Int64: String] = [:]
                for customer in allCustomers {
                    if let id = customer.id { nameById[id] = customer.name }
                }
                report.agingBuckets = buckets
                report.agingCustomers = customerTotals.map { id, value in
                    AgingCustomerRow(
                        customerId: id,
                        name: nameById[id] ?? "Customer #\(id)",
                        amountPaise: value.amount,
                        ageDays: value.age
                    )
                }
                .sorted { $0.amountPaise > $1.amountPaise }
                return report
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

extension ReportsModuleView {
    struct ReportData: Equatable {
        var producedKg: Int64 = 0
        var soldKg: Int64 = 0
        var salesPaise: Int64 = 0
        var expensesPaise: Int64 = 0
        var collectedPaise: Int64 = 0
        var invoiceCount = 0
        var taxablePaise: Int64 = 0
        var cgstPaise: Int64 = 0
        var sgstPaise: Int64 = 0
        var igstPaise: Int64 = 0
        var byProduct: [ProductReportRow] = []
        var expenseByCategory: [CategoryReportRow] = []
        var agingBuckets: [AgingBucketRow] = []
        var agingCustomers: [AgingCustomerRow] = []

        var netPaise: Int64 { salesPaise - expensesPaise }
    }
}