import Mimic
import Testing

@Mockable
protocol Repo {
    func value(for key: String) -> Int
    func sum(_ a: Int, _ b: Int) -> Int
    func fetch(id: Int) async throws -> String
}

@Suite("Argument-matched stubs")
struct ArgumentMatchingTests {

    @Test("matched stubs return different results per argument")
    func matchedReturns() {
        let mock = MockRepo()
        mock.valueWhen({ $0 == "a" }, return: 1)
        mock.valueWhen({ $0 == "b" }, return: 2)

        #expect(mock.value(for: "a") == 1)
        #expect(mock.value(for: "b") == 2)
    }

    @Test("first matching stub wins, in registration order")
    func firstMatchWins() {
        let mock = MockRepo()
        mock.valueWhen({ _ in true }, return: 99)   // catch-all, registered first
        mock.valueWhen({ $0 == "a" }, return: 1)
        #expect(mock.value(for: "a") == 99)
    }

    @Test("falls back to the handler when nothing matches")
    func fallThrough() {
        let mock = MockRepo()
        mock.valueHandler = { _ in -1 }
        mock.valueWhen({ $0 == "a" }, return: 1)
        #expect(mock.value(for: "a") == 1)
        #expect(mock.value(for: "z") == -1)   // no stub matched → handler
    }

    @Test("perform runs custom behaviour for matched arguments")
    func performBehaviour() {
        let mock = MockRepo()
        mock.sumWhen({ a, b in a == b }, perform: { a, _ in a * 10 })
        mock.sumHandler = { a, b in a + b }
        #expect(mock.sum(3, 3) == 30)   // matched: a == b
        #expect(mock.sum(3, 4) == 7)    // unmatched: handler
    }

    @Test("works for async throws methods")
    func asyncThrows() async throws {
        let mock = MockRepo()
        mock.fetchWhen({ $0 == 1 }, return: "one")
        mock.fetchWhen({ $0 == 2 }, perform: { _ in "two" })
        #expect(try await mock.fetch(id: 1) == "one")
        #expect(try await mock.fetch(id: 2) == "two")
    }

    @Test("mimicReset clears matched stubs")
    func resetClearsStubs() {
        let mock = MockRepo()
        mock.valueWhen({ _ in true }, return: 5)
        #expect(mock.value(for: "x") == 5)
        mock.mimicReset()
        mock.valueHandler = { _ in 0 }
        #expect(mock.value(for: "x") == 0)   // stub gone, handler used
    }
}
