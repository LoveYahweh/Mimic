import Foundation

/// A line in the shopping cart.
public struct CartItem: Equatable, Sendable {
    public let sku: String
    public let quantity: Int
    public let price: Decimal

    public init(sku: String, quantity: Int, price: Decimal) {
        self.sku = sku
        self.quantity = quantity
        self.price = price
    }
}

/// Proof of a successful charge.
public struct Receipt: Equatable, Sendable {
    public let id: String
    public let amount: Decimal

    public init(id: String, amount: Decimal) {
        self.id = id
        self.amount = amount
    }
}

/// A discount that can be applied at checkout.
public struct Coupon: Equatable, Sendable {
    public let code: String
    public let percentOff: Int

    public init(code: String, percentOff: Int) {
        self.code = code
        self.percentOff = percentOff
    }
}

/// The outcome of a completed checkout.
public struct CheckoutResult: Equatable, Sendable {
    public let receipt: Receipt
    public let discountApplied: Int
}

public enum CheckoutError: Error, Equatable {
    case emptyCart
    case outOfStock(sku: String)
    case paymentFailed
}
