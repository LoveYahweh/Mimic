import Foundation

/// Orchestrates a checkout across the cart, inventory, payment, coupon, and
/// analytics dependencies. This is the unit under test in `MimicDemoTests`;
/// every collaborator is a protocol, so tests drive it entirely with mocks.
public struct CheckoutCoordinator {
    let cart: CartStore
    let inventory: InventoryService
    let payments: PaymentGateway
    let coupons: CouponService
    let analytics: Analytics

    public init(
        cart: CartStore,
        inventory: InventoryService,
        payments: PaymentGateway,
        coupons: CouponService,
        analytics: Analytics
    ) {
        self.cart = cart
        self.inventory = inventory
        self.payments = payments
        self.coupons = coupons
        self.analytics = analytics
    }

    public func checkout(token: String, couponCode: String?) async throws -> CheckoutResult {
        let items = cart.items
        guard !items.isEmpty else {
            analytics.track("checkout_failed", properties: ["reason": "empty_cart"])
            throw CheckoutError.emptyCart
        }

        // Confirm stock and reserve every line before taking payment.
        for item in items {
            guard inventory.available(sku: item.sku) >= item.quantity,
                  inventory.reserve(sku: item.sku, quantity: item.quantity) else {
                analytics.track("checkout_failed", properties: ["reason": "out_of_stock", "sku": item.sku])
                throw CheckoutError.outOfStock(sku: item.sku)
            }
        }

        // Optional coupon, looked up through a completion-handler API.
        var discount = 0
        if let couponCode {
            discount = await loadCoupon(couponCode)?.percentOff ?? 0
        }

        let subtotal = items.reduce(Decimal(0)) { $0 + $1.price * Decimal($1.quantity) }
        let amount = subtotal * Decimal(100 - discount) / 100

        let receipt: Receipt
        do {
            receipt = try await payments.charge(amount: amount, token: token)
        } catch {
            analytics.track("checkout_failed", properties: ["reason": "payment"])
            throw CheckoutError.paymentFailed
        }

        cart.clear()
        analytics.track("checkout_succeeded", properties: ["receipt": receipt.id])
        return CheckoutResult(receipt: receipt, discountApplied: discount)
    }

    private func loadCoupon(_ code: String) async -> Coupon? {
        await withCheckedContinuation { continuation in
            coupons.loadCoupon(code: code) { continuation.resume(returning: $0) }
        }
    }
}
