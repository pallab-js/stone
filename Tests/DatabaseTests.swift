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

    func testMasterDeletionDeactivatesCustomerReferencedOnlyByPayments() throws {
        // `payments` has no foreign key to its party, so the delete would
        // otherwise succeed and orphan the payment (and drop it from the
        // receivables maths, while reports still sum it).
        let id: Int64 = try appDatabase.dbQueue.write { db in
            var customer = Customer(name: "Advance Only")
            try customer.insert(db)
            var payment = Payment(partyType: .customer, partyId: customer.id!, kind: .advance, amountPaise: 50_000)
            try payment.insert(db)
            return customer.id!
        }
        let outcome = try appDatabase.dbQueue.write { db in
            try MasterDeletion.delete(Customer.self, id: id, db: db)
        }
        XCTAssertEqual(outcome, .deactivated)
        let (customerCount, paymentCount, isActive) = try appDatabase.dbQueue.read { db in
            (try Customer.fetchCount(db), try Payment.fetchCount(db), try Customer.fetchOne(db, key: id)!.isActive)
        }
        XCTAssertEqual(customerCount, 1, "customer must be deactivated, not deleted")
        XCTAssertEqual(paymentCount, 1, "payment must survive")
        XCTAssertEqual(isActive, false)
    }

    func testMasterDeletionDeactivatesSupplierReferencedByPurchase() throws {
        // `purchases.supplierId` is ON DELETE SET NULL, so a plain delete would
        // succeed while silently stripping the supplier off every purchase.
        let id: Int64 = try appDatabase.dbQueue.write { db in
            var supplier = Supplier(name: "Crusher Hire")
            try supplier.insert(db)
            var purchase = Purchase(supplierId: supplier.id!, category: .royalty, amountPaise: 100_000)
            try purchase.insert(db)
            return supplier.id!
        }
        let outcome = try appDatabase.dbQueue.write { db in
            try MasterDeletion.delete(Supplier.self, id: id, db: db)
        }
        XCTAssertEqual(outcome, .deactivated)
        let (supplierCount, supplierID, isActive) = try appDatabase.dbQueue.read { db in
            (try Supplier.fetchCount(db), try Purchase.fetchOne(db)!.supplierId, try Supplier.fetchOne(db, key: id)!.isActive)
        }
        XCTAssertEqual(supplierCount, 1, "supplier must be deactivated, not deleted")
        XCTAssertEqual(supplierID, id, "purchase must keep its supplier")
        XCTAssertEqual(isActive, false)
    }

    func testMasterDeletionStillHardDeletesUnusedSupplierAndCustomer() throws {
        let (supplierID, customerID): (Int64, Int64) = try appDatabase.dbQueue.write { db in
            var supplier = Supplier(name: "Unused")
            try supplier.insert(db)
            var customer = Customer(name: "Unused")
            try customer.insert(db)
            return (supplier.id!, customer.id!)
        }
        let outcomes = try appDatabase.dbQueue.write { db in
            (
                try MasterDeletion.delete(Supplier.self, id: supplierID, db: db),
                try MasterDeletion.delete(Customer.self, id: customerID, db: db)
            )
        }
        XCTAssertEqual(outcomes.0, .deleted)
        XCTAssertEqual(outcomes.1, .deleted)
        let counts = try appDatabase.dbQueue.read { db in
            (try Supplier.fetchCount(db), try Customer.fetchCount(db))
        }
        XCTAssertEqual(counts.0, 0)
        XCTAssertEqual(counts.1, 0)
    }
}