import XCTest
import GRDB
@testable import PaashERP

/// Integration tests that drive the database exactly the way the app's
/// modules do (production batches, GST invoices, payments, stock
/// adjustments, reports) and verify the persisted results and the numbers
/// a client/demo would see.
final class BusinessWorkflowTests: XCTestCase {
    private var appDatabase: AppDatabase!

    override func setUpWithError() throws {
        appDatabase = AppDatabase.inMemory()
    }

    // MARK: - Helpers (mirror the view save/query logic)

    private func makeProduct(db: Database, code: String, name: String, gstRateBps: Int = 500) throws -> Product {
        var product = Product(code: code, name: name, gstRateBps: gstRateBps)
        try product.insert(db)
        return product
    }

    private func makeCustomer(db: Database, name: String, state: String = "Maharashtra") throws -> Customer {
        var customer = Customer(name: name, gstin: "27AAAAA0000A1Z5", state: state)
        try customer.insert(db)
        return customer
    }

    private func makeVehicle(db: Database, number: String = "MH12AB1234") throws -> Vehicle {
        var vehicle = Vehicle(number: number)
        try vehicle.insert(db)
        return vehicle
    }

    private struct DraftLine {
        var productID: Int64
        var qtyKg: Int64
        var ratePaisePerTonne: Int64
        var gstRateBps: Int
    }

    /// Mirrors ProductionModuleView.saveBatch(): batch + items + production movements.
    @discardableResult
    private func saveBatch(db: Database, date: Date, lines: [(productID: Int64, qtyKg: Int64)]) throws -> Int64 {
        var batch = ProductionBatch(date: date, shift: "A", machineHours: 6, dieselLitres: 120, operatorName: "Ram")
        try batch.save(db)
        guard let batchID = batch.id else { throw WorkflowTestError.missingID }
        for line in lines {
            var item = ProductionItem(batchId: batchID, productId: line.productID, qtyKg: line.qtyKg)
            try item.insert(db)
            var move = StockMovement(
                productId: line.productID, date: date, type: .production,
                qtyKg: line.qtyKg, refId: batchID
            )
            try move.insert(db)
        }
        return batchID
    }

    /// Mirrors SalesEditorView.save(): invoice + items + sale movements + dispatch.
    ///
    /// Returns the persisted invoice plus the independently recomputed totals,
    /// so tests can assert against both the stored rows and the formula.
    @discardableResult
    private func saveInvoice(
        db: Database,
        invoiceNo: String,
        date: Date,
        customerID: Int64,
        vehicleID: Int64? = nil,
        transportPaise: Int64 = 0,
        discountPaise: Int64 = 0,
        intraState: Bool,
        lines: [DraftLine]
    ) throws -> (invoice: SalesInvoice, subtotal: Int64, cgst: Int64, sgst: Int64, igst: Int64) {
        let amounts = lines.map { $0.qtyKg * $0.ratePaisePerTonne / 1000 }
        let gst = amounts.enumerated().map { index, amount in
            amount * Int64(lines[index].gstRateBps) / 10_000
        }
        let subtotal = amounts.reduce(0, +)
        let cgst = gst.reduce(Int64(0)) { partial, g in intraState ? partial + g / 2 : partial }
        let sgst = gst.reduce(Int64(0)) { partial, g in intraState ? partial + g - g / 2 : partial }
        let igst = gst.reduce(Int64(0)) { partial, g in intraState ? partial : partial + g }
        let grand = max(0, subtotal + cgst + sgst + igst + transportPaise - discountPaise)
        let netKg = lines.reduce(0) { $0 + $1.qtyKg }

        var invoice = SalesInvoice(
            invoiceNo: invoiceNo,
            date: date,
            customerId: customerID,
            vehicleId: vehicleID,
            status: .dispatched,
            subtotalPaise: subtotal,
            cgstPaise: cgst,
            sgstPaise: sgst,
            igstPaise: igst,
            transportChargePaise: transportPaise,
            discountPaise: discountPaise,
            grandTotalPaise: grand
        )
        try invoice.insert(db)
        guard let invoiceID = invoice.id else { throw WorkflowTestError.missingID }

        for (index, line) in lines.enumerated() {
            var item = InvoiceItem(
                invoiceId: invoiceID,
                productId: line.productID,
                qtyKg: line.qtyKg,
                ratePaisePerTonne: line.ratePaisePerTonne,
                amountPaise: amounts[index],
                gstRateBps: line.gstRateBps,
                hsn: "2517"
            )
            try item.insert(db)
            var move = StockMovement(
                productId: line.productID, date: date, type: .sale,
                qtyKg: -line.qtyKg, refId: invoiceID
            )
            try move.insert(db)
        }
        var dispatch = DispatchDetail(invoiceId: invoiceID, netKg: netKg)
        try dispatch.insert(db)

        return (invoice, subtotal, cgst, sgst, igst)
    }

    private func balanceKg(db: Database, productID: Int64) throws -> Int64 {
        try Int64.fetchOne(
            db,
            sql: "SELECT COALESCE(SUM(qtyKg), 0) FROM stockMovements WHERE productId = ?",
            arguments: [productID]
        ) ?? 0
    }

    private func dispatchNetKg(db: Database, invoiceID: Int64) throws -> Int64? {
        try DispatchDetail
            .filter(Column("invoiceId") == invoiceID)
            .fetchOne(db)?
            .netKg
    }

