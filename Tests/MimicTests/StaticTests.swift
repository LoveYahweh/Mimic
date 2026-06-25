import Mimic
import Testing

@Mockable
protocol Environment {
    static var current: String { get }
    static func bootstrap(name: String) -> Bool
}

@Suite("Static requirements")
struct StaticTests {

    @Test("static methods and properties are mocked on the type")
    func staticMembers() {
        MockEnvironment.current = "test"
        MockEnvironment.bootstrapHandler = { $0 == "test" }

        #expect(MockEnvironment.current == "test")
        #expect(MockEnvironment.bootstrap(name: "test"))
        #expect(MockEnvironment.bootstrapCallCount == 1)
        #expect(MockEnvironment.bootstrapCalls == ["test"])
    }
}
