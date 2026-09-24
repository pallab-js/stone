import Foundation
import GRDB

/// Master records that carry an `isActive` flag and can be deactivated when
/// hard deletion is blocked by referential integrity.
protocol DeactivatableMaster: MutablePersistableRecord, FetchableRecord {
    var isActive: Bool { get set }
}

extension Product: DeactivatableMaster {}
extension Customer: DeactivatableMaster {}
extension Supplier: DeactivatableMaster {}
extension Vehicle: DeactivatableMaster {}

enum MasterDeletion {
    enum Outcome: Equatable {
        case deleted
        case deactivated
    }

    /// Tries to hard-delete `id`. When foreign-key constraints prevent the
    /// delete (stock movements, invoice items, repayments reference the row),
    /// the record is deactivated instead so the UI never surfaces a raw
    /// "FOREIGN KEY constraint failed" error.
    static func delete<T: DeactivatableMaster>(_ type: T.Type, id: Int64, db: Database) throws -> Outcome {
        do {
            _ = try T.deleteOne(db, key: id)
            return .deleted
        } catch let error as DatabaseError where error.resultCode == .SQLITE_CONSTRAINT {
            if var record = try T.fetchOne(db, key: id) {
                record.isActive = false
                try record.update(db)
                return .deactivated
            }
            return .deleted
        }
    }
}