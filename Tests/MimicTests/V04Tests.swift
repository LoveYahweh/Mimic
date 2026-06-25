import Mimic
import Testing

@Mockable
protocol Defaults {
    func maybeName() -> String?
    func names() -> [String]
    func index() -> [String: Int]
    func tags() -> Set<String>
}

@Mockable
protocol Tracker {
    func log(_ message: String)
    func record(event: String, count: Int)
}

@Suite("v0.4 convenience")
struct V04Tests {

    @Test("optional and collection returns default to empty when unstubbed")
    func defaultReturns() {
        let mock = MockDefaults()
        #expect(mock.maybeName() == nil)
        #expect(mock.names() == [])
        #expect(mock.index() == [:])
        #expect(mock.tags() == [])
    }

    @Test("a stub still overrides the default")
    func stubOverridesDefault() {
        let mock = MockDefaults()
        mock.namesReturnValue = ["a", "b"]
        #expect(mock.names() == ["a", "b"])
    }

    @Test("wasCalled flips after the first call")
    func wasCalled() {
        let mock = MockTracker()
        #expect(mock.logWasCalled == false)
        mock.log("hello")
        #expect(mock.logWasCalled)
    }

    @Test("lastCall exposes the most recent arguments")
    func lastCall() {
        let mock = MockTracker()
        mock.log("first")
        mock.log("second")
        #expect(mock.logLastCall == "second")

        mock.record(event: "tap", count: 3)
        #expect(mock.recordLastCall?.event == "tap")
        #expect(mock.recordLastCall?.count == 3)
    }
}
