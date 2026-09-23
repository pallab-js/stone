import Foundation
import GRDB

struct Vehicle: Identifiable, Codable, Equatable, Hashable, Sendable {
    var id: Int64?
    var number: String
    var ownership: Ownership
    var capacityKg: Int64
    var driverName: String?
    var driverPhone: String?
    var isActive: Bool
    var createdAt: Date
    var updatedAt: Date

    enum Ownership: String, Codable, Sendable, CaseIterable, Identifiable {
        case own = "own"
        case hired = "hired"

        var id: String { rawValue }
        var label: String {
            switch self {
            case .own: "Own"
            case .hired: "Hired"
            }
        }
    }

    init(
        id: Int64? = nil,
        number: String,
        ownership: Ownership = .own,
        capacityKg: Int64 = 20_000,
        driverName: String? = nil,
        driverPhone: String? = nil,
        isActive: Bool = true,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.number = number
        self.ownership = ownership
        self.capacityKg = capacityKg
        self.driverName = driverName
        self.driverPhone = driverPhone
        self.isActive = isActive
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

extension Vehicle: TableRecord, FetchableRecord, MutablePersistableRecord {
    static var databaseTableName: String { "vehicles" }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}