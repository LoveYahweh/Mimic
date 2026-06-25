import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

/// `@Mockable` generates a `Mock<ProtocolName>` test double as a peer of the
/// annotated protocol. The generated mock records every call (count + arguments)
/// and lets a test stub behaviour by assigning a `<member>Handler` closure or,
/// for the simple case, a `<member>ReturnValue`.
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
        let access = accessKeyword(for: proto.modifiers)

        // Disambiguate overloaded methods up front so handler/recording names
        // never collide, regardless of source order.
        let functions = proto.memberBlock.members.compactMap {
            $0.decl.as(FunctionDeclSyntax.self)
        }
        let prefixes = disambiguatedPrefixes(for: functions)

        var members: [GeneratedMember] = []
        var functionIndex = 0
        for item in proto.memberBlock.members {
            if let function = item.decl.as(FunctionDeclSyntax.self) {
                members.append(functionMembers(
                    function,
                    memberPrefix: prefixes[functionIndex],
                    mockName: mockName,
                    access: access
                ))
                functionIndex += 1
            } else if let variable = item.decl.as(VariableDeclSyntax.self),
                      let member = propertyMembers(variable, mockName: mockName, access: access) {
                members.append(member)
            }
        }

        // `mimicReset()` returns the mock to a fresh state. It's deliberately
        // namespaced so it can't clash with a protocol requirement named `reset`.
        let resetLines = members.flatMap(\.resetLines)
        if !resetLines.isEmpty {
            let body = resetLines.map { "    \($0)" }.joined(separator: "\n")
            members.append(GeneratedMember(decls: """
            \(access)func mimicReset() {
            \(body)
            }
            """))
        }

        let body = members.map(\.decls)
            .joined(separator: "\n\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.isEmpty ? "" : "    \($0)" }
            .joined(separator: "\n")

        let mock: DeclSyntax = """
        \(raw: access)final class \(raw: mockName): \(raw: protocolName) {
            \(raw: access)init() {}

        \(raw: body)
        }
        """
        return [mock]
    }
}

/// The source produced for one protocol requirement, plus the statements that
/// return it to a pristine state inside `mimicReset()`.
private struct GeneratedMember {
    var decls: String
    var resetLines: [String] = []
}

// MARK: - Function members

private struct Param {
    let label: String?   // external argument label; nil == `_`
    let name: String     // internal parameter name
    let type: String     // type as written, for the method signature
    let bareType: String // type without parameter attributes, for stored closures
}