    private func currentYear() -> Int {
        Calendar.autoupdatingCurrent.component(.year, from: .now)
    }

    private func calendarDate(daysAgo: Int) -> Date {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        return calendar.date(byAdding: .day, value: -daysAgo, to: today) ?? .now
    }

    private func outstanding(db: AppDatabase, customerId: Int64) throws -> Int64 {
        try db.dbQueue.read { database in
            let invoices = try SalesInvoice.filter(Column("customerId") == customerId).fetchAll(database)
            struct PaidRow: Decodable, FetchableRecord {
                var invoiceId: Int64
                var amountPaise: Int64
            }
            let paid = try PaidRow.fetchAll(
                database,
                sql: "SELECT invoiceId, SUM(amountPaise) AS amountPaise FROM payments WHERE partyType = ? AND invoiceId IS NOT NULL GROUP BY invoiceId",
                arguments: [Payment.PartyType.customer.rawValue]
            )
            var paidByInvoice: [Int64: Int64] = [:]
            for row in paid { paidByInvoice[row.invoiceId] = row.amountPaise }
            return invoices.reduce(Int64(0)) { partial, invoice in
                partial + max(0, invoice.grandTotalPaise - (paidByInvoice[invoice.id ?? 0] ?? 0))
            }
        }
    }

    // MARK: - Invoice numbering

    func testInvoiceNumberingIsSequentialAndYearPrefixed() throws {
        // Seeded-style "PI-" numbers must not consume the sequence.
        try appDatabase.dbQueue.write { db in
            let customer = try makeCustomer(db: db, name: "A")
            try saveInvoice(db: db, invoiceNo: "PI-2020-0042", date: .now, customerID: customer.id!, intraState: true, lines: [])
            XCTAssertEqual(try InvoiceNumber.next(db: db), String(format: "INV-%d-0001", currentYear()))
            let first = try InvoiceNumber.next(db: db)
            try saveInvoice(db: db, invoiceNo: first, date: .now, customerID: customer.id!, intraState: true, lines: [])
            XCTAssertEqual(try InvoiceNumber.next(db: db), String(format: "INV-%d-0002", currentYear()))
        }
    }

    func testInvoiceNumberingCountsOnlyCurrentYearPrefix() throws {
        try appDatabase.dbQueue.write { db in
            let customer = try makeCustomer(db: db, name: "A")
            for year in [2019, 2020, 2021] {
                try saveInvoice(
                    db: db,
                    invoiceNo: String(format: "INV-%d-0001", year),
                    date: .now,
                    customerID: customer.id!,
                    intraState: true,
                    lines: []
                )
            }
            let first = try InvoiceNumber.next(db: db)
            XCTAssertEqual(first, String(format: "INV-%d-0001", currentYear()))
            try saveInvoice(db: db, invoiceNo: first, date: .now, customerID: customer.id!, intraState: true, lines: [])
            XCTAssertEqual(try InvoiceNumber.next(db: db), String(format: "INV-%d-0002", currentYear()))
        }
    }

    func testInvoiceNumberingDoesNotCollideAfterMiddleDeletion() throws {
        try appDatabase.dbQueue.write { db in
            let customer = try makeCustomer(db: db, name: "Sequence Customer")
            var created: [String] = []
            for _ in 1...3 {
                let no = try InvoiceNumber.next(db: db)
                try saveInvoice(db: db, invoiceNo: no, date: .now, customerID: customer.id!, intraState: true, lines: [])
                created.append(no)
            }
            // Delete the middle invoice (0002). Count-based numbering would
            // emit 0003 again, colliding with the still-existing invoice;
            // MAX-based numbering must continue to 0004.
            try SalesInvoice
                .filter(Column("invoiceNo") == created[1])
                .deleteAll(db)
            XCTAssertEqual(try InvoiceNumber.next(db: db), String(format: "INV-%d-0004", currentYear()))
        }
    }

    // MARK: - Production

    func testProductionBatchFeedsStock() throws {
        let productID: Int64 = try appDatabase.dbQueue.write { db in
            try makeProduct(db: db, code: "TEN", name: "10mm").id!
        }
        let batch = try appDatabase.dbQueue.write { db in
            try saveBatch(db: db, date: .now, lines: [(productID, 12_000)])
        }
        let (batchItems, balance) = try appDatabase.dbQueue.read { db in
            (
                try ProductionItem.filter(Column("batchId") == batch).fetchCount(db),
                try balanceKg(db: db, productID: productID)
            )
        }
        XCTAssertEqual(batchItems, 1)
        XCTAssertEqual(balance, 12_000)
    }

    func testEditingBatchReplacesItemsAndMovementsWithoutDoubleCounting() throws {
        let productID: Int64 = try appDatabase.dbQueue.write { db in
            try makeProduct(db: db, code: "MSD", name: "M-Sand").id!
        }
        let batchID: Int64 = try appDatabase.dbQueue.write { db in
            try saveBatch(db: db, date: .now, lines: [(productID, 10_000)])
        }
        // Re-save the same batch with a new quantity (mirrors saveBatch for an existing batch).
        try appDatabase.dbQueue.write { db in
            try StockMovement
                .filter(Column("type") == StockMovement.MoveType.production.rawValue)
                .filter(Column("refId") == batchID)
                .deleteAll(db)
            try ProductionItem.filter(Column("batchId") == batchID).deleteAll(db)
            var item = ProductionItem(batchId: batchID, productId: productID, qtyKg: 15_000)
            try item.insert(db)
            var move = StockMovement(productId: productID, date: .now, type: .production, qtyKg: 15_000, refId: batchID)
            try move.insert(db)
        }
        let (itemCount, balance) = try appDatabase.dbQueue.read { db in
            (
                try ProductionItem.filter(Column("batchId") == batchID).fetchCount(db),
                try balanceKg(db: db, productID: productID)
            )
        }
        XCTAssertEqual(itemCount, 1)
        XCTAssertEqual(balance, 15_000)
    }

