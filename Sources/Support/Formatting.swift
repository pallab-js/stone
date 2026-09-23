import Foundation

enum Format {
    private static let currencyFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_IN")
        formatter.numberStyle = .currency
        formatter.currencyCode = "INR"
        formatter.currencySymbol = "₹"
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2
        return formatter
    }()

    private static let numberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_IN")
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 0
        return formatter
    }()

    private static let tonnesFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_IN")
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2
        return formatter
    }()

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_IN")
        formatter.dateFormat = "d MMMM yyyy"
        return formatter
    }()

    private static let shortDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_IN")
        formatter.dateFormat = "d MMM yyyy"
        return formatter
    }()

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_IN")
        formatter.dateFormat = "h:mm a"
        return formatter
    }()

    static func inr(_ paise: Int64) -> String {
        let rupees = Double(paise) / 100.0
        return currencyFormatter.string(from: NSNumber(value: rupees)) ?? "₹0.00"
    }

    static func inrCompact(_ paise: Int64) -> String {
        let rupees = Double(paise) / 100.0
        if rupees >= 100_000_000 {
            return "₹\(tenth(rupees / 100_000_000)) Cr"
        }
        if rupees >= 100_000 {
            return "₹\(tenth(rupees / 100_000)) L"
        }
        return inr(paise)
    }

    static func rupees(_ amount: Double, decimals: Int = 2) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_IN")
        formatter.numberStyle = .currency
        formatter.currencyCode = "INR"
        formatter.currencySymbol = "₹"
        formatter.maximumFractionDigits = decimals
        formatter.minimumFractionDigits = decimals
        return formatter.string(from: NSNumber(value: amount)) ?? "₹0"
    }

    static func rupeesWithoutSymbol(_ paise: Int64) -> String {
        let rupees = Double(paise) / 100.0
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_IN")
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2
        return formatter.string(from: NSNumber(value: rupees)) ?? "0.00"
    }

    static func tonnes(_ kg: Int64) -> String {
        let tonnes = Double(kg) / 1000.0
        return tonnesFormatter.string(from: NSNumber(value: tonnes)) ?? "0.00"
    }

    static func tonnesLabel(_ kg: Int64) -> String {
        "\(tonnes(kg)) t"
    }

    static func kilograms(_ kg: Int64) -> String {
        numberFormatter.string(from: NSNumber(value: kg)) ?? String(kg)
    }

    static func percent(bps: Int) -> String {
        let value = Double(bps) / 100.0
        if value.truncatingRemainder(dividingBy: 1) == 0 {
            return "\(Int(value))%"
        }
        return "\(value)%"
    }

    /// Parses user-typed numeric input into a Double.
    ///
    /// Commas are treated as Indian thousands-grouping separators and removed;
    /// "." is the decimal separator. Returns nil for empty or malformed input.
    /// e.g. "1,50,000.50" → 150000.5, "6mm" → nil.
    static func parse(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let normalized = trimmed.replacingOccurrences(of: ",", with: "")
        return Double(normalized)
    }

    /// Parses a user-typed rupee amount into paise. Empty or invalid input → 0.
    /// Handles Indian digit grouping: "15,000" → 1,500,000 paise (₹15,000).
    static func paise(_ text: String) -> Int64 {
        guard let value = parse(text) else { return 0 }
        return Int64((value * 100).rounded())
    }

    /// Parses a user-typed tonne quantity into kilograms. Empty or invalid input → 0.
    /// "12.5" → 12,500 kg.
    static func kg(fromTonnes text: String) -> Int64 {
        guard let value = parse(text) else { return 0 }
        return Int64((value * 1000).rounded())
    }

    static func day(_ date: Date) -> String {
        dayFormatter.string(from: date)
    }

    static func shortDate(_ date: Date) -> String {
        shortDateFormatter.string(from: date)
    }

    static func time(_ date: Date) -> String {
        timeFormatter.string(from: date)
    }

    private static func tenth(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        if rounded.truncatingRemainder(dividingBy: 1) == 0 {
            return "\(Int(rounded))"
        }
        return String(format: "%.1f", rounded)
    }
}