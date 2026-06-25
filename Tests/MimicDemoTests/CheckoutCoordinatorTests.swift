import Foundation
import Testing
@testable import MimicDemo

/// A fresh set of mocks plus a coordinator wired to them. Each test stubs only
/// what it needs and then asserts both the result and the interactions.
private struct System {
    let cart = MockCartStore()
    let inventory = MockInventoryService()
    let payments = MockPaymentGateway()
    let coupons = MockCouponService()
    let analytics = MockAnalytics()

    var coordinator: CheckoutCoordinator {
        CheckoutCoordinator(
            cart: cart,
            inventory: inventory,
            payments: payments,
            coupons: coupons,
            analytics: analytics
        )
    }

    /// Stub the collaborators so a checkout succeeds, charging the amount asked.
    func stubSuccessfulInfrastructure(items: [CartItem]) {
        cart.items = items
        inventory.availableReturnValue = .max          // …ReturnValue shorthand
        inventory.reserveReturnValue = true
        payments.chargeHandler = { amount, _ in Receipt(id: "rcpt_1", amount: amount) }
    }
}

private struct StubPaymentError: Error {}

@Suite("CheckoutCoordinator")
struct CheckoutCoordinatorTests {

    @Test("happy path charges the subtotal, clears the cart, and tracks success")
    func happyPath() async throws {
        let sys = System()
        sys.stubSuccessfulInfrastructure(items: [
            CartItem(sku: "A", quantity: 2, price: 10),
            CartItem(sku: "B", quantity: 1, price: 5),
        ])

        let result = try await sys.coordinator.checkout(token: "tok", couponCode: nil)

        // Result.
        #expect(result.receipt.id == "rcpt_1")
        #expect(result.discountApplied == 0)
        #expect(result.receipt.amount == 25)

        // Interactions: every line was reserved, the charge used the subtotal.
        #expect(sys.inventory.reserveCallCount == 2)
        #expect(sys.inventory.reserveLastCall?.sku == "B")
        #expect(sys.payments.chargeLastCall?.amount == 25)
        #expect(sys.cart.clearWasCalled)
        #expect(sys.analytics.trackLastCall?.event == "checkout_succeeded")
    }

    @Test("a coupon reduces the charged amount")
    func couponDiscount() async throws {
        let sys = System()
        sys.stubSuccessfulInfrastructure(items: [CartItem(sku: "A", quantity: 2, price: 10)])
        // Completion-handler dependency: invoke the captured callback.
        sys.coupons.loadCouponHandler = { code, completion in
            completion(Coupon(code: code, percentOff: 10))
        }

        let result = try await sys.coordinator.checkout(token: "tok", couponCode: "SAVE10")

        #expect(result.discountApplied == 10)
        #expect(sys.payments.chargeLastCall?.amount == 18)        // 20 - 10%
        #expect(sys.coupons.loadCouponLastCall?.code == "SAVE10")
    }

    @Test("an empty cart fails before touching payment")
    func emptyCart() async {
        let sys = System()
        sys.cart.items = []

        await #expect(throws: CheckoutError.emptyCart) {
            try await sys.coordinator.checkout(token: "tok", couponCode: nil)
        }
        #expect(sys.payments.chargeWasCalled == false)
        #expect(sys.analytics.trackLastCall?.properties["reason"] == "empty_cart")
    }

    @Test("insufficient stock fails with the offending sku")
    func outOfStock() async {
        let sys = System()
        sys.cart.items = [CartItem(sku: "B", quantity: 5, price: 1)]
        sys.inventory.availableReturnValue = 0

        await #expect(throws: CheckoutError.outOfStock(sku: "B")) {
            try await sys.coordinator.checkout(token: "tok", couponCode: nil)
        }
        #expect(sys.payments.chargeWasCalled == false)
        #expect(sys.analytics.trackLastCall?.properties["sku"] == "B")
    }

    @Test("a payment failure surfaces and leaves the cart intact")
    func paymentFailure() async {
        let sys = System()
        sys.stubSuccessfulInfrastructure(items: [CartItem(sku: "A", quantity: 1, price: 9)])
        sys.payments.chargeHandler = { _, _ in throw StubPaymentError() }

        await #expect(throws: CheckoutError.paymentFailed) {
            try await sys.coordinator.checkout(token: "tok", couponCode: nil)
        }
        #expect(sys.cart.clearWasCalled == false)
        #expect(sys.analytics.trackLastCall?.properties["reason"] == "payment")
    }

    @Test("mimicReset returns a reused mock to a clean slate")
    func resettingMocks() async throws {
        let sys = System()
        sys.stubSuccessfulInfrastructure(items: [CartItem(sku: "A", quantity: 1, price: 1)])
        _ = try await sys.coordinator.checkout(token: "tok", couponCode: nil)
        #expect(sys.analytics.trackCallCount > 0)

        sys.analytics.mimicReset()
        #expect(sys.analytics.trackCallCount == 0)
        #expect(sys.analytics.trackCalls.isEmpty)
    }
}
