import Foundation
import GRDB

/// Master records that carry an `isActive` flag and can be deactivated when
/// hard deletion is blocked by referential integrity.
protocol DeactivatableMaster: MutablePersistableRecord, FetchableRecord {
    var isActive: Bool { get set }

    /// Rows that reference this record from tables that cannot block the
    /// delete — `payments` has no foreign key to its party, and
    /// `purchases.supplierId` is `ON DELETE SET NULL`. Deleting despite those
    /// would orphan payments or silently erase a purchase's supplier, so the
    /// record is deactivated instead.
    static func softReferenceCount(id: Int64, db: Database) throws -> Int
}

extension Product: DeactivatableMaster {}
extension Customer: DeactivatableMaster {}
extension Supplier: DeactivatableMaster {}
extension Vehicle: DeactivatableMaster {}

extension Product {
    static func softReferenceCount(id: Int64, db: Database) throws -> Int { 0 }
}

extension Vehicle {
    static func softReferenceCount(id: Int64, db: Database) throws -> Int { 0 }
}

extension Customer {
    static func softReferenceCount(id: Int64, db: Database) throws -> Int {
        try Int.fetchOne(
            db,
            sql: "SELECT COUNT(*) FROM payments WHERE partyType = ? AND partyId = ?",
            arguments: [Payment.PartyType.customer.rawValue, id]
        ) ?? 0
    }
}

extension Supplier {
    static func softReferenceCount(id: Int64, db: Database) throws -> Int {
        try Int.fetchOne(
            db,
            sql: """
                SELECT (SELECT COUNT(*) FROM purchases WHERE supplierId = ?)
                     + (SELECT COUNT(*) FROM payments WHERE partyType = ? AND partyId = ?)
                """,
            arguments: [id, Payment.PartyType.supplier.rawValue, id]
        ) ?? 0
    }
}

enum MasterDeletion {
    enum Outcome: Equatable {
        case deleted
        case deactivated
    }

    /// Tries to hard-delete `id`. When foreign-key constraints prevent the
    /// delete (stock movements, invoice items, repayments reference the row),
    /// or when rows reference it without a blocking constraint, the record is
    /// deactivated instead so the UI never surfaces a raw "FOREIGN KEY
    /// constraint failed" error and no history is silently orphaned.
    static func delete<T: DeactivatableMaster>(_ type: T.Type, id: Int64, db: Database) throws -> Outcome {
        if try T.softReferenceCount(id: id, db: db) > 0 {
            return try deactivate(type, id: id, db: db)
        }
        do {
            _ = try T.deleteOne(db, key: id)
            return .deleted
        } catch let error as DatabaseError where error.resultCode == .SQLITE_CONSTRAINT {
            return try deactivate(type, id: id, db: db)
        }
    }

    private static func deactivate<T: DeactivatableMaster>(_ type: T.Type, id: Int64, db: Database) throws -> Outcome {
        if var record = try T.fetchOne(db, key: id) {
            record.isActive = false
            try record.update(db)
            return .deactivated
        }
        return .deleted
    }
}