    // MARK: - GST invoice math

    func testIntraStateInvoiceMathAndStockDeduction() throws {
        let (invoice, productID) = try appDatabase.dbQueue.write { db -> ((SalesInvoice, Int64, Int64, Int64, Int64), Int64) in
            let product = try makeProduct(db: db, code: "TEN", name: "10mm", gstRateBps: 500)
            let customer = try makeCustomer(db: db, name: "Rajpura Constructions", state: "Maharashtra")
            let vehicle = try makeVehicle(db: db)
            let result = try saveInvoice(
                db: db,
                invoiceNo: "INV-2026-0001",
                date: .now,
                customerID: customer.id!,
                vehicleID: vehicle.id!,
                transportPaise: 50_000,
                intraState: true,
                lines: [
                    DraftLine(productID: product.id!, qtyKg: 10_000, ratePaisePerTonne: 120_000, gstRateBps: 500)
                ]
            )
            return (result, product.id!)
        }
        let (result, subtotal, cgst, sgst, igst) = invoice
        // amount = 10,000 kg × ₹1,200/t ÷ 1000 = ₹12,000 → 1,200,000 paise
        XCTAssertEqual(subtotal, 1_200_000)
        // gst = 1,200,000 × 500 ÷ 10,000 = 60,000 → CGST 30,000 / SGST 30,000
        XCTAssertEqual(cgst, 30_000)
        XCTAssertEqual(sgst, 30_000)
        XCTAssertEqual(igst, 0)

        let persisted = try appDatabase.dbQueue.read { db in
            let invoiceRow = try SalesInvoice.fetchOne(db, key: result.id!)
            let dispatchNet = try dispatchNetKg(db: db, invoiceID: result.id!)
            let itemCount = try InvoiceItem.fetchCount(db)
            let balance = try balanceKg(db: db, productID: productID)
            return (invoiceRow, dispatchNet, itemCount, balance)
        }
        XCTAssertEqual(persisted.0?.subtotalPaise, 1_200_000)
        XCTAssertEqual(persisted.0?.cgstPaise, 30_000)
        XCTAssertEqual(persisted.0?.sgstPaise, 30_000)
        XCTAssertEqual(persisted.0?.igstPaise, 0)
        XCTAssertEqual(persisted.0?.transportChargePaise, 50_000)
        XCTAssertEqual(persisted.0?.grandTotalPaise, 1_310_000)
        XCTAssertEqual(persisted.1, 10_000)
        XCTAssertEqual(persisted.2, 1)
        // Stock decreased by the sold quantity.
        XCTAssertEqual(persisted.3, -10_000)
    }

    func testOddPaiseGSTRoundRobin() throws {
        let (result, _, cgst, sgst, _) = try appDatabase.dbQueue.write { db in
            let p1 = try makeProduct(db: db, code: "G2", name: "20mm", gstRateBps: 500)
            let p2 = try makeProduct(db: db, code: "G3", name: "40mm", gstRateBps: 1800)
            let customer = try makeCustomer(db: db, name: "Shree Builders", state: "Maharashtra")
            return try saveInvoice(
                db: db,
                invoiceNo: "INV-2026-0002",
                date: .now,
                customerID: customer.id!,
                intraState: true,
                lines: [
                    DraftLine(productID: p1.id!, qtyKg: 3_333, ratePaisePerTonne: 95_000, gstRateBps: 500),
                    DraftLine(productID: p2.id!, qtyKg: 2_450, ratePaisePerTonne: 110_000, gstRateBps: 1800)
                ]
            )
        }
        // 3,333 kg × ₹950/t ÷ 1000 = 316,635 paise; gst 15,831 (odd) → CGST 7,915 / SGST 7,916
        // 2,450 kg × ₹1,100/t ÷ 1000 = 269,500 paise; gst 48,510 (even) → CGST 24,255 / SGST 24,255
        XCTAssertEqual(cgst, 7_915 + 24_255)
        XCTAssertEqual(sgst, 7_916 + 24_255)
        // CGST + SGST must equal the sum of per-line GST even when paise are odd.
        XCTAssertEqual(cgst + sgst, 15_831 + 48_510)
        XCTAssertEqual(result.grandTotalPaise, result.subtotalPaise + cgst + sgst)
    }

    func testInterStateInvoiceUsesIGSTOnly() throws {
        let (result, _, cgst, sgst, igst) = try appDatabase.dbQueue.write { db in
            let product = try makeProduct(db: db, code: "TEN", name: "10mm", gstRateBps: 500)
            let customer = try makeCustomer(db: db, name: "Bengaluru Infra", state: "Karnataka")
            return try saveInvoice(
                db: db,
                invoiceNo: "INV-2026-0003",
                date: .now,
                customerID: customer.id!,
                intraState: false,
                lines: [
                    DraftLine(productID: product.id!, qtyKg: 20_000, ratePaisePerTonne: 125_000, gstRateBps: 500)
                ]
            )
        }
        // 20,000 kg × ₹1,250/t ÷ 1000 = 2,500,000; gst 5% = 125,000 → IGST only.
        XCTAssertEqual(igst, 125_000)
        XCTAssertEqual(cgst, 0)
        XCTAssertEqual(sgst, 0)
        XCTAssertEqual(result.grandTotalPaise, 2_500_000 + 125_000)
    }

