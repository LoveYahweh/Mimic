import Mimic
import Testing

@Mockable
protocol Service {
    init(config: String)
    init?(optional value: Int)
    func run() -> Int
}

@Mockable
protocol ZeroArgInit {
    init()
    func ping()
}

@Mockable
protocol Functional {
    func map(_ transform: (Int) throws -> String) rethrows -> [String]
    func forEach(_ body: (Int) throws -> Void) rethrows
}

@Suite("init and rethrows")
struct InitAndRethrowsTests {

    @Test("required initializers satisfy the protocol and the mock is usable")
    func initRequirements() {
        let viaConfig = MockService(config: "x")
        viaConfig.runReturnValue = 7
        #expect(viaConfig.run() == 7)

        let viaOptional = MockService(optional: 1)
        #expect(viaOptional != nil)

        // The convenience no-arg init still exists alongside the required ones.
        let plain = MockService()
        plain.runReturnValue = 3
        #expect(plain.run() == 3)
    }

    @Test("a zero-parameter init requirement is satisfied without a duplicate")
    func zeroArgInit() {
        let mock = MockZeroArgInit()
        mock.ping()
        #expect(mock.pingCallCount == 1)
    }

    @Test("rethrows requirement: non-throwing call path")
    func rethrowsNonThrowing() {
        let mock = MockFunctional()
        mock.mapHandler = { transform in (try? [1, 2].map(transform)) ?? [] }
        let result = mock.map { "\($0)" }
        #expect(result == ["1", "2"])
        #expect(mock.mapCallCount == 1)
    }

    @Test("rethrows void requirement is callable")
    func rethrowsVoid() {
        let mock = MockFunctional()
        var captured = false
        mock.forEachHandler = { body in try? body(0); captured = true }
        mock.forEach { _ in }
        #expect(captured)
    }
}
