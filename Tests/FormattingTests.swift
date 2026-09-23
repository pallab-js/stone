import XCTest
import Foundation
@testable import PaashERP

final class FormattingTests: XCTestCase {
    func testIndianCurrencyGrouping() {
        XCTAssertEqual(Format.inr(123_456), "₹1,234.56")
        XCTAssertEqual(Format.inr(123_456_00), "₹1,23,456.00")
        XCTAssertEqual(Format.inr(1_23_45_678_90), "₹1,23,45,678.90")
    }

    func testCompactLakhAndCrore() {
        XCTAssertEqual(Format.inrCompact(100_000_00), "₹1 L")
        XCTAssertEqual(Format.inrCompact(135_000_00), "₹1.4 L")
        XCTAssertEqual(Format.inrCompact(1_00_00_00_00_00), "₹1 Cr")
        XCTAssertEqual(Format.inrCompact(4_999), "₹49.99")
    }

    func testTonnesAndKilograms() {
        XCTAssertEqual(Format.tonnesLabel(1_500_000), "1,500.00 t")
        XCTAssertEqual(Format.tonnesLabel(520), "0.52 t")
        XCTAssertEqual(Format.kilograms(12_345), "12,345")
    }

    func testGSTPercent() {
        XCTAssertEqual(Format.percent(bps: 500), "5%")
        XCTAssertEqual(Format.percent(bps: 1200), "12%")
        XCTAssertEqual(Format.percent(bps: 0), "0%")
    }

    func testRupeesWithoutSymbol() {
        XCTAssertEqual(Format.rupeesWithoutSymbol(150_000_00), "1,50,000.00")
    }
}