    // MARK: - Invoice update & delete

    func testInvoiceUpdateReplacesLinesAndMovements() throws {
        let (p1, p2, customer) = try appDatabase.dbQueue.write { db in
            (try makeProduct(db: db, code: "TEN", name: "10mm"),
             try makeProduct(db: db, code: "MSD", name: "M-Sand"),
             try makeCustomer(db: db, name: "Demo Customer"))
        }
        let first = try appDatabase.dbQueue.write { db in
            try saveInvoice(
                db: db, invoiceNo: "INV-2026-0010", date: .now, customerID: customer.id!,
                intraState: true,
                lines: [
                    DraftLine(productID: p1.id!, qtyKg: 5_000, ratePaisePerTonne: 100_000, gstRateBps: 500),
                    DraftLine(productID: p2.id!, qtyKg: 3_000, ratePaisePerTonne: 90_000, gstRateBps: 500)
                ]
            )
        }
        let invoiceID = first.invoice.id!
        // Re-save updates in place (mirrors save() for an existing invoice).
        let updatedGrand = try appDatabase.dbQueue.write { db -> Int64 in
            var invoice = try SalesInvoice.fetchOne(db, key: invoiceID)!
            try StockMovement
                .filter(Column("type") == StockMovement.MoveType.sale.rawValue)
                .filter(Column("refId") == invoiceID)
                .deleteAll(db)
            try InvoiceItem.filter(Column("invoiceId") == invoiceID).deleteAll(db)
            try DispatchDetail.filter(Column("invoiceId") == invoiceID).deleteAll(db)

            // One delivery: 2,000 kg × ₹950/t ÷ 1000 = 190,000; gst 9,500.
            let amount: Int64 = 2_000 * 95_000 / 1000
            let gst = amount * 500 / 10_000
            invoice.subtotalPaise = amount
            invoice.cgstPaise = gst / 2
            invoice.sgstPaise = gst - gst / 2
            invoice.igstPaise = 0
            invoice.grandTotalPaise = amount + gst
            try invoice.save(db)

            var item = InvoiceItem(invoiceId: invoiceID, productId: p1.id!, qtyKg: 2_000,
                                   ratePaisePerTonne: 95_000, amountPaise: amount, gstRateBps: 500, hsn: "2517")
            try item.insert(db)
            var move = StockMovement(productId: p1.id!, date: .now, type: .sale, qtyKg: -2_000, refId: invoiceID)
            try move.insert(db)
            var dispatch = DispatchDetail(invoiceId: invoiceID, netKg: 2_000)
            try dispatch.insert(db)
            return invoice.grandTotalPaise
        }

        let (itemCount, moveCount, dispatchNet, persisted) = try appDatabase.dbQueue.read { db in
            (
                try InvoiceItem.filter(Column("invoiceId") == invoiceID).fetchCount(db),
                try StockMovement.filter(Column("refId") == invoiceID).fetchCount(db),
                try dispatchNetKg(db: db, invoiceID: invoiceID),
                try SalesInvoice.fetchOne(db, key: invoiceID)
            )
        }
        XCTAssertEqual(itemCount, 1)
        XCTAssertEqual(moveCount, 1)
        XCTAssertEqual(dispatchNet, 2_000)
        XCTAssertEqual(persisted?.subtotalPaise, 190_000)
        XCTAssertEqual(persisted?.grandTotalPaise, updatedGrand)
        // P1 stock reflects only the latest delivery; P2's old movement was removed.
        let (balanceP1, balanceP2) = try appDatabase.dbQueue.read { db in
            (try balanceKg(db: db, productID: p1.id!), try balanceKg(db: db, productID: p2.id!))
        }
        XCTAssertEqual(balanceP1, -2_000)
        XCTAssertEqual(balanceP2, 0)
    }

    func testInvoiceDeleteRestoresStockAndIsBlockedWhenPaymentsExist() throws {
        let (product, customer) = try appDatabase.dbQueue.write { db in
            (try makeProduct(db: db, code: "TEN", name: "10mm"),
             try makeCustomer(db: db, name: "Delete Test"))
        }
        try appDatabase.dbQueue.write { db in
            try saveBatch(db: db, date: .now, lines: [(product.id!, 10_000)])
        }
        let result = try appDatabase.dbQueue.write { db in
            try saveInvoice(
                db: db, invoiceNo: "INV-2026-0020", date: .now, customerID: customer.id!,
                intraState: true,
                lines: [DraftLine(productID: product.id!, qtyKg: 4_000, ratePaisePerTonne: 100_000, gstRateBps: 500)]
            )
        }
        let invoiceID = result.invoice.id!
        // Blocked when a payment references the invoice (mirrors deleteSelected()).
        let canDeleteWithPayment = try appDatabase.dbQueue.write { db -> Bool in
            var payment = Payment(date: .now, partyType: .customer, partyId: customer.id!, invoiceId: invoiceID, amountPaise: 100_000)
            try payment.insert(db)
            return try Payment.filter(Column("invoiceId") == invoiceID).fetchCount(db) == 0
        }
        XCTAssertFalse(canDeleteWithPayment)

        // Delete the payment, then perform the app's delete cascade.
        try appDatabase.dbQueue.write { db in
            try Payment.filter(Column("invoiceId") == invoiceID).deleteAll(db)
            try StockMovement
                .filter(Column("type") == StockMovement.MoveType.sale.rawValue)
                .filter(Column("refId") == invoiceID)
                .deleteAll(db)
            try DispatchDetail.filter(Column("invoiceId") == invoiceID).deleteAll(db)
            try InvoiceItem.filter(Column("invoiceId") == invoiceID).deleteAll(db)
            try SalesInvoice.deleteOne(db, key: invoiceID)
        }
        let (invoiceCount, balance) = try appDatabase.dbQueue.read { db in
            (try SalesInvoice.fetchCount(db), try balanceKg(db: db, productID: product.id!))
        }
        XCTAssertEqual(invoiceCount, 0)
        XCTAssertEqual(balance, 10_000) // stock restored to produced level
    }

