import Foundation
import GRDB

/// Sequential, per-year invoice numbering driven by the configured
/// `invoice_prefix` app setting (default "INV").
///
/// Both the app and the demo seeder generate numbers through this one path,
/// so a database never mixes "PI-…" and "INV-…" numbering.
enum InvoiceNumber {
    static func next(db: Database, for date: Date = .now) throws -> String {
        let year = Calendar.autoupdatingCurrent.component(.year, from: date)
        let prefix = (try AppSetting.value(forKey: "invoice_prefix", db: db)) ?? "INV"
        let pattern = "\(prefix)-\(year)-"
        let matchingNumbers = try String.fetchAll(
            db,
            sql: "SELECT invoiceNo FROM salesInvoices WHERE invoiceNo LIKE ?",
            arguments: [pattern + "%"]
        )
        let maxNumber = matchingNumbers.compactMap { no -> Int? in
            guard let last = no.split(separator: "-").last else { return nil }
            return Int(last)
        }.max() ?? 0

        return String(format: "%@%04d", pattern, maxNumber + 1)
    }
}
