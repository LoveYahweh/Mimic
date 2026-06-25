import Mimic
import Testing

@Mockable
protocol Pipeline {
    func validate() -> Bool
    func reserve(_ sku: String) -> Bool
    func charge(amount: Int) async throws
    func clear()
}

@Suite("Order-aware verification")
struct VerificationTests {

    @Test("mimicInvocations records calls in order")
    func recordsOrder() async throws {
        let mock = MockPipeline()
        mock.validateReturnValue = true
        mock.reserveReturnValue = true

        _ = mock.validate()
        _ = mock.reserve("A")
        try await mock.charge(amount: 100)
        mock.clear()

        #expect(mock.mimicInvocations == [.validate, .reserve, .charge, .clear])
    }

    @Test("mimicVerify checks ordering between two members")
    func verifyOrdering() async throws {
        let mock = MockPipeline()
        mock.validateReturnValue = true
        mock.reserveReturnValue = true

        _ = mock.validate()
        _ = mock.reserve("A")
        try await mock.charge(amount: 100)

        #expect(mock.mimicVerify(.validate, before: .charge))
        #expect(mock.mimicVerify(.reserve, before: .charge))
        #expect(mock.mimicVerify(.charge, before: .validate) == false)
    }

    @Test("mimicVerify is false when a member was never called")
    func verifyMissing() {
        let mock = MockPipeline()
        mock.clear()
        #expect(mock.mimicVerify(.clear, before: .validate) == false)
    }

    @Test("ordering uses first occurrence of earlier and last of later")
    func repeatedCalls() {
        let mock = MockPipeline()
        mock.reserveReturnValue = true
        _ = mock.reserve("A")
        mock.clear()
        _ = mock.reserve("B")
        // reserve appears before and after clear; first reserve precedes last clear
        #expect(mock.mimicVerify(.reserve, before: .clear))
    }

    @Test("mimicReset clears the invocation log")
    func resetClearsLog() {
        let mock = MockPipeline()
        mock.clear()
        #expect(mock.mimicInvocations == [.clear])
        mock.mimicReset()
        #expect(mock.mimicInvocations.isEmpty)
    }
}