    func testCancelInvoiceReturnsStockAndIsExcludedFromSales() throws {
        let (product, customer) = try appDatabase.dbQueue.write { db in
            (try makeProduct(db: db, code: "TEN", name: "10mm"),
             try makeCustomer(db: db, name: "Cancel Customer"))
        }
        try appDatabase.dbQueue.write { db in
            try saveBatch(db: db, date: .now, lines: [(product.id!, 10_000)])
        }
        let invoice = try appDatabase.dbQueue.write { db in
            try saveInvoice(
                db: db, invoiceNo: "INV-2026-0090", date: .now, customerID: customer.id!,
                intraState: true,
                lines: [DraftLine(productID: product.id!, qtyKg: 4_000, ratePaisePerTonne: 100_000, gstRateBps: 500)]
            ).invoice
        }
        let invoiceID = invoice.id!

        // Cancellation requires no linked payments (mirrors cancelSelected()).
        let canCancel = try appDatabase.dbQueue.read { db in
            try Payment.filter(Column("invoiceId") == invoiceID).fetchCount(db) == 0
        }
        XCTAssertTrue(canCancel)

        try appDatabase.dbQueue.write { db in
            var persisted = try SalesInvoice.fetchOne(db, key: invoiceID)
            persisted?.status = .cancelled
            if let persisted { try persisted.update(db) }
            try StockMovement
                .filter(Column("type") == StockMovement.MoveType.sale.rawValue)
                .filter(Column("refId") == invoiceID)
                .deleteAll(db)
        }

        let (status, balance, recordedSales) = try appDatabase.dbQueue.read { db in
            (
                try SalesInvoice.fetchOne(db, key: invoiceID)!.status,
                try balanceKg(db: db, productID: product.id!),
                try Int64.fetchOne(
                    db,
                    sql: "SELECT COALESCE(SUM(grandTotalPaise), 0) FROM salesInvoices WHERE status != ?",
                    arguments: [SalesInvoice.Status.cancelled.rawValue]
                ) ?? 0
            )
        }
        XCTAssertEqual(status, .cancelled)
        XCTAssertEqual(balance, 10_000) // stock returned to produced level
        XCTAssertEqual(recordedSales, 0) // excluded from sales KPIs
    }

    func testCustomerOpeningBalanceCountsTowardOutstanding() throws {
        try appDatabase.dbQueue.write { db in
            var customer = try makeCustomer(db: db, name: "Opening Balance Customer")
            customer.openingBalancePaise = 250_000
            try customer.update(db)
        }
        let outstanding = try appDatabase.dbQueue.read { db in
            let cancelled = SalesInvoice.Status.cancelled.rawValue
            let invoiced = try Int64.fetchOne(
                db,
                sql: "SELECT COALESCE(SUM(grandTotalPaise), 0) FROM salesInvoices WHERE status != ?",
                arguments: [cancelled]
            ) ?? 0
            let collected = try Int64.fetchOne(
                db,
                sql: "SELECT COALESCE(SUM(amountPaise), 0) FROM payments WHERE partyType = ?",
                arguments: [Payment.PartyType.customer.rawValue]
            ) ?? 0
            let opening = try Int64.fetchOne(
                db,
                sql: "SELECT COALESCE(SUM(openingBalancePaise), 0) FROM customers"
            ) ?? 0
            return max(0, invoiced - collected + opening)
        }
        XCTAssertEqual(outstanding, 250_000)
    }

    // MARK: - Payments & receivables aging

    func testPaymentsSettleOutstandingIntoSingleInvoice() throws {
        let (product, customer) = try appDatabase.dbQueue.write { db in
            (try makeProduct(db: db, code: "TEN", name: "10mm"),
             try makeCustomer(db: db, name: "Paying Customer"))
        }
        let result = try appDatabase.dbQueue.write { db in
            try saveInvoice(
                db: db, invoiceNo: "INV-2026-0030", date: calendarDate(daysAgo: 20), customerID: customer.id!,
                intraState: true,
                lines: [DraftLine(productID: product.id!, qtyKg: 5_000, ratePaisePerTonne: 100_000, gstRateBps: 500)]
            )
        }
        let grand = result.invoice.grandTotalPaise
        try appDatabase.dbQueue.write { db in
            var payment = Payment(date: .now, partyType: .customer, partyId: customer.id!, invoiceId: result.invoice.id!, amountPaise: grand / 2)
            try payment.insert(db)
        }
        XCTAssertEqual(try outstanding(db: appDatabase, customerId: customer.id!), grand - grand / 2)

        try appDatabase.dbQueue.write { db in
            var payment = Payment(date: .now, partyType: .customer, partyId: customer.id!, invoiceId: result.invoice.id!, amountPaise: grand - grand / 2)
            try payment.insert(db)
        }
        XCTAssertEqual(try outstanding(db: appDatabase, customerId: customer.id!), 0)
    }

