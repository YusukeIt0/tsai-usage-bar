import Foundation

/// Short dollar amounts such as "$10" or "$12.5".
enum USDText {
    static func format(_ value: Double) -> String {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.minimumFractionDigits = 0
        f.maximumFractionDigits = 2
        return "$" + (f.string(from: NSNumber(value: value)) ?? String(value))
    }

    /// Money with cents: "$3.30".
    static func money(_ value: Double) -> String { String(format: "$%.2f", value) }
}
