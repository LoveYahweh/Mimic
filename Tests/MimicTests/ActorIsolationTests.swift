import Mimic
import Testing

@MainActor
@Mockable
protocol ViewModelService: AnyObject {
    var title: String { get }
    func refresh() async
    func fetch(id: Int) async throws -> String
    func decode<T: Decodable>(_ type: T.Type, from raw: String) async throws -> T
}

@MainActor
@Suite("Actor-isolated protocols")
struct ActorIsolationTests {

    @Test("a @MainActor protocol produces a usable, isolated mock")
    func mainActorMock() async throws {
        let mock = MockViewModelService()
        mock.title = "Home"
        mock.refreshHandler = {}
        mock.fetchReturnValue = "ok"

        await mock.refresh()
        let value = try await mock.fetch(id: 1)

        #expect(mock.title == "Home")
        #expect(value == "ok")
        #expect(mock.refreshCallCount == 1)
        #expect(mock.fetchCalls == [1])
    }

    @Test("actor-isolated async generic method round-trips")
    func isolatedGeneric() async throws {
        let mock = MockViewModelService()
        mock.decodeHandler = { _, raw in Int(raw) ?? -1 }
        let n: Int = try await mock.decode(Int.self, from: "42")
        #expect(n == 42)
    }
}
