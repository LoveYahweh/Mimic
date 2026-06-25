import Mimic
import Testing

// MARK: - Protocols exercising the full supported surface

@Mockable
protocol Empty {}

@Mockable
protocol Signatures {
    func noArgsVoid()
    func threeArgs(_ a: Int, b: String, c: Bool) -> String
    func update(_ value: inout Int)
    mutating func bump()
    func onChange(_ cb: ((Int) -> Void)?)
    func makeAdder(base: Int) -> (Int) -> Int
    func pair() -> (Int, String)
    func withDefault(x: Int, flag: Bool)
}

@Mockable
protocol Effects {
    func sync() -> Int
    func throwing() throws -> Int
    func asynchronous() async -> Int
    func asyncThrowing() async throws -> Int
}

@Mockable
protocol Properties {
    var readOnly: Int { get }
    var readWrite: String { get set }
    var optional: Int? { get }
    var collection: [String] { get }
}

@Mockable
protocol Overloads {
    func f(_ x: Int)            // by type vs the next
    func f(_ x: String)
    func g()                   // by async vs the next
    func g() async
    func h(a: Int)             // by arity / label vs the next
    func h(a: Int, b: Int)
}

// MARK: - Tests

@Suite("Full coverage — signatures")
struct SignatureCoverageTests {

    @Test("no-arg void method counts without a handler")
    func noArgsVoid() {
        let mock = MockSignatures()
        mock.noArgsVoid()
        mock.noArgsVoid()
        #expect(mock.noArgsVoidCallCount == 2)
        #expect(mock.noArgsVoidWasCalled)
    }

    @Test("three arguments are recorded as a labelled tuple")
    func threeArgs() {
        let mock = MockSignatures()
        mock.threeArgsReturnValue = "ok"
        _ = mock.threeArgs(1, b: "two", c: true)
        let last = mock.threeArgsLastCall
        #expect(last?.a == 1)
        #expect(last?.b == "two")
        #expect(last?.c == true)
    }

    @Test("inout parameter is forwarded with & and the value is recorded")
    func inoutParameter() {
        let mock = MockSignatures()
        mock.updateHandler = { value in value += 100 }
        var n = 5
        mock.update(&n)
        #expect(n == 105)
        #expect(mock.updateCalls == [5])   // recorded the value at call time
    }

    @Test("mutating requirement is witnessed by a plain method")
    func mutatingRequirement() {
        let mock = MockSignatures()
        mock.bump()
        #expect(mock.bumpCallCount == 1)
    }

    @Test("optional closure parameter")
    func optionalClosureParameter() {
        let mock = MockSignatures()
        var fired = 0
        mock.onChangeHandler = { cb in cb?(7) }
        mock.onChange { fired = $0 }
        #expect(fired == 7)
    }

    @Test("closure return type stubs and returns")
    func closureReturn() {
        let mock = MockSignatures()
        mock.makeAdderHandler = { base in { $0 + base } }
        let add10 = mock.makeAdder(base: 10)
        #expect(add10(5) == 15)
    }

    @Test("tuple return type")
    func tupleReturn() {
        let mock = MockSignatures()
        mock.pairReturnValue = (1, "one")
        let p = mock.pair()
        #expect(p.0 == 1)
        #expect(p.1 == "one")
    }

    @Test("default parameter values don't break conformance")
    func defaultValues() {
        let mock = MockSignatures()
        mock.withDefault(x: 1, flag: true)
        #expect(mock.withDefaultLastCall?.x == 1)
    }

    @Test("empty protocol produces a usable mock")
    func emptyProtocol() {
        _ = MockEmpty()
    }
}

@Suite("Full coverage — effects")
struct EffectsCoverageTests {

    @Test("sync, throwing, async, async throwing all stub via ReturnValue")
    func allEffects() async throws {
        let mock = MockEffects()
        mock.syncReturnValue = 1
        mock.throwingReturnValue = 2
        mock.asynchronousReturnValue = 3
        mock.asyncThrowingReturnValue = 4

        #expect(mock.sync() == 1)
        #expect(try mock.throwing() == 2)
        #expect(await mock.asynchronous() == 3)
        #expect(try await mock.asyncThrowing() == 4)
    }

    @Test("a throwing handler propagates")
    func throwingPropagates() {
        struct E: Error {}
        let mock = MockEffects()
        mock.throwingHandler = { throw E() }
        #expect(throws: E.self) { try mock.throwing() }
    }
}

@Suite("Full coverage — properties")
struct PropertyCoverageTests {

    @Test("read-only and read-write properties round-trip")
    func roundTrip() {
        let mock = MockProperties()
        mock.readOnly = 42
        mock.readWrite = "hi"
        mock.collection = ["a"]
        #expect(mock.readOnly == 42)
        #expect(mock.readWrite == "hi")
        #expect(mock.collection == ["a"])
    }

    @Test("optional property defaults to nil")
    func optionalDefaultsNil() {
        let mock = MockProperties()
        #expect(mock.optional == nil)
        mock.optional = 9
        #expect(mock.optional == 9)
    }

    @Test("mutating a read-write property through the protocol")
    func readWriteMutation() {
        let mock = MockProperties()
        mock.readWrite = "before"
        mock.readWrite = "after"
        #expect(mock.readWrite == "after")
    }
}

@Suite("Full coverage — overloads")
struct OverloadCoverageTests {

    @Test("overload by parameter type")
    func byType() {
        let mock = MockOverloads()
        mock.fXIntHandler = { _ in }
        mock.fXStringHandler = { _ in }
        mock.f(1)
        mock.f("a")
        #expect(mock.fXIntCallCount == 1)
        #expect(mock.fXStringCallCount == 1)
        #expect(mock.fXIntLastCall == 1)
        #expect(mock.fXStringLastCall == "a")
    }

    @Test("overload by async-ness")
    func byAsync() async {
        let mock = MockOverloads()
        mock.gHandler = { }
        mock.gAsyncHandler = { }
        // In an async context `g()` resolves to the async overload, so reach the
        // sync one from a sync scope. Each still has its own handler and counter.
        func callSync() { mock.g() }
        callSync()
        await mock.g()
        #expect(mock.gCallCount == 1)
        #expect(mock.gAsyncCallCount == 1)
    }

    @Test("overload by arity")
    func byArity() {
        let mock = MockOverloads()
        mock.hAHandler = { _ in }
        mock.hABHandler = { _, _ in }
        mock.h(a: 1)
        mock.h(a: 1, b: 2)
        #expect(mock.hACallCount == 1)
        #expect(mock.hABCallCount == 1)
        #expect(mock.hABLastCall?.b == 2)
    }
}
