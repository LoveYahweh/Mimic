import Mimic
import Testing

@Mockable
protocol Decoder {
    func decode<T>(_ raw: String) -> T
    func process<T>(_ item: T)
    func transform<T>(_ x: T) -> T
    func compare<T>(_ a: T, _ b: T) -> Bool where T: Equatable
}

@Mockable
protocol Variadics {
    func sum(_ values: Int...) -> Int
    func firstTruthy(of flags: Bool...) -> Bool?
    func log(_ tag: String, _ parts: String...)
}

@Suite("Generics — type-erased handlers")
struct GenericsTests {

    @Test("generic return is stubbed through the handler and cast back")
    func genericReturn() {
        let mock = MockDecoder()
        mock.decodeHandler = { raw in Int(raw) ?? -1 }
        let value: Int = mock.decode("42")
        #expect(value == 42)
        #expect(mock.decodeCallCount == 1)
    }

    @Test("generic parameter is erased to Any and recorded")
    func genericParameter() {
        let mock = MockDecoder()
        mock.processHandler = { _ in }
        mock.process("hello")
        mock.process(99)
        #expect(mock.processCallCount == 2)
        #expect(mock.processCalls.last as? Int == 99)
    }

    @Test("generic in both positions round-trips via the handler")
    func genericInOut() {
        let mock = MockDecoder()
        mock.transformHandler = { x in x }   // identity over Any
        let result: String = mock.transform("echo")
        #expect(result == "echo")
    }

    @Test("generic with a where clause")
    func genericWhereClause() {
        let mock = MockDecoder()
        mock.compareHandler = { a, b in
            guard let a = a as? Int, let b = b as? Int else { return false }
            return a == b
        }
        #expect(mock.compare(3, 3))
        #expect(mock.compare(3, 4) == false)
    }
}

@Suite("Variadics")
struct VariadicsTests {

    @Test("variadic parameter is captured as an array")
    func variadicArray() {
        let mock = MockVariadics()
        mock.sumHandler = { values in values.reduce(0, +) }
        #expect(mock.sum(1, 2, 3) == 6)
        #expect(mock.sumCalls.last == [1, 2, 3])
    }

    @Test("variadic with an optional return falls back to nil")
    func variadicOptionalReturn() {
        let mock = MockVariadics()
        #expect(mock.firstTruthy(of: true, false) == nil)   // unstubbed → default nil
        mock.firstTruthyHandler = { $0.first { $0 } }
        #expect(mock.firstTruthy(of: false, true) == true)
    }

    @Test("a fixed parameter alongside a variadic")
    func mixedFixedAndVariadic() {
        let mock = MockVariadics()
        mock.logHandler = { _, _ in }
        mock.log("net", "a", "b", "c")
        #expect(mock.logLastCall?.tag == "net")
        #expect(mock.logLastCall?.parts == ["a", "b", "c"])
    }
}
