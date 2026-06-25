import Mimic
import Testing

@Mockable
protocol Callbacks {
    var onTap: () -> Void { get }                 // non-optional function-type property
    var onChange: ((Int) -> Void)? { get set }    // optional function-type property
    func register(_ cb: () -> Void)               // non-escaping closure (forwarded, not recorded)
    func store(_ cb: @escaping () -> Void)        // escaping closure (recorded)
    func lazyValue(_ make: @autoclosure () -> Int) -> Int
    func equals(_ other: Self) -> Bool            // Self parameter
}

@Suite("Closures and function-type properties")
struct ClosureAndPropertyTests {

    @Test("non-optional function-type property round-trips")
    func functionProperty() {
        let mock = MockCallbacks()
        var fired = 0
        mock.onTap = { fired += 1 }
        mock.onTap()
        #expect(fired == 1)
    }

    @Test("optional function-type property defaults to nil")
    func optionalFunctionProperty() {
        let mock = MockCallbacks()
        #expect(mock.onChange == nil)
        var seen = 0
        mock.onChange = { seen = $0 }
        mock.onChange?(5)
        #expect(seen == 5)
    }

    @Test("non-escaping closure is forwarded to the handler")
    func nonEscapingForwarded() {
        let mock = MockCallbacks()
        var ran = false
        mock.registerHandler = { cb in cb() }   // handler invokes the forwarded closure
        mock.register { ran = true }
        #expect(ran)
        #expect(mock.registerCallCount == 1)    // still counted, just not argument-recorded
    }

    @Test("escaping closure is recorded and can be replayed")
    func escapingRecorded() {
        let mock = MockCallbacks()
        var done = false
        mock.store { done = true }
        #expect(mock.storeCallCount == 1)
        mock.storeCalls.first?()   // escaping closures are stored in …Calls
        #expect(done)
    }

    @Test("autoclosure parameter is forwarded")
    func autoclosure() {
        let mock = MockCallbacks()
        mock.lazyValueHandler = { make in make() * 2 }
        #expect(mock.lazyValue(21) == 42)
    }

    @Test("Self parameter is accepted")
    func selfParameter() {
        let mock = MockCallbacks()
        let other = MockCallbacks()
        mock.equalsHandler = { $0 === other }
        #expect(mock.equals(other))
        #expect(mock.equals(MockCallbacks()) == false)
    }
}
