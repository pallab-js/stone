import SwiftUI
import Charts
import GRDB

struct OverviewView: View {
    @Environment(\.appDatabase) private var db
    @State private var snapshot: Snapshot = Snapshot.empty

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Spacing.xl) {
                PageHeader(
                    title: "Dashboard",
                    subtitle: snapshot.businessName
                )

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 215), spacing: DS.Spacing.m, alignment: .top)],
                    spacing: DS.Spacing.m
                ) {
                    KPIValueCard(
                        title: "Today's Production",
                        value: Format.tonnesLabel(snapshot.todayProductionKg),
                        icon: "gearshape.2.fill",
                        tint: DS.Color.info
                    )
                    KPIValueCard(
                        title: "Today's Sales",
                        value: Format.inr(snapshot.todaySalesPaise),
                        icon: "doc.text.fill",
                        tint: DS.Color.success
                    )
                    KPIValueCard(
                        title: "Outstanding Receivables",
                        value: Format.inr(snapshot.outstandingPaise),
                        footnote: snapshot.openInvoicesText,
                        icon: "indianrupeesign.circle.fill",
                        tint: DS.Color.warning
                    )
                    KPIValueCard(
                        title: "Stock on Hand",
                        value: Format.tonnesLabel(snapshot.totalStockKg),
                        footnote: "Valued at \(Format.inr(snapshot.stockValuePaise))",
                        icon: "shippingbox.fill",
                        tint: DS.Color.accent
                    )
                }

                if snapshot.lowStock.isNotEmpty {
                    SectionHeading(title: "Low stock alert")
                    CardContainer {
                        ForEach(snapshot.lowStock) { item in
                            HStack {
                                Label(item.name, systemImage: "exclamationmark.triangle.fill")
                                    .foregroundStyle(DS.Color.warning)
                                Spacer()
                                Text("\(Format.tonnesLabel(item.qtyKg)) left")
                                    .font(DS.Font.captionMono)
                            }
                            .padding(.vertical, DS.Spacing.xs)
                        }
                    }
                }

                if snapshot.chart.isNotEmpty {
                    SectionHeading(title: "Last 14 days — production vs sales")
                    CardContainer {
                        Chart(snapshot.chart) { point in
                            BarMark(
                                x: .value("Day", point.label),
                                y: .value("Production (t)", point.productionKg / 1000)
                            )
                            .foregroundStyle(by: .value("Series", "Production"))
                            BarMark(
                                x: .value("Day", point.label),
                                y: .value("Sales (₹)", point.salesPaise / 100)
                            )
                            .foregroundStyle(by: .value("Series", "Sales"))
                        }
                        .chartForegroundStyleScale([
                            "Production": DS.Color.info,
                            "Sales": DS.Color.success
                        ])
                        .frame(height: 240)
                    }
                }

                HStack(alignment: .top, spacing: DS.Spacing.m) {
                    CardContainer {
                        VStack(alignment: .leading, spacing: DS.Spacing.m) {
                            SectionHeading(title: "Recent dispatches", count: snapshot.recentInvoices.count)
                            ForEach(snapshot.recentInvoices) { row in
                                dispatchRow(row)
                                if row != snapshot.recentInvoices.last { Divider() }
                            }
                        }
                    }
                    .frame(width: 560)

                    CardContainer {
                        VStack(alignment: .leading, spacing: DS.Spacing.m) {
                            SectionHeading(title: "Unit at a glance")
                            statRow("Products", snapshot.productCount, icon: "cube.box.fill", tint: DS.Color.info)
                            statRow("Customers", snapshot.customerCount, icon: "person.2.fill", tint: DS.Color.success)
                            statRow("Suppliers", snapshot.supplierCount, icon: "truck.box.fill", tint: DS.Color.accent)
                            statRow("Vehicles", snapshot.vehicleCount, icon: "truck.fill", tint: DS.Color.warning)
                            Divider()
                            Text(snapshot.hint)
                                .font(DS.Font.footnote)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .padding(DS.Spacing.xl)
            .frame(maxWidth: 1280)
            .frame(maxWidth: .infinity)
        }
        .background(DS.Color.contentBackground)
        .refreshable { reload() }
        .task { reload() }
    }

    private func dispatchRow(_ row: RecentInvoice) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                Text(row.customerName)
                    .font(DS.Font.bodySemibold)
                Text("\(row.invoice.invoiceNo) · \(Format.shortDate(row.invoice.date))")
                    .font(DS.Font.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: DS.Spacing.xs) {
                Text(Format.inr(row.invoice.grandTotalPaise))
                    .font(DS.Font.tableValue)
                Text("\(Format.tonnesLabel(row.qtyKg))")
                    .font(DS.Font.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, DS.Spacing.xs)
    }

    private func statRow(_ title: String, _ value: Int, icon: String, tint: SwiftUI.Color) -> some View {
        HStack(spacing: DS.Spacing.m) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background(tint.opacity(0.14))
                .clipShape(RoundedRectangle(cornerRadius: 7))
            Text(title)
                .font(DS.Font.body)
            Spacer()
            Text("\(value)")
                .font(DS.Font.tableValue)
        }
        .padding(.vertical, 2)
    }

    private func reload() {
        do {
            let newSnapshot = try db.dbQueue.read(Snapshot.load)
            snapshot = newSnapshot
        } catch {
            snapshot = .empty
        }
    }
}

