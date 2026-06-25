import Mimic
import Testing

// MARK: - Protocols under test

@Mockable
protocol Calculator {
    func add(_ a: Int, _ b: Int) -> Int
    func reset()
}

@Mockable
protocol Repository {
    var isReady: Bool { get }
    var token: String? { get set }
    func fetch(id: Int) async throws -> String
    func save(name: String, value: Int) throws
}

// MARK: - Behaviour

@Suite("Generated mock behaviour")
struct MockBehaviourTests {

    @Test("stubs return values and records call count")
    func stubsAndCounts() {
        let mock = MockCalculator()
        mock.addHandler = { a, b in a + b }

        #expect(mock.add(2, 3) == 5)
        #expect(mock.add(10, 1) == 11)
        #expect(mock.addCallCount == 2)
    }

    @Test("records arguments for multi-parameter methods as a labelled tuple")
    func recordsArguments() {
        let mock = MockCalculator()
        mock.addHandler = { _, _ in 0 }

        _ = mock.add(7, 8)
        #expect(mock.addCalls.first?.a == 7)
        #expect(mock.addCalls.first?.b == 8)
    }

    @Test("void methods need no handler and still count")
    func voidMethods() {
        let mock = MockCalculator()
        mock.reset()
        mock.reset()
        #expect(mock.resetCallCount == 2)
    }

    @Test("settable properties round-trip; get-only is settable in the mock")
    func properties() {
        let mock = MockRepository()
        mock.isReady = true
        mock.token = "abc"
        #expect(mock.isReady)
        #expect(mock.token == "abc")
    }

    @Test("async throwing methods propagate stubbed results")
    func asyncThrows() async throws {
        let mock = MockRepository()
        mock.fetchHandler = { id in "row-\(id)" }
        let value = try await mock.fetch(id: 42)
        #expect(value == "row-42")
        #expect(mock.fetchCalls == [42])
    }

    @Test("stubbed errors are thrown")
    func throwsErrors() async {
        struct Boom: Error {}
        let mock = MockRepository()
        mock.fetchHandler = { _ in throw Boom() }
        await #expect(throws: Boom.self) {
            _ = try await mock.fetch(id: 1)
        }
    }
}
