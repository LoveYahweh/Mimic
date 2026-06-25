import Mimic
import Testing

@Mockable
protocol KeywordParams {
    func a(_ `default`: Int) -> Int          // keyword internal name, no label
    func b(`class`: Int, `where`: String)    // keyword labels and names
    func c(in scope: String)                 // keyword label, ordinary name
}

@Mockable
protocol Ownership {
    func take(_ x: borrowing Int) -> Int
    func give(_ x: consuming String)
}

@Mockable
protocol Cloneable {
    func clone() -> Self
}

@Suite("Edge cases — keywords, ownership, Self")
struct EdgeCaseTests {

    @Test("keyword internal name is recorded")
    func keywordName() {
        let mock = MockKeywordParams()
        mock.aReturnValue = 1
        _ = mock.a(7)
        #expect(mock.aCalls == [7])
        #expect(mock.aLastCall == 7)
    }

    @Test("keyword labels and names round-trip")
    func keywordLabels() {
        let mock = MockKeywordParams()
        mock.b(class: 3, where: "scope")
        #expect(mock.bCallCount == 1)
        #expect(mock.bLastCall?.class == 3)
        #expect(mock.bLastCall?.where == "scope")
    }

    @Test("keyword argument label with an ordinary name")
    func keywordLabelOnly() {
        let mock = MockKeywordParams()
        mock.c(in: "outer")
        #expect(mock.cCalls == ["outer"])
    }

    @Test("borrowing and consuming parameters are recorded by value")
    func ownershipParameters() {
        let mock = MockOwnership()
        mock.takeReturnValue = 99
        #expect(mock.take(5) == 99)
        #expect(mock.takeCalls == [5])

        mock.give("payload")
        #expect(mock.giveCalls == ["payload"])
    }

    @Test("Self return type is stubbed and returned")
    func selfReturn() {
        let mock = MockCloneable()
        let other = MockCloneable()
        mock.cloneHandler = { other }
        #expect(mock.clone() === other)
    }
}