struct RecentInvoice: Identifiable, Equatable {
    var id: Int64 { invoice.id ?? 0 }
    var invoice: SalesInvoice
    var customerName: String
    var qtyKg: Int64
}

struct LowStockItem: Identifiable, Equatable {
    var id: Int64 { productId }
    var productId: Int64
    var name: String
    var qtyKg: Int64
}

struct DayBar: Identifiable, Equatable {
    var id: String { label }
    var label: String
    var productionKg: Int64
    var salesPaise: Int64
}

extension OverviewView {
    private static let chartDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_IN")
        formatter.dateFormat = "d MMM"
        return formatter
    }()

    struct Snapshot: Equatable {
        var businessName = "Stone Crusher Business Unit"
        var productCount = 0
        var customerCount = 0
        var supplierCount = 0
        var vehicleCount = 0
        var todayProductionKg: Int64 = 0
        var todaySalesPaise: Int64 = 0
        var outstandingPaise: Int64 = 0
        var openInvoices = 0
        var totalStockKg: Int64 = 0
        var stockValuePaise: Int64 = 0
        var lowStock: [LowStockItem] = []
        var chart: [DayBar] = []
        var recentInvoices: [RecentInvoice] = []
        var hint = "All figures are computed live from the local database. Everything works fully offline."

        var openInvoicesText: String {
            "\(openInvoices) sales on record"
        }

        static let empty = Snapshot()

        static func load(_ db: Database) throws -> Snapshot {
            var snapshot = Snapshot()
            let calendar = Calendar.current
            let startOfDay = calendar.startOfDay(for: .now)
            let nextDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? .now

            snapshot.productCount = try Product.fetchCount(db)
            snapshot.customerCount = try Customer.fetchCount(db)
            snapshot.supplierCount = try Supplier.fetchCount(db)
            snapshot.vehicleCount = try Vehicle.fetchCount(db)

            snapshot.businessName = try AppSetting.value(forKey: "business_name", db: db)
                ?? "Stone Crusher Business Unit"

            snapshot.todayProductionKg = try Int64.fetchOne(
                db,
                sql: "SELECT COALESCE(SUM(qtyKg), 0) FROM stockMovements WHERE type = ? AND date >= ? AND date < ?",
                arguments: [StockMovement.MoveType.production.rawValue, startOfDay, nextDay]
            ) ?? 0

            snapshot.todaySalesPaise = try Int64.fetchOne(
                db,
                sql: "SELECT COALESCE(SUM(grandTotalPaise), 0) FROM salesInvoices WHERE date >= ? AND date < ?",
                arguments: [startOfDay, nextDay]
            ) ?? 0

            let invoiced = try Int64.fetchOne(
                db,
                sql: "SELECT COALESCE(SUM(grandTotalPaise), 0) FROM salesInvoices"
            ) ?? 0
            let collected = try Int64.fetchOne(
                db,
                sql: "SELECT COALESCE(SUM(amountPaise), 0) FROM payments WHERE partyType = ?",
                arguments: [Payment.PartyType.customer.rawValue]
            ) ?? 0
            snapshot.outstandingPaise = max(0, invoiced - collected)

            snapshot.openInvoices = try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM salesInvoices"
            ) ?? 0

            struct BalanceRow: Decodable, FetchableRecord {
                var productId: Int64
                var qtyKg: Int64
            }
            let balances = try BalanceRow.fetchAll(
                db,
                sql: "SELECT productId, SUM(qtyKg) AS qtyKg FROM stockMovements GROUP BY productId"
            )
            let products = try Product.fetchAll(db)
            let allRates = try ProductRate.order(Column("id")).fetchAll(db)
            var latestRates: [Int64: Int64] = [:]
            for rate in allRates {
                latestRates[rate.productId] = rate.ratePaisePerTonne
            }
            var productNameById: [Int64: String] = [:]
            for product in products {
                if let id = product.id {
                    productNameById[id] = product.name
                    if !product.isActive { continue }
                    let balance = balances.first { $0.productId == id }?.qtyKg ?? 0
                    if balance < 50_000 {
                        snapshot.lowStock.append(
                            LowStockItem(productId: id, name: product.name, qtyKg: balance)
                        )
                    }
                }
            }
            snapshot.lowStock.sort { $0.qtyKg < $1.qtyKg }

            if let earliest = calendar.date(byAdding: .day, value: -13, to: startOfDay) {
                let productionMoves = try StockMovement
                    .filter(Column("type") == StockMovement.MoveType.production.rawValue)
                    .filter(Column("date") >= earliest && Column("date") < nextDay)
                    .fetchAll(db)
                let invoices = try SalesInvoice
                    .filter(Column("date") >= earliest && Column("date") < nextDay)
                    .fetchAll(db)
                var productionByDay: [Date: Int64] = [:]
                for move in productionMoves {
                    let day = calendar.startOfDay(for: move.date)
                    productionByDay[day, default: 0] += move.qtyKg
                }
                var salesByDay: [Date: Int64] = [:]
                for invoice in invoices {
                    let day = calendar.startOfDay(for: invoice.date)
                    salesByDay[day, default: 0] += invoice.grandTotalPaise
                }
                var chartDays: [Date] = []
                for offset in 0...13 {
                    if let day = calendar.date(byAdding: .day, value: offset, to: earliest) {
                        chartDays.append(day)
                    }
                }
                snapshot.chart = chartDays.map { day in
                    DayBar(
                        label: chartDayFormatter.string(from: day),
                        productionKg: productionByDay[day] ?? 0,
                        salesPaise: salesByDay[day] ?? 0
                    )
                }
            }

            snapshot.totalStockKg = balances.reduce(0) { $0 + $1.qtyKg }
            snapshot.stockValuePaise = balances.reduce(0) { partial, row in
                let rate = latestRates[row.productId] ?? 0
                let value = Double(row.qtyKg) * Double(rate) / 1000.0
                return partial + Int64(value.rounded())
            }

            let recent = try SalesInvoice
                .order(Column("date").desc, Column("id").desc)
                .limit(6)
                .fetchAll(db)
            let customers = try Customer.fetchAll(db)
            var customerName = [Int64: String]()
            for customer in customers {
                if let id = customer.id { customerName[id] = customer.name }
            }
            let invoiceIDs = recent.compactMap(\.id)
            struct QtyRow: Decodable, FetchableRecord {
                var invoiceId: Int64
                var qtyKg: Int64
            }
            var qtyByInvoice: [Int64: Int64] = [:]
            if invoiceIDs.isNotEmpty {
                let qtyRows = try QtyRow.fetchAll(
                    db,
                    sql: "SELECT invoiceId, SUM(qtyKg) AS qtyKg FROM invoiceItems WHERE invoiceId IN (\(Array(repeating: "?", count: invoiceIDs.count).joined(separator: ","))) GROUP BY invoiceId",
                    arguments: StatementArguments(invoiceIDs)
                )
                for row in qtyRows {
                    qtyByInvoice[row.invoiceId] = row.qtyKg
                }
            }
            snapshot.recentInvoices = recent.map { invoice in
                RecentInvoice(
                    invoice: invoice,
                    customerName: customerName[invoice.customerId] ?? "Unknown",
                    qtyKg: qtyByInvoice[invoice.id ?? 0] ?? 0
                )
            }

            return snapshot
        }
    }
}

private extension Array {
    var isNotEmpty: Bool { !isEmpty }
}