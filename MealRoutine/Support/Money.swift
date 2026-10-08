import Foundation

/// An amount in one ISO 4217 currency. Logic carries the code, never a symbol; symbols and
/// separators come from `MoneyFormat` at display time. There is no implicit conversion.
struct Money: Codable, Equatable, Hashable, Sendable {
    var amount: Decimal
    var currencyCode: String

    init(amount: Decimal, currencyCode: String) {
        self.amount = amount
        self.currencyCode = currencyCode
    }

    /// Sum of amounts in one currency. Nil when the currencies differ.
    func adding(_ other: Money) -> Money? {
        guard other.currencyCode == currencyCode else { return nil }
        return Money(amount: amount + other.amount, currencyCode: currencyCode)
    }
}

enum MoneyFormat {
    /// `₺1.200,50` for TRY in tr-TR, `$42.50` for USD in en-US. Symbol placement, separators and
    /// minor units all come from the locale and currency.
    static func string(_ money: Money, locale: Locale = RegionalContext.displayLocale) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = locale
        formatter.currencyCode = money.currencyCode
        return formatter.string(from: NSDecimalNumber(decimal: money.amount)) ?? "\(money.amount) \(money.currencyCode)"
    }
}
