import Mimic
import Testing

@Mockable
protocol Feed {
    func next() -> Int
    func load(id: Int) throws -> String
    func fetch() async throws(FeedError) -> Int
    func ping()
}

enum FeedError: Error, Equatable { case offline }

@Suite("v0.6 richer stubbing")
struct StubbingTests {

    @Test("Returns yields each value in order, then repeats the last")
    func sequentialReturns() {
        let mock = MockFeed()
        mock.nextReturns(10, 20, 30)
        #expect(mock.next() == 10)
        #expect(mock.next() == 20)
        #expect(mock.next() == 30)
        #expect(mock.next() == 30)   // exhausted → last value repeats
        #expect(mock.nextCallCount == 4)
    }

    @Test("a single Returns value behaves like a constant stub")
    func singleReturn() {
        let mock = MockFeed()
        mock.nextReturns(7)
        #expect(mock.next() == 7)
        #expect(mock.next() == 7)
    }

    @Test("ThrowsError makes a throwing method throw the given error")
    func throwsError() {
        struct Boom: Error {}
        let mock = MockFeed()
        mock.loadThrowsError(Boom())
        #expect(throws: Boom.self) { try mock.load(id: 1) }
    }

    @Test("ThrowsError respects a typed-throws signature")
    func typedThrowsError() async {
        let mock = MockFeed()
        mock.fetchThrowsError(.offline)            // parameter is FeedError, not any Error
        await #expect(throws: FeedError.offline) { try await mock.fetch() }
    }

    @Test("Returns is cleared by mimicReset")
    func resetClearsReturns() {
        let mock = MockFeed()
        mock.nextReturns(1, 2)
        _ = mock.next()
        mock.mimicReset()
        #expect(mock.nextCallCount == 0)
        #expect(mock.nextHandler == nil)
    }
}
