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
        // Take the MAX existing number for this year so deletion never makes
        // the next number collide with an existing invoice.
        if let maxNo = try String.fetchOne(
            db,
            sql: "SELECT MAX(invoiceNo) FROM salesInvoices WHERE invoiceNo LIKE ?",
            arguments: [pattern + "%"]
        ), let last = maxNo.split(separator: "-").last, let number = Int(last) {
            return String(format: "%@%04d", pattern, number + 1)
        }
        return String(format: "%@%04d", pattern, 1)
    }
}