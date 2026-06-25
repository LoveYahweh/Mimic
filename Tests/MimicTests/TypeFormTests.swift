import Mimic
import Testing

protocol Animal {}
struct Dog: Animal {}

@Mockable
protocol TypeForms {
    func optionals(_ x: Int?) -> String?
    func iuo(_ x: Int!) -> String!
    func collections(_ a: [Int], _ d: [String: Int]) -> Set<String>
    func tuple(_ p: (Int, String)) -> (x: Int, y: String)
    func existential(_ a: any Animal) -> any Animal
    func metatype(_ t: Int.Type) -> String
    func keyPath(_ kp: KeyPath<String, Int>) -> Int
    var iuoProperty: Int! { get set }
    var tupleProperty: (a: Int, b: String) { get }
}

@Suite("Type forms")
struct TypeFormTests {

    @Test("optionals and IUO round-trip; IUO defaults to nil")
    func optionalsAndIUO() {
        let mock = MockTypeForms()
        #expect(mock.optionals(nil) == nil)        // optional return defaults to nil
        #expect(mock.iuo(1) == nil)                // IUO return defaults to nil
        mock.iuoReturnValue = "ok"
        #expect(mock.iuo(2) == "ok")
        #expect(mock.iuoCalls == [1, 2])   // both calls recorded (as Int?)
    }

    @Test("collections default to empty; tuples are recorded")
    func collectionsAndTuples() {
        let mock = MockTypeForms()
        #expect(mock.collections([1], [:]).isEmpty)   // Set return defaults to empty
        mock.tupleReturnValue = (x: 1, y: "a")
        let r = mock.tuple((9, "z"))
        #expect(r.x == 1)
        #expect(mock.tupleCalls.first?.0 == 9)
    }

    @Test("existential and metatype parameters")
    func existentialsAndMetatypes() {
        let mock = MockTypeForms()
        mock.existentialHandler = { $0 }
        let out = mock.existential(Dog())
        #expect(out is Dog)

        mock.metatypeReturnValue = "Int"
        #expect(mock.metatype(Int.self) == "Int")
    }

    @Test("key-path parameter is recorded")
    func keyPaths() {
        let mock = MockTypeForms()
        mock.keyPathReturnValue = 5
        _ = mock.keyPath(\String.count)
        #expect(mock.keyPathCalls.first == \String.count)
    }

    @Test("IUO property and tuple property")
    func properties() {
        let mock = MockTypeForms()
        #expect(mock.iuoProperty == nil)   // IUO property defaults to nil
        mock.iuoProperty = 7
        #expect(mock.iuoProperty == 7)
        mock.tupleProperty = (a: 1, b: "x")
        #expect(mock.tupleProperty.a == 1)
    }
}