private func functionMembers(
    _ function: FunctionDeclSyntax,
    memberPrefix: String,
    mockName: String,
    access: String
) -> GeneratedMember {
    let name = function.name.text
    let signature = function.signature
    let isStatic = function.modifiers.contains { $0.name.text == "static" }
    let returnType = signature.returnClause?.type.trimmedDescription

    // Effects are copied verbatim so typed throws (`throws(MyError)`) survives.
    let isAsync = signature.effectSpecifiers?.asyncSpecifier != nil
    let throwsClause = signature.effectSpecifiers?.throwsClause
    let isThrows = throwsClause != nil
    let effects = "\(isAsync ? " async" : "")\(throwsClause.map { " \($0.trimmedDescription)" } ?? "")"

    let params: [Param] = signature.parameterClause.parameters.map { p in
        let first = p.firstName.text
        let second = p.secondName?.text
        return Param(
            label: first == "_" ? nil : first,
            name: second ?? first,
            type: p.type.trimmedDescription,
            bareType: strippedType(p.type)
        )
    }

    // Member modifier prefixes. `static` requirements need static storage marked
    // `nonisolated(unsafe)` (mutable static state is otherwise rejected under the
    // Swift 6 language mode). The counters expose a public getter but stay
    // privately settable. Methods don't store state, so they skip the escape hatch.
    let staticKw = isStatic ? "static " : ""
    let storedStatic = isStatic ? "nonisolated(unsafe) static " : ""
    let member = "\(access)\(storedStatic)"
    let counter = "\(access)private(set) \(storedStatic)"
    let methodPrefix = "\(access)\(staticKw)"

    // Closure / handler type, e.g. `((Int, String) async throws -> Bool)?`.
    // Parameter attributes like `@escaping` are stripped — they're illegal inside
    // a stored function type, but completion-handler params still work.
    let closureParams = params.map(\.bareType).joined(separator: ", ")
    let handlerType = "((\(closureParams))\(effects) -> \(returnType ?? "Void"))?"

    // Call-recording storage.
    var storage = """
    \(member)var \(memberPrefix)Handler: \(handlerType)
    \(counter)var \(memberPrefix)CallCount = 0
    """
    var resetLines = ["\(memberPrefix)Handler = nil", "\(memberPrefix)CallCount = 0"]

    let recordLine: String
    switch params.count {
    case 0:
        recordLine = ""
    case 1:
        storage += "\n\(counter)var \(memberPrefix)Calls: [\(params[0].bareType)] = []"
        recordLine = "    \(memberPrefix)Calls.append(\(params[0].name))"
        resetLines.append("\(memberPrefix)Calls = []")
    default:
        let tupleType = params.map { "\($0.name): \($0.bareType)" }.joined(separator: ", ")
        let tupleValue = params.map { "\($0.name): \($0.name)" }.joined(separator: ", ")
        storage += "\n\(counter)var \(memberPrefix)Calls: [(\(tupleType))] = []"
        recordLine = "    \(memberPrefix)Calls.append((\(tupleValue)))"
        resetLines.append("\(memberPrefix)Calls = []")
    }

    // `…ReturnValue` shorthand: assigning it stubs a handler that ignores the
    // arguments and returns the value, so trivial stubs need no closure.
    if let returnType, returnType != "Void" {
        let ignored = params.isEmpty ? "" : params.map { _ in "_" }.joined(separator: ", ") + " in "
        storage += """

        private \(storedStatic)var _\(memberPrefix)ReturnValue: \(returnType)?
        \(access)\(staticKw)var \(memberPrefix)ReturnValue: \(returnType) {
            get {
                guard let _\(memberPrefix)ReturnValue else {
                    fatalError("\(mockName).\(name) needs `\(memberPrefix)ReturnValue` or `\(memberPrefix)Handler` to be set.")
                }
                return _\(memberPrefix)ReturnValue
            }
            set {
                _\(memberPrefix)ReturnValue = newValue
                \(memberPrefix)Handler = { \(ignored)newValue }
            }
        }
        """
        resetLines.append("_\(memberPrefix)ReturnValue = nil")
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
    let callPrefix = "\(isThrows ? "try " : "")\(isAsync ? "await " : "")"

    let invocation: String
    if let returnType, returnType != "Void" {
        invocation = """
            guard let \(memberPrefix)Handler else {
                fatalError("\(mockName).\(name) needs `\(memberPrefix)ReturnValue` or `\(memberPrefix)Handler` to be set.")
            }
            return \(callPrefix)\(memberPrefix)Handler(\(callArgs))
        """
    } else {
        invocation = "    \(callPrefix)\(memberPrefix)Handler?(\(callArgs))"
    }

    let bodyLines = ["    \(memberPrefix)CallCount += 1", recordLine, invocation]
        .filter { !$0.isEmpty }
        .joined(separator: "\n")

    let decls = """
    \(storage)
    \(methodPrefix)func \(name)(\(paramText))\(effects)\(returnClause) {
    \(bodyLines)
    }
    """
    return GeneratedMember(decls: decls, resetLines: isStatic ? [] : resetLines)
}

// MARK: - Property members

private func propertyMembers(
    _ variable: VariableDeclSyntax,
    mockName: String,
    access: String
) -> GeneratedMember? {
    guard let binding = variable.bindings.first,
          let pattern = binding.pattern.as(IdentifierPatternSyntax.self),
          let type = binding.typeAnnotation?.type
    else { return nil }

    let name = pattern.identifier.text
    let typeText = type.trimmedDescription
    let isStatic = variable.modifiers.contains { $0.name.text == "static" }
    let storedStatic = isStatic ? "nonisolated(unsafe) static " : ""
    let staticKw = isStatic ? "static " : ""

    // An optional requirement is satisfied by a plain stored property (defaulting
    // to nil), which is also settable from the test.
    if type.is(OptionalTypeSyntax.self) {
        return GeneratedMember(
            decls: "\(access)\(storedStatic)var \(name): \(typeText)",
            resetLines: isStatic ? [] : ["\(name) = nil"]
        )
    }

    // A non-optional requirement needs a value the mock can't synthesise, so back
    // it with an optional and expose the exact type via a computed accessor.
    // Providing a setter also lets a test assign get-only requirements directly.
    let decls = """
    private \(storedStatic)var _\(name): \(typeText)?
    \(access)\(staticKw)var \(name): \(typeText) {
        get {
            guard let _\(name) else {
                fatalError("\(mockName).\(name) was read before it was set.")
            }
            return _\(name)
        }
        set { _\(name) = newValue }
    }
    """
    return GeneratedMember(decls: decls, resetLines: isStatic ? [] : ["_\(name) = nil"])
}

// MARK: - Types

/// Drops parameter attributes (`@escaping`, `@autoclosure`) while keeping
/// specifiers (`inout`), so the type is valid inside a stored closure.
private func strippedType(_ type: TypeSyntax) -> String {
    guard let attributed = type.as(AttributedTypeSyntax.self) else {
        return type.trimmedDescription
    }
    let specifiers = attributed.specifiers.trimmedDescription
    let base = attributed.baseType.trimmedDescription
    return specifiers.isEmpty ? base : "\(specifiers) \(base)"
}

// MARK: - Access level

private func accessKeyword(for modifiers: DeclModifierListSyntax) -> String {
    for modifier in modifiers {
        switch modifier.name.text {
        case "public", "open": return "public "
        case "package": return "package "
        default: continue
        }
    }
    return ""
}

// MARK: - Overload disambiguation

/// Returns a stable, unique member-name prefix for each function. A method whose
/// base name is unique keeps that name; overloaded methods are disambiguated by
/// argument labels, then by parameter types, with a numeric fallback that
/// guarantees uniqueness even for `async`/`throws`-only overloads.
private func disambiguatedPrefixes(for functions: [FunctionDeclSyntax]) -> [String] {
    var groups: [String: [Int]] = [:]
    for (index, function) in functions.enumerated() {
        groups[function.name.text, default: []].append(index)
    }

    var result = [String](repeating: "", count: functions.count)
    for (base, indices) in groups {
        guard indices.count > 1 else {
            result[indices[0]] = base
            continue
        }
        let byLabel = indices.map { base + labelSuffix(functions[$0]) }
        if Set(byLabel).count == byLabel.count {
            for (offset, index) in indices.enumerated() { result[index] = byLabel[offset] }
        } else {
            for index in indices { result[index] = base + typeSuffix(functions[index]) }
        }
    }

    // Final safety net: force any remaining collisions apart with a numeric tail.
    var occurrences: [String: Int] = [:]
    for prefix in result { occurrences[prefix, default: 0] += 1 }
    var running: [String: Int] = [:]
    for index in result.indices where occurrences[result[index]]! > 1 {
        let n = (running[result[index]] ?? 0) + 1
        running[result[index]] = n
        result[index] += "\(n)"
    }
    return result
}

private func labelSuffix(_ function: FunctionDeclSyntax) -> String {
    function.signature.parameterClause.parameters.map { p in
        let first = p.firstName.text
        let token = first != "_" ? first : (p.secondName?.text ?? first)
        return token.capitalizedFirstLetter
    }.joined()
}

private func typeSuffix(_ function: FunctionDeclSyntax) -> String {
    let labels = labelSuffix(function)
    let types = function.signature.parameterClause.parameters.map { p in
        p.type.trimmedDescription.alphanumericsOnly.capitalizedFirstLetter
    }.joined()
    let effects = function.signature.effectSpecifiers
    let async = effects?.asyncSpecifier != nil ? "Async" : ""
    let throwing = effects?.throwsClause != nil ? "Throws" : ""
    return labels + types + async + throwing
}

private extension String {
    var capitalizedFirstLetter: String {
        guard let first else { return self }
        return first.uppercased() + dropFirst()
    }

    var alphanumericsOnly: String {
        filter { $0.isLetter || $0.isNumber }
    }
}

// MARK: - Diagnostics

enum MimicError: Error, CustomStringConvertible {
    case notAProtocol

    var description: String {
        switch self {
        case .notAProtocol:
            return "@Mockable can only be attached to a protocol."
        }
    }
}
