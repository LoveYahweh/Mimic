import Mimic
import Testing

@Mockable
protocol ReadGrid {
    subscript(index: Int) -> String { get }
}

@Mockable
protocol MutableGrid {
    subscript(key: String) -> Int { get set }
}

@Mockable
protocol Grid2D {
    subscript(row: Int, col: Int) -> Double { get set }
}

@Mockable
protocol OptionalGrid {
    subscript(id: Int) -> String? { get }
}

@Mockable
protocol OverloadedGrid {
    subscript(i: Int) -> String { get }
    subscript(s: String) -> Int { get }
}

@Suite("Subscripts")
struct SubscriptTests {

    @Test("read-only subscript stubs the getter and records the index")
    func readOnly() {
        let mock = MockReadGrid()
        mock.subscriptGetHandler = { index in "item-\(index)" }
        #expect(mock[3] == "item-3")
        #expect(mock.subscriptGetCallCount == 1)
        #expect(mock.subscriptGetCalls == [3])
        #expect(mock.subscriptGetWasCalled)
    }

    @Test("read-write subscript records gets and sets independently")
    func readWrite() {
        let mock = MockMutableGrid()
        mock.subscriptGetHandler = { _ in 0 }
        _ = mock["a"]
        mock["b"] = 9

        #expect(mock.subscriptGetCalls == ["a"])
        #expect(mock.subscriptSetCallCount == 1)
        #expect(mock.subscriptSetCalls.first?.key == "b")
        #expect(mock.subscriptSetCalls.first?.newValue == 9)
    }

    @Test("multi-parameter subscript records a labelled tuple")
    func multiParam() {
        let mock = MockGrid2D()
        mock.subscriptSetHandler = { _, _, _ in }
        mock[1, 2] = 3.5
        let call = mock.subscriptSetCalls.first
        #expect(call?.row == 1)
        #expect(call?.col == 2)
        #expect(call?.newValue == 3.5)
    }

    @Test("optional-returning subscript defaults to nil when unstubbed")
    func optionalDefault() {
        let mock = MockOptionalGrid()
        #expect(mock[1] == nil)
    }

    @Test("overloaded subscripts disambiguate by parameter type")
    func overloaded() {
        let mock = MockOverloadedGrid()
        mock.subscriptIntGetHandler = { _ in "by-int" }
        mock.subscriptStringGetHandler = { _ in 42 }
        #expect(mock[7] == "by-int")
        #expect(mock["k"] == 42)
        #expect(mock.subscriptIntGetCalls == [7])
        #expect(mock.subscriptStringGetCalls == ["k"])
    }
}
