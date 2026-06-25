import Mimic
import Testing

struct LoadError: Error, Equatable {}

@Mockable
protocol DataClient {
    func load(id: Int) -> String
    func fetch(completion: @escaping (Result<Int, LoadError>) -> Void)
    func decode(_ raw: String) throws(LoadError) -> Int
    func send(_ payload: String)
}

@Suite("v0.3 ergonomics")
struct ErgonomicsTests {

    @Test("…ReturnValue stubs without a closure")
    func returnValueShorthand() {
        let mock = MockDataClient()
        mock.loadReturnValue = "stubbed"

        #expect(mock.load(id: 1) == "stubbed")
        #expect(mock.load(id: 2) == "stubbed")
        #expect(mock.loadReturnValue == "stubbed")
        #expect(mock.loadCallCount == 2)
    }

    @Test("completion-handler functions capture and invoke the closure")
    func completionHandlers() {
        let mock = MockDataClient()
        mock.fetchHandler = { completion in completion(.success(42)) }

        var received: Int?
        mock.fetch { result in received = try? result.get() }
        #expect(received == 42)
        #expect(mock.fetchCallCount == 1)
    }

    @Test("typed throws is preserved and propagates")
    func typedThrows() {
        let mock = MockDataClient()
        mock.decodeHandler = { (_: String) throws(LoadError) -> Int in throw LoadError() }
        #expect(throws: LoadError.self) {
            try mock.decode("nope")
        }
    }

    @Test("mimicReset clears handlers, counts, and recorded calls")
    func reset() {
        let mock = MockDataClient()
        mock.loadReturnValue = "x"
        _ = mock.load(id: 1)
        mock.send("a")
        #expect(mock.loadCallCount == 1)
        #expect(mock.sendCalls == ["a"])

        mock.mimicReset()
        #expect(mock.loadCallCount == 0)
        #expect(mock.sendCallCount == 0)
        #expect(mock.sendCalls.isEmpty)
        #expect(mock.loadHandler == nil)
    }
}
