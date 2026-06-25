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
                func greet(name: String) -> String {
                    greetCallCount += 1
                    greetCalls.append(name)
                    guard let greetHandler else {
                        fatalError("MockGreeter.greet was called before its `greetHandler` was set.")
                    }
                    return greetHandler(name)
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

                private var _isOn: Bool?
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