    func testAgingBucketsMatchReportsCalculation() throws {
        let (product, customer) = try appDatabase.dbQueue.write { db in
            (try makeProduct(db: db, code: "TEN", name: "10mm"),
             try makeCustomer(db: db, name: "Aging Customer"))
        }
        // Two unpaid invoices: 10 days old (bucket 0–30) and 45 days old (bucket 31–60).
        let recentGrand = try appDatabase.dbQueue.write { db in
            try saveInvoice(db: db, invoiceNo: "INV-2026-0040", date: calendarDate(daysAgo: 10), customerID: customer.id!, intraState: true,
                            lines: [DraftLine(productID: product.id!, qtyKg: 2_000, ratePaisePerTonne: 100_000, gstRateBps: 500)])
                .invoice.grandTotalPaise
        }
        let agedGrand = try appDatabase.dbQueue.write { db in
            try saveInvoice(db: db, invoiceNo: "INV-2026-0041", date: calendarDate(daysAgo: 45), customerID: customer.id!, intraState: true,
                            lines: [DraftLine(productID: product.id!, qtyKg: 3_000, ratePaisePerTonne: 100_000, gstRateBps: 500)])
                .invoice.grandTotalPaise
        }

        let buckets = try appDatabase.dbQueue.read { db -> (counts: [Int], amounts: [Int64]) in
            let calendar = Calendar.current
            let today = calendar.startOfDay(for: .now)
            let invoices = try SalesInvoice.filter(Column("customerId") == customer.id!).fetchAll(db)
            var counts = [0, 0, 0, 0]
            var amounts: [Int64] = [0, 0, 0, 0]
            for invoice in invoices where invoice.grandTotalPaise > 0 {
                let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: invoice.date), to: today).day ?? 0
                let index = days <= 30 ? 0 : (days <= 60 ? 1 : (days <= 90 ? 2 : 3))
                counts[index] += 1
                amounts[index] += invoice.grandTotalPaise
            }
            return (counts, amounts)
        }
        XCTAssertEqual(buckets.counts, [1, 1, 0, 0])
        XCTAssertEqual(buckets.amounts, [recentGrand, agedGrand, 0, 0])
    }

    // MARK: - Stock adjustments & valuation

    func testStockAdjustmentsAndValuation() throws {
        let productID: Int64 = try appDatabase.dbQueue.write { db in
            try makeProduct(db: db, code: "TEN", name: "10mm").id!
        }
        try appDatabase.dbQueue.write { db in
            try saveBatch(db: db, date: .now, lines: [(productID, 10_000)])
            var inMove = StockMovement(productId: productID, date: .now, type: .adjustmentIn, qtyKg: 1_000)
            try inMove.insert(db)
            XCTAssertEqual(try balanceKg(db: db, productID: productID), 11_000)
            var outMove = StockMovement(productId: productID, date: .now, type: .adjustmentOut, qtyKg: -500)
            try outMove.insert(db)
            XCTAssertEqual(try balanceKg(db: db, productID: productID), 10_500)
        }
        // Valuation at latest rate: 10,500 kg × ₹1,250/t ÷ 1000 = ₹13,125 → 1,312,500 paise.
        try appDatabase.dbQueue.write { db in
            var rate = ProductRate(productId: productID, ratePaisePerTonne: 125_000)
            try rate.insert(db)
        }
        let value = try appDatabase.dbQueue.read { db -> Int64 in
            let balance = try balanceKg(db: db, productID: productID)
            let latest = try ProductRate
                .filter(Column("productId") == productID)
                .order(Column("effectiveDate").desc)
                .fetchOne(db)
            guard let latest else { return 0 }
            return Int64((Double(balance) * Double(latest.ratePaisePerTonne) / 1000.0).rounded())
        }
        XCTAssertEqual(value, 1_312_500)
    }

    // MARK: - Reports KPI mirror

    func testReportsKPIsMirrorViewQueries() throws {
        let (p1, p2, customer) = try appDatabase.dbQueue.write { db in
            (try makeProduct(db: db, code: "TEN", name: "10mm", gstRateBps: 500),
             try makeProduct(db: db, code: "MSD", name: "M-Sand", gstRateBps: 1800),
             try makeCustomer(db: db, name: "Report Customer", state: "Maharashtra"))
        }
        let from = calendarDate(daysAgo: 30)
        let to = calendarDate(daysAgo: 1)
        let next = to.addingTimeInterval(86_400)

        // Production 20 days ago (in window): p1 10,000 + p2 5,000.
        // In-window sale 10 days ago: p1 3,000 + p2 2,000.
        // Out-of-window invoice 60 days ago: p1 6,000.
        // Expense 5 days ago: diesel ₹50,000; out-of-window misc ₹10,000.
        try appDatabase.dbQueue.write { db in
            try saveBatch(db: db, date: calendarDate(daysAgo: 20), lines: [(p1.id!, 10_000), (p2.id!, 5_000)])
            try saveInvoice(db: db, invoiceNo: "INV-2026-0050", date: calendarDate(daysAgo: 10), customerID: customer.id!, intraState: true,
                            lines: [DraftLine(productID: p1.id!, qtyKg: 3_000, ratePaisePerTonne: 100_000, gstRateBps: 500),
                                    DraftLine(productID: p2.id!, qtyKg: 2_000, ratePaisePerTonne: 95_000, gstRateBps: 1800)])
            try saveInvoice(db: db, invoiceNo: "INV-2026-0051", date: calendarDate(daysAgo: 60), customerID: customer.id!, intraState: true,
                            lines: [DraftLine(productID: p1.id!, qtyKg: 6_000, ratePaisePerTonne: 100_000, gstRateBps: 500)])
            var purchase = Purchase(date: calendarDate(daysAgo: 5), category: .diesel, amountPaise: 5_000_000)
            try purchase.insert(db)
            var outside = Purchase(date: calendarDate(daysAgo: 45), category: .misc, amountPaise: 1_000_000)
            try outside.insert(db)
        }

        let kpis = try appDatabase.dbQueue.read { db -> (produced: Int64, sold: Int64, sales: Int64, expenses: Int64) in
            (
                produced: try Int64.fetchOne(db, sql: "SELECT COALESCE(SUM(qtyKg), 0) FROM stockMovements WHERE type = ? AND date >= ? AND date < ?",
                                            arguments: [StockMovement.MoveType.production.rawValue, from, next]) ?? 0,
                sold: try Int64.fetchOne(db, sql: "SELECT COALESCE(SUM(-qtyKg), 0) FROM stockMovements WHERE type = ? AND date >= ? AND date < ?",
                                         arguments: [StockMovement.MoveType.sale.rawValue, from, next]) ?? 0,
                sales: try Int64.fetchOne(db, sql: "SELECT COALESCE(SUM(grandTotalPaise), 0) FROM salesInvoices WHERE date >= ? AND date < ?",
                                          arguments: [from, next]) ?? 0,
                expenses: try Int64.fetchOne(db, sql: "SELECT COALESCE(SUM(amountPaise), 0) FROM purchases WHERE date >= ? AND date < ?",
                                             arguments: [from, next]) ?? 0
            )
        }
        XCTAssertEqual(kpis.produced, 15_000)
        XCTAssertEqual(kpis.sold, 5_000)
        XCTAssertEqual(kpis.expenses, 5_000_000)
        // p1: 300,000 + 15,000 (CGST 7.5k + 7.5k); p2: 190,000 + 34,200 → in-window sales total 539,200.
        XCTAssertEqual(kpis.sales, 539_200)
    }

    // MARK: - Seed data integrity audit

    func testSeededDatasetPassesFullIntegrityAudit() throws {
        let db = AppDatabase.inMemory()
        try DemoSeeder.seedIfNeeded(db.dbQueue)

        struct ProdRow: Decodable, FetchableRecord {
            var productId: Int64
            var qtyKg: Int64
        }
        struct DispatchRow: Decodable, FetchableRecord {
            var invoiceId: Int64
            var netKg: Int64
        }

        try db.dbQueue.read { database in
            let invoices = try SalesInvoice.fetchAll(database)
            let items = try InvoiceItem.fetchAll(database)
            XCTAssertGreaterThanOrEqual(invoices.count, 80, "expected a full demo dataset")
            XCTAssertGreaterThanOrEqual(items.count, 80)
            XCTAssertEqual(Set(invoices.map(\.invoiceNo)).count, invoices.count, "duplicate invoice numbers")

            let dispatches = try DispatchRow.fetchAll(database, sql: "SELECT invoiceId, netKg FROM dispatchDetails")
            XCTAssertEqual(dispatches.count, invoices.count, "every invoice should have one dispatch")

            let saleMoves = try ProdRow.fetchAll(database, sql: "SELECT refId AS productId, qtyKg FROM stockMovements WHERE type = 'sale'")
            let salesByInvoice = Dictionary(grouping: saleMoves, by: \.productId)

            for invoice in invoices {
                let lineItems = items.filter { $0.invoiceId == invoice.id }
                XCTAssertFalse(lineItems.isEmpty, "\(invoice.invoiceNo) has no line items")

                let subtotal = lineItems.reduce(Int64(0)) { $0 + $1.amountPaise }
                XCTAssertEqual(invoice.subtotalPaise, subtotal, "subtotal mismatch \(invoice.invoiceNo)")

                for item in lineItems {
                    let expectedAmount = item.qtyKg * item.ratePaisePerTonne / 1000
                    XCTAssertEqual(item.amountPaise, expectedAmount, "amount mismatch in \(invoice.invoiceNo)")
                }

                // Seeder writes CGST+SGST (never IGST) and no discount, and the split equals per-line GST.
                XCTAssertEqual(invoice.igstPaise, 0, "unexpected IGST in \(invoice.invoiceNo)")
                XCTAssertEqual(invoice.discountPaise, 0)
                let lineGST = lineItems.reduce(Int64(0)) { $0 + $1.amountPaise * Int64($1.gstRateBps) / 10_000 }
                XCTAssertEqual(invoice.cgstPaise + invoice.sgstPaise, lineGST, "GST split mismatch \(invoice.invoiceNo)")
                XCTAssertEqual(invoice.grandTotalPaise,
                               invoice.subtotalPaise + invoice.cgstPaise + invoice.sgstPaise + invoice.transportChargePaise,
                               "grand total mismatch \(invoice.invoiceNo)")

                // Sale movements must sum to the negative of the line quantity.
                let sold = salesByInvoice[invoice.id ?? 0] ?? []
                let itemQty = lineItems.reduce(Int64(0)) { $0 + $1.qtyKg }
                XCTAssertEqual(sold.reduce(Int64(0)) { $0 + $1.qtyKg }, -itemQty, "sale movements mismatch \(invoice.invoiceNo)")
            }

            // No payment exceeds its invoice total.
            let payments = try Payment.fetchAll(database)
            for payment in payments {
                guard let invoiceID = payment.invoiceId, let invoice = invoices.first(where: { $0.id == invoiceID }) else { continue }
                XCTAssertLessThanOrEqual(payment.amountPaise, invoice.grandTotalPaise, "payment exceeds invoice \(invoice.invoiceNo)")
            }

            // Every product was produced and sold.
            let produced = try ProdRow.fetchAll(database, sql: "SELECT productId, SUM(qtyKg) AS qtyKg FROM stockMovements WHERE type = 'production' GROUP BY productId")
            let sold = try ProdRow.fetchAll(database, sql: "SELECT productId, SUM(qtyKg) AS qtyKg FROM stockMovements WHERE type = 'sale' GROUP BY productId")
            XCTAssertEqual(Set(produced.map(\.productId)), Set(sold.map(\.productId)), "produced/sold product sets differ")
            XCTAssertEqual(produced.count, try Product.fetchCount(database), "not every product was produced")
        }
    }

    // MARK: - Stock gate (negative-stock prevention on invoice save)

    func testStockGateBlocksOverselling() throws {
        let productID: Int64 = try appDatabase.dbQueue.write { db in
            try makeProduct(db: db, code: "TEN", name: "10mm").id!
        }
        try appDatabase.dbQueue.write { db in
            try saveBatch(db: db, date: .now, lines: [(productID, 10_000)])
        }
        XCTAssertThrowsError(try appDatabase.dbQueue.write { db in
            try StockGate.requireAvailable(db: db, replacingInvoiceID: nil, required: [productID: 10_001], productName: { _ in "10mm" })
        }) { error in
            XCTAssertEqual(error as? InvoiceValidationError,
                           .insufficientStock(product: "10mm", availableKg: 10_000, neededKg: 10_001))
        }
        // Zero requirement never blocks.
        XCTAssertNoThrow(try appDatabase.dbQueue.write { db in
            try StockGate.requireAvailable(db: db, replacingInvoiceID: nil, required: [productID: 0], productName: { _ in "10mm" })
        })
    }

    func testStockGateAllowsExactlyAvailable() throws {
        let productID: Int64 = try appDatabase.dbQueue.write { db in
            try makeProduct(db: db, code: "TEN", name: "10mm").id!
        }
        try appDatabase.dbQueue.write { db in
            try saveBatch(db: db, date: .now, lines: [(productID, 10_000)])
        }
        XCTAssertNoThrow(try appDatabase.dbQueue.write { db in
            try StockGate.requireAvailable(db: db, replacingInvoiceID: nil, required: [productID: 10_000], productName: { _ in "10mm" })
        })
    }

    func testStockGateAllowsEditingToReuseAlreadySoldStock() throws {
        let (product, customer) = try appDatabase.dbQueue.write { db in
            (try makeProduct(db: db, code: "TEN", name: "10mm"),
             try makeCustomer(db: db, name: "Gate Customer"))
        }
        // 8 t invoiced first, then 10 t produced → 2 t on hand.
        let invoice = try appDatabase.dbQueue.write { db in
            try saveInvoice(db: db, invoiceNo: "INV-2026-0070", date: .now, customerID: customer.id!, intraState: true,
                            lines: [DraftLine(productID: product.id!, qtyKg: 8_000, ratePaisePerTonne: 100_000, gstRateBps: 500)])
        }.invoice
        try appDatabase.dbQueue.write { db in
            try saveBatch(db: db, date: .now, lines: [(product.id!, 10_000)])
        }
        let onHand = try appDatabase.dbQueue.read { try balanceKg(db: $0, productID: product.id!) }
        XCTAssertEqual(onHand, 2_000)
        // Editing to 9 t re-adds the 8 t the same invoice already consumed: 2 + 8 = 10 ≥ 9 → ok.
        XCTAssertNoThrow(try appDatabase.dbQueue.write { db in
            try StockGate.requireAvailable(db: db, replacingInvoiceID: invoice.id!, required: [product.id!: 9_000], productName: { _ in "10mm" })
        })
        // A brand-new invoice over the 2 t on hand must be rejected.
        XCTAssertThrowsError(try appDatabase.dbQueue.write { db in
            try StockGate.requireAvailable(db: db, replacingInvoiceID: nil, required: [product.id!: 3_000], productName: { _ in "10mm" })
        })
        // Editing to 11 t exceeds 2 + 8 = 10 t → rejected.
        XCTAssertThrowsError(try appDatabase.dbQueue.write { db in
            try StockGate.requireAvailable(db: db, replacingInvoiceID: invoice.id!, required: [product.id!: 11_000], productName: { _ in "10mm" })
        })
    }
}

private enum WorkflowTestError: Error {
    case missingID
}