import Foundation
import Mimic

/// The cart being checked out. A get-only collection property plus a command.
@Mockable
public protocol CartStore {
    var items: [CartItem] { get }
    func clear()
}

/// Stock checks and reservations — plain synchronous methods with return values.
@Mockable
public protocol InventoryService {
    func available(sku: String) -> Int
    func reserve(sku: String, quantity: Int) -> Bool
}

/// The payment backend — an `async throws` method.
@Mockable
public protocol PaymentGateway {
    func charge(amount: Decimal, token: String) async throws -> Receipt
}

/// A callback-style coupon lookup — a completion handler.
@Mockable
public protocol CouponService {
    func loadCoupon(code: String, completion: @escaping (Coupon?) -> Void)
}

/// Fire-and-forget analytics — a void method taking a dictionary.
@Mockable
public protocol Analytics {
    func track(_ event: String, properties: [String: String])
}
