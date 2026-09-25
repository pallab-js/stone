import XCTest
import Foundation
import GRDB
@testable import PaashERP

final class ExportTests: XCTestCase {
    func testCSVWriterEscapesAndJoins() {
        let csv = CSVWriter.string(
            headers: ["a", "b"],
            rows: [["1,2", "x\"y"], ["3", "4"]]
        )
        XCTAssertEqual(csv, "a,b\n\"1,2\",\"x\"\"y\"\n3,4")
    }

    func testCSVWriterSkipsHeaderWhenEmpty() {
        let csv = CSVWriter.string(headers: [], rows: [["1", "2"]])
        XCTAssertEqual(csv, "1,2")
    }

    func testAmountInWordsBasic() {
        XCTAssertEqual(NumberToWords.inr(0), "Rupees Zero")
        XCTAssertEqual(NumberToWords.inr(1), "Rupees One")
        XCTAssertEqual(NumberToWords.inr(100), "Rupees One Hundred")
    }

    func testAmountInWordsLakhAndCrore() {
        XCTAssertEqual(NumberToWords.inr(100000), "Rupees One Lakh")
        XCTAssertEqual(NumberToWords.inr(10000000), "Rupees One Crore")
    }

    func testAmountInWordsWithPaise() {
        XCTAssertEqual(
            NumberToWords.inr(12345.67),
            "Rupees Twelve Thousand Three Hundred Forty Five and Paise Sixty Seven"
        )
    }

    func testAmountInWordsLargeIndianNumber() {
        XCTAssertEqual(
            NumberToWords.inr(123456789),
            "Rupees Twelve Crore Thirty Four Lakh Fifty Six Thousand Seven Hundred Eighty Nine"
        )
    }

    func testAmountInWordsHandlesTotalsAboveTwoThousandCrore() {
        // The crore chunk is the only one that can exceed 999, and the old
        // hundreds branch indexed belowTwenty[n / 100] — a 20-entry array —
        // with values like 25, trapping while rendering the invoice PDF.
        XCTAssertEqual(NumberToWords.inr(25_000_000_000), "Rupees Two Thousand Five Hundred Crore")
        XCTAssertEqual(NumberToWords.inr(200_000_000_000), "Rupees Twenty Thousand Crore")
        XCTAssertEqual(NumberToWords.inr(1_000_000_000_000), "Rupees One Lakh Crore")
        XCTAssertEqual(
            NumberToWords.inr(12_345_678_901_234),
            "Rupees Twelve Lakh Thirty Four Thousand Five Hundred Sixty Seven Crore "
                + "Eighty Nine Lakh One Thousand Two Hundred Thirty Four"
        )
    }

    func testInvoicePDFGenerationFromSeededInvoice() throws {
        let db = AppDatabase.inMemory()
        try DemoSeeder.seedIfNeeded(db.dbQueue)
        let documentData = try db.dbQueue.read { database in
            guard let invoice = try SalesInvoice.order(Column("id")).fetchOne(database),
                  let invoiceID = invoice.id,
                  let doc = try InvoiceDocumentLoader.load(database, invoiceID: invoiceID) else {
                throw ExportError.missingInvoice
            }
            return doc
        }
        let pdf = MainActor.assumeIsolated {
            DocumentExport.pdfData(root: InvoiceDocumentView(data: documentData))
        }
        XCTAssertNotNil(pdf)
        guard let pdf else { return }
        XCTAssertGreaterThan(pdf.count, 500, "PDF should carry document content")
        let header = String(data: pdf.prefix(5), encoding: .ascii)
        XCTAssertEqual(header, "%PDF-", "Expected a PDF document")
    }

    func testInvoiceLoaderPopulatesBusinessAndCustomer() throws {
        let db = AppDatabase.inMemory()
        try DemoSeeder.seedIfNeeded(db.dbQueue)
        let doc = try db.dbQueue.read { database in
            guard let invoice = try SalesInvoice.order(Column("id")).fetchOne(database),
                  let invoiceID = invoice.id else { throw ExportError.missingInvoice }
            return try InvoiceDocumentLoader.load(database, invoiceID: invoiceID)
        }
        let data = try XCTUnwrap(doc)
        XCTAssertEqual(data.business.name, "Shree Vitthal Stone Crusher")
        XCTAssertFalse(data.customerName.isEmpty)
        XCTAssertFalse(data.items.isEmpty)
        XCTAssertGreaterThan(data.invoice.grandTotalPaise, 0)
    }
}

enum ExportError: Error {
    case missingInvoice
}