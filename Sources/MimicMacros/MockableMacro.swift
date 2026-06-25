import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

/// `@Mockable` generates a `Mock<ProtocolName>` test double as a peer of the
/// annotated protocol. The generated mock records every call (count + arguments)
/// and lets a test stub behaviour by assigning a `<member>Handler` closure.
public struct MockableMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let proto = declaration.as(ProtocolDeclSyntax.self) else {
            throw MimicError.notAProtocol
        }

        let protocolName = proto.name.text
        let mockName = "Mock\(protocolName)"

        var members: [String] = []
        var seenNames: Set<String> = []

        for item in proto.memberBlock.members {
            if let function = item.decl.as(FunctionDeclSyntax.self) {
                let base = function.name.text
                if !seenNames.insert(base).inserted {
                    throw MimicError.overloadedMember(base)
                }
                members.append(try functionMembers(function, mockName: mockName))
            } else if let variable = item.decl.as(VariableDeclSyntax.self) {
                members.append(contentsOf: propertyMembers(variable, mockName: mockName))
            }
        }

        let body = members
            .joined(separator: "\n\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.isEmpty ? "" : "    \($0)" }
            .joined(separator: "\n")

        let mock: DeclSyntax = """
        final class \(raw: mockName): \(raw: protocolName) {
            init() {}

        \(raw: body)
        }
        """
        return [mock]
    }
}

// MARK: - Function members

private struct Param {
    let label: String?   // external argument label; nil == `_`
    let name: String     // internal parameter name
    let type: String
}

private func functionMembers(_ function: FunctionDeclSyntax, mockName: String) throws -> String {
    let name = function.name.text
    let signature = function.signature
    let isAsync = signature.effectSpecifiers?.asyncSpecifier != nil
    let isThrows = signature.effectSpecifiers?.throwsClause != nil
    let returnType = signature.returnClause?.type.trimmedDescription

    let params: [Param] = signature.parameterClause.parameters.map { p in
        let first = p.firstName.text
        let second = p.secondName?.text
        return Param(
            label: first == "_" ? nil : first,
            name: second ?? first,
            type: p.type.trimmedDescription
        )
    }

    // Closure / handler type, e.g. `((Int, String) async throws -> Bool)?`
    let effects = "\(isAsync ? " async" : "")\(isThrows ? " throws" : "")"
    let closureParams = params.map(\.type).joined(separator: ", ")
    let handlerType = "((\(closureParams))\(effects) -> \(returnType ?? "Void"))?"

    // Call-recording storage.
    var storage = """
    var \(name)Handler: \(handlerType)
    private(set) var \(name)CallCount = 0
    """
    let recordLine: String
    switch params.count {
    case 0:
        recordLine = ""
    case 1:
        storage += "\nprivate(set) var \(name)Calls: [\(params[0].type)] = []"
        recordLine = "    \(name)Calls.append(\(params[0].name))"
    default:
        let tupleType = params.map { "\($0.name): \($0.type)" }.joined(separator: ", ")
        let tupleValue = params.map { "\($0.name): \($0.name)" }.joined(separator: ", ")
        storage += "\nprivate(set) var \(name)Calls: [(\(tupleType))] = []"
        recordLine = "    \(name)Calls.append((\(tupleValue)))"
    }

    // Reconstruct the declaration so the mock conforms to the protocol exactly.
    let paramText = params.map { p -> String in
        let head: String
        switch p.label {
        case nil: head = "_ \(p.name)"
        case p.name?: head = p.name
        case let label?: head = "\(label) \(p.name)"
        }
        return "\(head): \(p.type)"
    }.joined(separator: ", ")
    let returnClause = returnType.map { " -> \($0)" } ?? ""

    let callArgs = params.map(\.name).joined(separator: ", ")
    let prefix = "\(isThrows ? "try " : "")\(isAsync ? "await " : "")"

    let invocation: String
    if let returnType, returnType != "Void" {
        invocation = """
            guard let \(name)Handler else {
                fatalError("\(mockName).\(name) was called before its `\(name)Handler` was set.")
            }
            return \(prefix)\(name)Handler(\(callArgs))
        """
    } else {
        invocation = "    \(prefix)\(name)Handler?(\(callArgs))"
    }

    let bodyLines = ["    \(name)CallCount += 1", recordLine, invocation]
        .filter { !$0.isEmpty }
        .joined(separator: "\n")

    return """
    \(storage)
    func \(name)(\(paramText))\(effects)\(returnClause) {
    \(bodyLines)
    }
    """
}

// MARK: - Property members

private func propertyMembers(_ variable: VariableDeclSyntax, mockName: String) -> [String] {
    guard let binding = variable.bindings.first,
          let pattern = binding.pattern.as(IdentifierPatternSyntax.self),
          let type = binding.typeAnnotation?.type
    else { return [] }

    let name = pattern.identifier.text
    let typeText = type.trimmedDescription

    // An optional requirement is satisfied by a plain stored property (defaulting
    // to nil), which is also settable from the test.
    if type.is(OptionalTypeSyntax.self) {
        return ["var \(name): \(typeText)"]
    }

    // A non-optional requirement needs a value the mock can't synthesise, so back
    // it with an optional and expose the exact type via a computed accessor.
    // Providing a setter also lets a test assign get-only requirements directly.
    return ["""
    private var _\(name): \(typeText)?
    var \(name): \(typeText) {
        get {
            guard let _\(name) else {
                fatalError("\(mockName).\(name) was read before it was set.")
            }
            return _\(name)
        }
        set { _\(name) = newValue }
    }
    """]
}

// MARK: - Diagnostics

enum MimicError: Error, CustomStringConvertible {
    case notAProtocol
    case overloadedMember(String)

    var description: String {
        switch self {
        case .notAProtocol:
            return "@Mockable can only be attached to a protocol."
        case .overloadedMember(let name):
            return "@Mockable does not yet support overloaded members ('\(name)' appears more than once)."
        }
    }
}
