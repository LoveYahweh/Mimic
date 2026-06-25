import MimicMacros
import SwiftSyntaxMacrosTestSupport
import XCTest

final class MacroExpansionTests: XCTestCase {
    private let macros = ["Mockable": MockableMacro.self]

    func testExpandsSimpleProtocol() {
        assertMacroExpansion(
            """
            @Mockable
            protocol Greeter {
                func greet(name: String) -> String
            }
            """,
            expandedSource: """
            protocol Greeter {
                func greet(name: String) -> String
            }

            final class MockGreeter: Greeter {
                init() {
                }

                var greetHandler: ((String) -> String)?
                private(set) var greetCallCount = 0
                private(set) var greetCalls: [String] = []
                var greetWasCalled: Bool {
                    greetCallCount > 0
                }
                var greetLastCall: Optional<String> {
                    greetCalls.last
                }
                private var _greetReturnValue: Optional<String> = nil
                var greetReturnValue: String {
                    get {
                        guard let _greetReturnValue else {
                            fatalError("MockGreeter.greet needs `greetReturnValue` or `greetHandler` to be set.")
                        }
                        return _greetReturnValue
                    }
                    set {
                        _greetReturnValue = newValue
                        greetHandler = { _ in
                            newValue
                        }
                    }
                }

                func greetReturns(_ values: String...) {
                    var queue = values
                    greetHandler = { _ in
                        queue.count > 1 ? queue.removeFirst() : queue[0]
                    }
                }
                func greet(name: String) -> String {
                    greetCallCount += 1
                    greetCalls.append(name)
                    guard let greetHandler else {
                        fatalError("MockGreeter.greet needs `greetReturnValue` or `greetHandler` to be set.")
                    }
                    return greetHandler(name)
                }

                func mimicReset() {
                    greetHandler = nil
                    greetCallCount = 0
                    greetCalls = []
                    _greetReturnValue = nil
                }
            }
            """,
            macros: macros
        )
    }

    func testMirrorsPublicAccess() {
        assertMacroExpansion(
            """
            @Mockable
            public protocol Flag {
                var isOn: Bool { get }
            }
            """,
            expandedSource: """
            public protocol Flag {
                var isOn: Bool { get }
            }

            public final class MockFlag: Flag {
                public init() {
                }

                private var _isOn: Optional<Bool> = nil
                public var isOn: Bool {
                    get {
                        guard let _isOn else {
                            fatalError("MockFlag.isOn was read before it was set.")
                        }
                        return _isOn
                    }
                    set {
                        _isOn = newValue
                    }
                }

                public func mimicReset() {
                    _isOn = nil
                }
            }
            """,
            macros: macros
        )
    }

    func testErasesGenericMethod() {
        assertMacroExpansion(
            """
            @Mockable
            protocol Box {
                func unwrap<T>(_ raw: String) -> T
            }
            """,
            expandedSource: """
            protocol Box {
                func unwrap<T>(_ raw: String) -> T
            }

            final class MockBox: Box {
                init() {
                }

                var unwrapHandler: ((String) -> Any)?
                private(set) var unwrapCallCount = 0
                private(set) var unwrapCalls: [String] = []
                var unwrapWasCalled: Bool {
                    unwrapCallCount > 0
                }
                var unwrapLastCall: Optional<String> {
                    unwrapCalls.last
                }
                func unwrap<T>(_ raw: String) -> T {
                    unwrapCallCount += 1
                    unwrapCalls.append(raw)
                    guard let unwrapHandler else {
                        fatalError("MockBox.unwrap needs `unwrapHandler` to be set.")
                    }
                    return unwrapHandler(raw) as! T
                }

                func mimicReset() {
                    unwrapHandler = nil
                    unwrapCallCount = 0
                    unwrapCalls = []
                }
            }
            """,
            macros: macros
        )
    }

    func testDiagnosesNonProtocol() {
        assertMacroExpansion(
            """
            @Mockable
            struct NotAProtocol {}
            """,
            expandedSource: """
            struct NotAProtocol {}
            """,
            diagnostics: [
                DiagnosticSpec(message: "@Mockable can only be attached to a protocol.", line: 1, column: 1)
            ],
            macros: macros
        )
    }
}
