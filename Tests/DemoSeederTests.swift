import XCTest
import GRDB
@testable import PaashERP

final class DemoSeederTests: XCTestCase {
    private func seededDatabase() throws -> AppDatabase {
        let db = AppDatabase.inMemory()
        try DemoSeeder.seedIfNeeded(db.dbQueue)
        return db
    }

    func testSeedsMastersAndTransactions() throws {
        let db = try seededDatabase()
        let counts = try db.dbQueue.read { database in
            (
                try Product.fetchCount(database),
                try Customer.fetchCount(database),
                try Supplier.fetchCount(database),
                try Vehicle.fetchCount(database),
                try ProductionBatch.fetchCount(database),
                try SalesInvoice.fetchCount(database),
                try Payment.fetchCount(database),
                try Purchase.fetchCount(database)
            )
        }
        XCTAssertEqual(counts.0, 7, "products")
        XCTAssertEqual(counts.1, 8, "customers")
        XCTAssertEqual(counts.2, 4, "suppliers")
        XCTAssertEqual(counts.3, 6, "vehicles")
        XCTAssertGreaterThan(counts.4, 0, "production batches")
        XCTAssertGreaterThan(counts.5, 80, "sales invoices across 30 days")
        XCTAssertGreaterThan(counts.6, 0, "payments")
        XCTAssertGreaterThan(counts.7, 0, "purchases")
    }

    func testSeedIsIdempotent() throws {
        let db = AppDatabase.inMemory()
        try DemoSeeder.seedIfNeeded(db.dbQueue)
        try DemoSeeder.seedIfNeeded(db.dbQueue)
        let count = try db.dbQueue.read { try SalesInvoice.fetchCount($0) }
        XCTAssertGreaterThanOrEqual(count, 80)
    }

    func testStockNeverGoesNegative() throws {
        let db = try seededDatabase()
        struct Row: Decodable, FetchableRecord {
            var productId: Int64
            var balanceKg: Int64
        }
        let negative = try db.dbQueue.read { database in
            try Row.fetchAll(
                database,
                sql: "SELECT productId, SUM(qtyKg) AS balanceKg FROM stockMovements GROUP BY productId HAVING SUM(qtyKg) < 0"
            )
        }
        XCTAssertTrue(negative.isEmpty, "Negative stock found: \(negative)")
    }

    func testEveryProductProducedAndSold() throws {
        let db = try seededDatabase()
        struct Row: Decodable, FetchableRecord {
            var productId: Int64
            var qtyKg: Int64
        }
        let produced = try db.dbQueue.read { database in
            try Row.fetchAll(
                database,
                sql: "SELECT productId, SUM(qtyKg) AS qtyKg FROM stockMovements WHERE type = 'production' GROUP BY productId"
            )
        }
        let sold = try db.dbQueue.read { database in
            try Row.fetchAll(
                database,
                sql: "SELECT productId, SUM(qtyKg) AS qtyKg FROM stockMovements WHERE type = 'sale' GROUP BY productId"
            )
        }
        XCTAssertEqual(produced.count, 7)
        XCTAssertEqual(sold.count, 7)
        for producedRow in produced {
            let soldRow = sold.first { $0.productId == producedRow.productId }
            XCTAssertNotNil(soldRow, "Product \(producedRow.productId) never sold")
            XCTAssertLessThan(soldRow!.qtyKg, 0, "Sale movement should be negative")
        }
    }
}