import Mimic
import Testing

@Mockable
protocol Store {
    func value(for key: String) -> Int
    func value(at index: Int) -> Int
    func reset()
    func reset(to value: Int)
}

@Suite("Overloaded requirements")
struct OverloadTests {

    @Test("label-disambiguated handlers stay independent")
    func independentHandlers() {
        let mock = MockStore()
        mock.valueForHandler = { _ in 1 }
        mock.valueAtHandler = { _ in 2 }

        #expect(mock.value(for: "a") == 1)
        #expect(mock.value(at: 0) == 2)
        #expect(mock.valueForCallCount == 1)
        #expect(mock.valueAtCallCount == 1)
        #expect(mock.valueForCalls == ["a"])
        #expect(mock.valueAtCalls == [0])
    }

    @Test("zero-arg overload keeps the bare name; the other is suffixed")
    func mixedArity() {
        let mock = MockStore()
        mock.reset()
        mock.resetToHandler = { _ in }
        mock.reset(to: 5)

        #expect(mock.resetCallCount == 1)
        #expect(mock.resetToCallCount == 1)
        #expect(mock.resetToCalls == [5])
    }
}
