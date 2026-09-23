import XCTest
import GRDB
@testable import PaashERP

final class DatabaseTests: XCTestCase {
    private var appDatabase: AppDatabase!

    override func setUpWithError() throws {
        appDatabase = AppDatabase.inMemory()
    }

    func testProductCRUD() throws {
        try appDatabase.dbQueue.write { db in
            var product = Product(code: "TEN", name: "10mm")
            try product.insert(db)
            XCTAssertNotNil(product.id)
        }
        let count = try appDatabase.dbQueue.read { db in
            try Product.fetchCount(db)
        }
        XCTAssertEqual(count, 1)
    }

    func testProductRateCascadesOnProductDelete() throws {
        var productID: Int64?
        try appDatabase.dbQueue.write { db in
            var product = Product(code: "MSD", name: "M-Sand")
            try product.insert(db)
            productID = product.id
            var rate = ProductRate(productId: product.id!, ratePaisePerTonne: 95_000)
            try rate.insert(db)
        }
        XCTAssertEqual(
            try appDatabase.dbQueue.read { try ProductRate.fetchCount($0) },
            1
        )
        try appDatabase.dbQueue.write { db in
            try Product.deleteOne(db, key: productID!)
        }
        XCTAssertEqual(
            try appDatabase.dbQueue.read { try ProductRate.fetchCount($0) },
            0
        )
    }

    func testUniqueInvoiceNumbers() throws {
        let numbers: [String] = try appDatabase.dbQueue.read { db in
            try SalesInvoice.fetchAll(db).map(\.invoiceNo)
        }
        XCTAssertEqual(Set(numbers).count, numbers.count)
    }

    func testInvoiceTotalsAreConsistent() throws {
        let invoices = try appDatabase.dbQueue.read { db in
            try SalesInvoice.fetchAll(db)
        }
        for invoice in invoices {
            let expected = invoice.subtotalPaise
                + invoice.cgstPaise
                + invoice.sgstPaise
                + invoice.igstPaise
                + invoice.transportChargePaise
                - invoice.discountPaise
            XCTAssertEqual(invoice.grandTotalPaise, expected, "Mismatch on \(invoice.invoiceNo)")
        }
    }

    func testMasterDeletionRemovesUnreferencedProduct() throws {
        let id: Int64 = try appDatabase.dbQueue.write { db in
            var product = Product(code: "TEN", name: "10mm")
            try product.insert(db)
            return product.id!
        }
        let outcome = try appDatabase.dbQueue.write { db in
            try MasterDeletion.delete(Product.self, id: id, db: db)
        }
        XCTAssertEqual(outcome, .deleted)
        XCTAssertEqual(
            try appDatabase.dbQueue.read { try Product.fetchCount($0) },
            0
        )
    }

    func testMasterDeletionDeactivatesProductReferencedByStock() throws {
        let id: Int64 = try appDatabase.dbQueue.write { db in
            var product = Product(code: "TEN", name: "10mm")
            try product.insert(db)
            var move = StockMovement(productId: product.id!, date: .now, type: .production, qtyKg: 1_000)
            try move.insert(db)
            return product.id!
        }
        let outcome = try appDatabase.dbQueue.write { db in
            try MasterDeletion.delete(Product.self, id: id, db: db)
        }
        XCTAssertEqual(outcome, .deactivated)
        let (isActive, count) = try appDatabase.dbQueue.read { db in
            (try Product.fetchOne(db, key: id)!.isActive, try Product.fetchCount(db))
        }
        XCTAssertEqual(isActive, false)
        XCTAssertEqual(count, 1)
    }

    func testMasterDeletionDeactivatesCustomerReferencedByInvoice() throws {
        let id: Int64 = try appDatabase.dbQueue.write { db in
            var customer = Customer(name: "C")
            try customer.insert(db)
            var invoice = SalesInvoice(invoiceNo: "INV-2026-0001", date: .now, customerId: customer.id!)
            try invoice.insert(db)
            return customer.id!
        }
        let outcome = try appDatabase.dbQueue.write { db in
            try MasterDeletion.delete(Customer.self, id: id, db: db)
        }
        XCTAssertEqual(outcome, .deactivated)
        let (isActive, invoiceCount) = try appDatabase.dbQueue.read { db in
            (try Customer.fetchOne(db, key: id)!.isActive, try SalesInvoice.fetchCount(db))
        }
        XCTAssertEqual(isActive, false)
        XCTAssertEqual(invoiceCount, 1) // invoice keeps its snapshot
    }
}