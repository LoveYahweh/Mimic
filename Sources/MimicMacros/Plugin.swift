import SwiftCompilerPlugin
import SwiftSyntaxMacros

@main
struct MimicPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        MockableMacro.self,
    ]
}
