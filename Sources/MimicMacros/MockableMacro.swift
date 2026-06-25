import SwiftDiagnostics
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
        // Propagate a global actor (`@MainActor`, custom `@…Actor`) onto the mock so
        // its isolation matches the protocol's; otherwise actor-isolated async
        // requirements fail the Swift 6 `sending` check.
        let globalActor = proto.attributes
            .compactMap { $0.as(AttributeSyntax.self) }
            .filter { $0.attributeName.trimmedDescription.hasSuffix("Actor") }
            .map { "\($0.trimmedDescription) " }
            .joined()

        // Disambiguate overloaded methods up front so handler/recording names
        // never collide, regardless of source order.
        // Operator requirements (`static func ==`) can't map to an identifier-based
        // handler name; they're diagnosed and skipped rather than miscompiled.
        let functions = proto.memberBlock.members
            .compactMap { $0.decl.as(FunctionDeclSyntax.self) }
            .filter { !isOperatorName($0.name.text) }
        let prefixes = disambiguatedPrefixes(for: functions)
        let subscripts = proto.memberBlock.members.compactMap {
            $0.decl.as(SubscriptDeclSyntax.self)
        }
        let subscriptPrefixes = subscriptDisambiguatedPrefixes(for: subscripts)

        var members: [GeneratedMember] = []
        var functionIndex = 0
        var subscriptIndex = 0
        for item in proto.memberBlock.members {
            if let function = item.decl.as(FunctionDeclSyntax.self) {
                if isOperatorName(function.name.text) {
                    context.diagnose(Diagnostic(
                        node: function,
                        message: MimicDiagnostic(
                            "@Mockable doesn't generate operator requirements, so \(mockName) won't conform until you add one by hand."
                        )
                    ))
                } else {
                    members.append(functionMembers(
                        function,
                        memberPrefix: prefixes[functionIndex],
                        mockName: mockName,
                        access: access,
                        globalActor: globalActor
                    ))
                    functionIndex += 1
                }
            } else if let variable = item.decl.as(VariableDeclSyntax.self),
                      let member = propertyMembers(variable, mockName: mockName, access: access, globalActor: globalActor) {
                members.append(member)
            } else if let subscriptDecl = item.decl.as(SubscriptDeclSyntax.self) {
                members.append(subscriptMembers(
                    subscriptDecl,
                    memberPrefix: subscriptPrefixes[subscriptIndex],
                    mockName: mockName,
                    access: access,
                    globalActor: globalActor
                ))
                subscriptIndex += 1
            } else if let unsupported = unsupportedMemberDescription(item.decl) {
                // Warn clearly rather than leave a confusing "does not conform" error.
                context.diagnose(Diagnostic(
                    node: item.decl,
                    message: MimicDiagnostic(
                        "@Mockable doesn't generate \(unsupported) yet, so \(mockName) won't conform until you add one by hand."
                    )
                ))
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

        // Omit the body block entirely for a member-less protocol so the mock
        // doesn't carry trailing blank lines.
        let bodyBlock = body.isEmpty ? "" : "\n\n\(body)"
        let mock: DeclSyntax = """
        \(raw: globalActor)\(raw: access)final class \(raw: mockName): \(raw: protocolName) {
            \(raw: access)init() {}\(raw: bodyBlock)
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
    let label: String?      // external argument label; nil == `_`
    let name: String        // raw internal parameter name
    let escapedName: String // `name`, backtick-escaped if it's a keyword
    let type: String        // type as written, for the method signature
    let bareType: String    // attributes stripped, keeps `inout`; for the closure type
    let recordType: String  // also drops `inout`/ownership; for the `…Calls` element
    let isInout: Bool
    let recordable: Bool    // false for non-escaping closures — storing one would escape it

    /// How the argument is forwarded to the handler (`inout` needs `&`).
    var callArgument: String { isInout ? "&\(escapedName)" : escapedName }
}

/// Parses a parameter clause (shared by methods and subscripts) into the data
/// needed for the handler type, recording, signature, and call forwarding.
private func parsedParameters(
    _ parameters: FunctionParameterListSyntax,
    genericNames: Set<String>,
    mockName: String
) -> [Param] {
    parameters.map { p in
        let first = unescapedIdentifier(p.firstName.text)
        let second = p.secondName.map { unescapedIdentifier($0.text) }
        let isVariadic = p.ellipsis != nil

        // `inout` is legal inside a function type (and needs `&` at the call site);
        // other ownership specifiers (`borrowing`/`consuming`) are illegal there and
        // a plain witness still conforms, so they're dropped everywhere.
        let (attributes, specifiers, rawBase) = splitType(p.type)
        let isInout = specifiers.contains("inout")
        let isGeneric = referencesGeneric(rawBase, genericNames)
        // Storage normalizes an IUO to a plain optional (`!` is illegal in a stored
        // closure/array), but the signature keeps the original `!` — an IUO
        // requirement is only satisfied by an IUO witness.
        let storedBase = isGeneric ? "Any" : substitutingSelf(normalizeIUO(rawBase), with: mockName)

        // The type as written in the conforming declaration keeps attributes and
        // `inout` (so `@escaping` params still conform) but not `...`, appended below.
        // `Self` is substituted because a class can't take covariant `Self` as a
        // parameter (the mock is `final`, so the concrete type is equivalent).
        let sigBase = substitutingSelf(rawBase, with: mockName)
        let signatureCore = isInout ? "inout \(sigBase)" : sigBase
        let attributed = attributes.isEmpty ? signatureCore : "\(attributes) \(signatureCore)"
        let signatureType = isVariadic ? "\(sigBase)..." : attributed
        // The stored-closure parameter type: a variadic becomes an array, `inout`
        // is kept, attributes and other ownership specifiers are dropped.
        let closureType: String
        if isVariadic { closureType = "[\(storedBase)]" }
        else if isInout { closureType = "inout \(storedBase)" }
        else { closureType = storedBase }
        // The recorded element type is the same but never `inout`.
        let recordType = isVariadic ? "[\(storedBase)]" : storedBase

        // A non-escaping closure (incl. `@autoclosure`) can't be recorded — storing
        // it in the `…Calls` array would let it escape — but it's still forwarded.
        let coreType = (p.type.as(AttributedTypeSyntax.self)?.baseType) ?? p.type
        let attributeTokens = attributes.split(separator: " ").map(String.init)
        let isAutoclosure = attributeTokens.contains("@autoclosure")
        let isEscaping = attributeTokens.contains("@escaping")
        let isFunctionType = coreType.is(FunctionTypeSyntax.self)
        let isOptional = p.type.is(OptionalTypeSyntax.self)
        let recordable = !(isAutoclosure || (isFunctionType && !isEscaping && !isOptional))

        let internalName = second ?? first
        return Param(
            label: first == "_" ? nil : first,
            name: internalName,
            escapedName: escapedIdentifier(internalName),
            type: signatureType,
            bareType: closureType,
            recordType: recordType,
            isInout: isInout,
            recordable: recordable
        )
    }
}

private func functionMembers(
    _ function: FunctionDeclSyntax,
    memberPrefix: String,
    mockName: String,
    access: String,
    globalActor: String
) -> GeneratedMember {
    let name = function.name.text
    let signature = function.signature
    let isStatic = function.modifiers.contains { $0.name.text == "static" }
    let returnTypeSyntax = signature.returnClause?.type
    let returnType = returnTypeSyntax?.trimmedDescription          // signature (keeps IUO)
    let storedReturn = returnType.map(normalizeIUO)                // storage (IUO → optional)

    // Generic methods can't be stored as concrete closures, so any type that
    // mentions a generic parameter is erased to `Any` in storage and force-cast
    // back inside the method body. The method signature keeps its generics intact.
    let genericNames = Set(function.genericParameterClause?.parameters.map { $0.name.text } ?? [])
    let genericClause = function.genericParameterClause?.trimmedDescription ?? ""
    let whereClause = function.genericWhereClause.map { " \($0.trimmedDescription)" } ?? ""
    let returnIsGeneric = returnType.map { referencesGeneric($0, genericNames) } ?? false
    // `Self` can't be a stored-property type; substitute the concrete mock name
    // (the mock is `final`, so `Self == MockX`). Returns/ReturnValue are skipped.
    let returnHasSelf = returnType.map { referencesGeneric($0, ["Self"]) } ?? false
    let handlerReturn = returnIsGeneric
        ? "Any"
        : substitutingSelf(storedReturn ?? "Void", with: mockName)

    // Effects are copied verbatim so typed throws (`throws(MyError)`) survives.
    let isAsync = signature.effectSpecifiers?.asyncSpecifier != nil
    let throwsClause = signature.effectSpecifiers?.throwsClause
    let isThrows = throwsClause != nil
    let effects = "\(isAsync ? " async" : "")\(throwsClause.map { " \($0.trimmedDescription)" } ?? "")"

    let params = parsedParameters(signature.parameterClause.parameters, genericNames: genericNames, mockName: mockName)
    let recordableParams = params.filter(\.recordable)

    // A `nonisolated` requirement on an actor-isolated protocol needs a
    // nonisolated witness, so its storage opts out of the actor and the method
    // (and handler closure) carry no isolation.
    let isNonisolated = function.modifiers.contains { $0.name.text == "nonisolated" }
    let memberActor = isNonisolated ? "" : globalActor

    // Member modifier prefixes. Mutable storage that is `static`, or nonisolated on
    // an actor-isolated mock, must be marked `nonisolated(unsafe)` to compile under
    // the Swift 6 language mode. The counters expose a public getter but stay
    // privately settable. Methods don't store state, so they skip the escape hatch.
    let staticKw = isStatic ? "static " : ""
    let needsUnsafe = isStatic || (isNonisolated && !globalActor.isEmpty)
    let storedStatic = "\(needsUnsafe ? "nonisolated(unsafe) " : "")\(staticKw)"
    let member = "\(access)\(storedStatic)"
    let counter = "\(access)private(set) \(storedStatic)"
    let methodPrefix = "\(access)\(isNonisolated ? "nonisolated " : "")\(staticKw)"

    // Closure / handler type, e.g. `((Int, String) async throws -> Bool)?`.
    // Parameter attributes like `@escaping` are stripped — they're illegal inside
    // a stored function type, but completion-handler params still work.
    // When the protocol is actor-isolated, the handler closure carries the same
    // isolation so on-actor arguments aren't "sent" to a nonisolated callee.
    let closureParams = params.map(\.bareType).joined(separator: ", ")
    let handlerType = "(\(memberActor)(\(closureParams))\(effects) -> \(handlerReturn))?"

    // Call-recording storage.
    var storage = """
    \(member)var \(memberPrefix)Handler: \(handlerType)
    \(counter)var \(memberPrefix)CallCount = 0
    """
    var resetLines = ["\(memberPrefix)Handler = nil", "\(memberPrefix)CallCount = 0"]

    let recordLine: String
    switch recordableParams.count {
    case 0:
        recordLine = ""
    case 1:
        storage += "\n\(counter)var \(memberPrefix)Calls: [\(recordableParams[0].recordType)] = []"
        recordLine = "    \(memberPrefix)Calls.append(\(recordableParams[0].escapedName))"
        resetLines.append("\(memberPrefix)Calls = []")
    default:
        // Tuple element labels accept keywords unescaped; only the value references do.
        let tupleType = recordableParams.map { "\($0.name): \($0.recordType)" }.joined(separator: ", ")
        let tupleValue = recordableParams.map { "\($0.name): \($0.escapedName)" }.joined(separator: ", ")
        storage += "\n\(counter)var \(memberPrefix)Calls: [(\(tupleType))] = []"
        recordLine = "    \(memberPrefix)Calls.append((\(tupleValue)))"
        resetLines.append("\(memberPrefix)Calls = []")
    }

    // Convenience accessors over the recorded state.
    storage += "\n\(access)\(staticKw)var \(memberPrefix)WasCalled: Bool { \(memberPrefix)CallCount > 0 }"
    if !recordableParams.isEmpty {
        let element = recordableParams.count == 1
            ? recordableParams[0].recordType
            : "(\(recordableParams.map { "\($0.name): \($0.recordType)" }.joined(separator: ", ")))"
        // `Optional<…>` rather than `…?` so a function-typed element (e.g. a
        // completion closure) doesn't bind the `?` onto its return type.
        storage += "\n\(access)\(staticKw)var \(memberPrefix)LastCall: Optional<\(element)> { \(memberPrefix)Calls.last }"
    }

    // A closure head that ignores every argument, e.g. `_, _ in ` (or empty).
    let closureHead = params.isEmpty ? "" : params.map { _ in "_" }.joined(separator: ", ") + " in "

    // `…ReturnValue` shorthand: assigning it stubs a handler that ignores the
    // arguments and returns the value, so trivial stubs need no closure. Skipped
    // for generic or `Self` returns, which have no single concrete type to store.
    if let returnType, let storedReturn, returnType != "Void", !returnIsGeneric, !returnHasSelf {
        storage += """

        private \(storedStatic)var _\(memberPrefix)ReturnValue: Optional<\(storedReturn)> = nil
        \(access)\(staticKw)var \(memberPrefix)ReturnValue: \(storedReturn) {
            get {
                guard let _\(memberPrefix)ReturnValue else {
                    fatalError("\(mockName).\(name) needs `\(memberPrefix)ReturnValue` or `\(memberPrefix)Handler` to be set.")
                }
                return _\(memberPrefix)ReturnValue
            }
            set {
                _\(memberPrefix)ReturnValue = newValue
                \(memberPrefix)Handler = { \(closureHead)newValue }
            }
        }

        \(access)\(staticKw)func \(memberPrefix)Returns(_ values: \(storedReturn)...) {
            var queue = values
            \(memberPrefix)Handler = { \(closureHead)
                queue.count > 1 ? queue.removeFirst() : queue[0]
            }
        }
        """
        resetLines.append("_\(memberPrefix)ReturnValue = nil")
    }

    // `…ThrowsError` convenience for any throwing requirement. The parameter type
    // matches the (possibly typed) throw. The handler closure is written with an
    // explicit signature so a typed throw (`throws(E)`) is inferred correctly
    // rather than widening to `any Error`.
    if isThrows {
        let errorType = throwsClause?.type?.trimmedDescription ?? "any Error"
        let typedParams = params.map { "_: \($0.bareType)" }.joined(separator: ", ")
        storage += """

        \(access)\(staticKw)func \(memberPrefix)ThrowsError(_ error: \(errorType)) {
            \(memberPrefix)Handler = { (\(typedParams))\(effects) -> \(handlerReturn) in throw error }
        }
        """
    }

    // Reconstruct the declaration so the mock conforms to the protocol exactly.
    let paramText = params.map { p -> String in
        let head: String
        switch p.label {
        case nil: head = "_ \(p.escapedName)"
        case p.name?: head = p.name   // label and name are one token; the binding is referenced via escapedName
        case let label?: head = "\(label) \(p.escapedName)"
        }
        return "\(head): \(p.type)"
    }.joined(separator: ", ")
    let returnClause = returnType.map { " -> \($0)" } ?? ""

    let callArgs = params.map(\.callArgument).joined(separator: ", ")
    let callPrefix = "\(isThrows ? "try " : "")\(isAsync ? "await " : "")"

    let invocation: String
    if let returnType, returnType != "Void" {
        // A generic or `Self` return is stored loosely and force-cast back.
        // Otherwise an optional or collection return falls back to an empty value
        // when unstubbed; anything else traps so a missing stub is loud.
        let erased = returnIsGeneric || returnHasSelf
        let cast = erased ? " as! \(returnType)" : ""
        let fallback = erased ? nil : returnTypeSyntax.flatMap(defaultReturn(for:))
        let hint = erased ? "`\(memberPrefix)Handler`" : "`\(memberPrefix)ReturnValue` or `\(memberPrefix)Handler`"
        let missingHandler = fallback.map { "return \($0)" }
            ?? "fatalError(\"\(mockName).\(name) needs \(hint) to be set.\")"
        invocation = """
            guard let \(memberPrefix)Handler else {
                \(missingHandler)
            }
            return \(callPrefix)\(memberPrefix)Handler(\(callArgs))\(cast)
        """
    } else {
        invocation = "    \(callPrefix)\(memberPrefix)Handler?(\(callArgs))"
    }

    let bodyLines = ["    \(memberPrefix)CallCount += 1", recordLine, invocation]
        .filter { !$0.isEmpty }
        .joined(separator: "\n")

    let decls = """
    \(storage)
    \(methodPrefix)func \(name)\(genericClause)(\(paramText))\(effects)\(returnClause)\(whereClause) {
    \(bodyLines)
    }
    """
    return GeneratedMember(decls: decls, resetLines: isStatic ? [] : resetLines)
}

// MARK: - Subscript members

private func subscriptMembers(
    _ decl: SubscriptDeclSyntax,
    memberPrefix prefix: String,
    mockName: String,
    access: String,
    globalActor: String
) -> GeneratedMember {
    let genericNames = Set(decl.genericParameterClause?.parameters.map { $0.name.text } ?? [])
    let genericClause = decl.genericParameterClause?.trimmedDescription ?? ""
    let whereClause = decl.genericWhereClause.map { " \($0.trimmedDescription)" } ?? ""

    let returnTypeSyntax = decl.returnClause.type
    let returnType = returnTypeSyntax.trimmedDescription                 // subscript decl (keeps IUO)
    let storedReturn = normalizeIUO(returnType)                          // storage (IUO → optional)
    let returnIsGeneric = referencesGeneric(returnType, genericNames)
    let returnHasSelf = referencesGeneric(returnType, ["Self"])
    let handlerReturn = returnIsGeneric ? "Any" : substitutingSelf(storedReturn, with: mockName)
    let cast = (returnIsGeneric || returnHasSelf) ? " as! \(returnType)" : ""

    let params = parsedParameters(decl.parameterClause.parameters, genericNames: genericNames, mockName: mockName)
    let recordableParams = params.filter(\.recordable)
    let callArgs = params.map(\.callArgument).joined(separator: ", ")
    let closureParams = params.map(\.bareType).joined(separator: ", ")
    let paramClause = decl.parameterClause.trimmedDescription

    let isStatic = decl.modifiers.contains { $0.name.text == "static" }
    let isNonisolated = decl.modifiers.contains { $0.name.text == "nonisolated" }
    let memberActor = isNonisolated ? "" : globalActor
    let staticKw = isStatic ? "static " : ""
    let needsUnsafe = isStatic || (isNonisolated && !globalActor.isEmpty)
    let storedStatic = "\(needsUnsafe ? "nonisolated(unsafe) " : "")\(staticKw)"
    let member = "\(access)\(storedStatic)"
    let counter = "\(access)private(set) \(storedStatic)"
    let declPrefix = "\(access)\(isNonisolated ? "nonisolated " : "")\(staticKw)"

    var isSettable = false
    if let block = decl.accessorBlock, case .accessors(let list) = block.accessors {
        isSettable = list.contains { $0.accessorSpecifier.text == "set" }
    }

    // Builds the `…Calls` storage + append statement for a list of recorded values.
    func calls(_ name: String, _ entries: [(label: String, type: String, value: String)]) -> (storage: String, record: String, reset: String) {
        switch entries.count {
        case 0:
            return ("", "", "")
        case 1:
            return ("\n\(counter)var \(name)Calls: [\(entries[0].type)] = []",
                    "        \(name)Calls.append(\(entries[0].value))",
                    "\(name)Calls = []")
        default:
            let types = entries.map { "\($0.label): \($0.type)" }.joined(separator: ", ")
            let values = entries.map { "\($0.label): \($0.value)" }.joined(separator: ", ")
            return ("\n\(counter)var \(name)Calls: [(\(types))] = []",
                    "        \(name)Calls.append((\(values)))",
                    "\(name)Calls = []")
        }
    }

    let indexEntries = recordableParams.map { (label: $0.name, type: $0.recordType, value: $0.escapedName) }

    // Getter storage + body.
    let getHandlerType = "(\(memberActor)(\(closureParams)) -> \(handlerReturn))?"
    var storage = """
    \(member)var \(prefix)GetHandler: \(getHandlerType)
    \(counter)var \(prefix)GetCallCount = 0
    """
    var resetLines = ["\(prefix)GetHandler = nil", "\(prefix)GetCallCount = 0"]
    let getCalls = calls("\(prefix)Get", indexEntries)
    storage += getCalls.storage
    if !getCalls.reset.isEmpty { resetLines.append(getCalls.reset) }

    let fallback = (returnIsGeneric || returnHasSelf) ? nil : defaultReturn(for: returnTypeSyntax)
    let missingGet = fallback.map { "return \($0)" }
        ?? "fatalError(\"\(mockName) subscript needs `\(prefix)GetHandler` to be set.\")"
    var getStatements = ["        \(prefix)GetCallCount += 1"]
    if !getCalls.record.isEmpty { getStatements.append(getCalls.record) }
    getStatements.append("""
            guard let \(prefix)GetHandler else {
                \(missingGet)
            }
            return \(prefix)GetHandler(\(callArgs))\(cast)
    """)
    let getter = "    get {\n\(getStatements.joined(separator: "\n"))\n    }"

    var accessors = getter
    if isSettable {
        let setHandlerType = "(\(memberActor)(\(closureParams), \(handlerReturn)) -> Void)?"
        storage += """

        \(member)var \(prefix)SetHandler: \(setHandlerType)
        \(counter)var \(prefix)SetCallCount = 0
        """
        resetLines.append(contentsOf: ["\(prefix)SetHandler = nil", "\(prefix)SetCallCount = 0"])
        let setCalls = calls("\(prefix)Set", indexEntries + [(label: "newValue", type: handlerReturn, value: "newValue")])
        storage += setCalls.storage
        if !setCalls.reset.isEmpty { resetLines.append(setCalls.reset) }

        var setStatements = ["        \(prefix)SetCallCount += 1"]
        if !setCalls.record.isEmpty { setStatements.append(setCalls.record) }
        let setArgs = callArgs.isEmpty ? "newValue" : "\(callArgs), newValue"
        setStatements.append("        \(prefix)SetHandler?(\(setArgs))")
        accessors += "\n    set {\n\(setStatements.joined(separator: "\n"))\n    }"
    }

    storage += "\n\(access)\(staticKw)var \(prefix)GetWasCalled: Bool { \(prefix)GetCallCount > 0 }"

    let decls = """
    \(storage)
    \(declPrefix)subscript\(genericClause)\(paramClause) -> \(returnType)\(whereClause) {
    \(accessors)
    }
    """
    return GeneratedMember(decls: decls, resetLines: isStatic ? [] : resetLines)
}

// MARK: - Property members

private func propertyMembers(
    _ variable: VariableDeclSyntax,
    mockName: String,
    access: String,
    globalActor: String
) -> GeneratedMember? {
    guard let binding = variable.bindings.first,
          let pattern = binding.pattern.as(IdentifierPatternSyntax.self),
          let type = binding.typeAnnotation?.type
    else { return nil }

    let rawName = unescapedIdentifier(pattern.identifier.text)
    let name = escapedIdentifier(rawName)        // public property name
    let backing = "_\(rawName)"                  // underscore prefix → never a keyword
    // `Self` can't appear in a stored property; the mock is `final`, so the
    // concrete type is equivalent and still satisfies the requirement. An IUO type
    // (`Int!`) is kept as-is — a stored IUO property conforms and defaults to nil.
    let typeText = substitutingSelf(type.trimmedDescription, with: mockName)
    let isIUO = type.is(ImplicitlyUnwrappedOptionalTypeSyntax.self)
    let isStatic = variable.modifiers.contains { $0.name.text == "static" }
    // A `nonisolated` requirement on an actor-isolated mock needs nonisolated
    // storage and accessor (see the function path for the same handling).
    let isNonisolated = variable.modifiers.contains { $0.name.text == "nonisolated" }
    let needsUnsafe = isStatic || (isNonisolated && !globalActor.isEmpty)
    let staticKw = isStatic ? "static " : ""
    let storedStatic = "\(needsUnsafe ? "nonisolated(unsafe) " : "")\(staticKw)"
    let isolation = isNonisolated ? "nonisolated " : ""

    // An optional (or IUO) requirement is satisfied by a plain stored property
    // defaulting to nil, which is also settable from the test.
    if type.is(OptionalTypeSyntax.self) || isIUO {
        return GeneratedMember(
            decls: "\(access)\(storedStatic)var \(name): \(typeText)",
            resetLines: isStatic ? [] : ["\(name) = nil"]
        )
    }

    // A non-optional requirement needs a value the mock can't synthesise, so back
    // it with an optional and expose the exact type via a computed accessor.
    // `Optional<…>` (not `…?`) so a function-typed property binds the `?` correctly.
    let decls = """
    private \(storedStatic)var \(backing): Optional<\(typeText)> = nil
    \(access)\(isolation)\(staticKw)var \(name): \(typeText) {
        get {
            guard let \(backing) else {
                fatalError("\(mockName).\(rawName) was read before it was set.")
            }
            return \(backing)
        }
        set { \(backing) = newValue }
    }
    """
    return GeneratedMember(decls: decls, resetLines: isStatic ? [] : ["\(backing) = nil"])
}

// MARK: - Types

/// The empty value a method can return when it has no handler, or `nil` if the
/// return type has no safe default (in which case an unstubbed call traps).
private func defaultReturn(for type: TypeSyntax) -> String? {
    if type.is(OptionalTypeSyntax.self) || type.is(ImplicitlyUnwrappedOptionalTypeSyntax.self) {
        return "nil"
    }
    if type.is(ArrayTypeSyntax.self) { return "[]" }
    if type.is(DictionaryTypeSyntax.self) { return "[:]" }
    if let ident = type.as(IdentifierTypeSyntax.self) {
        switch ident.name.text {
        case "Optional": return "nil"
        case "Array", "ContiguousArray", "Set": return "[]"
        case "Dictionary": return "[:]"
        default: return nil
        }
    }
    return nil
}

/// Whether a type's text mentions any of the given generic parameter names.
private func referencesGeneric(_ typeText: String, _ names: Set<String>) -> Bool {
    guard !names.isEmpty else { return false }
    let tokens = typeText.split { !($0.isLetter || $0.isNumber || $0 == "_") }
    return tokens.contains { names.contains(String($0)) }
}

/// Separates a parameter type into its attributes (`@escaping`), ownership
/// specifiers (`inout`, `borrowing`, `consuming`, …), and the underlying type.
private func splitType(_ type: TypeSyntax) -> (attributes: String, specifiers: [String], base: String) {
    guard let attributed = type.as(AttributedTypeSyntax.self) else {
        return ("", [], type.trimmedDescription)
    }
    let attributes = attributed.attributes.trimmedDescription
    let specifiers = attributed.specifiers.map { $0.trimmedDescription }
    return (attributes, specifiers, attributed.baseType.trimmedDescription)
}

/// Normalizes an implicitly-unwrapped optional (`Int!`) to a plain optional
/// (`Int?`). `!` is illegal inside a stored closure/array type, and a `?` witness
/// satisfies an IUO requirement, so the mock uses the optional form throughout.
private func normalizeIUO(_ type: String) -> String {
    type.hasSuffix("!") ? "\(type.dropLast())?" : type
}

/// Removes surrounding back-ticks from a source identifier so it can be
/// re-escaped only where needed (`firstName.text` keeps them when escaped).
private func unescapedIdentifier(_ text: String) -> String {
    guard text.count >= 2, text.hasPrefix("`"), text.hasSuffix("`") else { return text }
    return String(text.dropFirst().dropLast())
}

/// Reserved Swift keywords that must be back-tick escaped when used as an
/// identifier (parameter name, tuple label, or value reference).
private let reservedKeywords: Set<String> = [
    "associatedtype", "class", "deinit", "enum", "extension", "fileprivate", "func",
    "import", "init", "inout", "internal", "let", "open", "operator", "private",
    "protocol", "public", "rethrows", "static", "struct", "subscript", "typealias",
    "var", "break", "case", "continue", "default", "defer", "do", "else", "fallthrough",
    "for", "guard", "if", "in", "repeat", "return", "switch", "where", "while", "as",
    "catch", "false", "is", "nil", "super", "self", "Self", "throw", "throws", "true",
    "try", "Any", "Protocol", "Type",
]

/// Back-tick escapes `name` when it collides with a reserved keyword.
private func escapedIdentifier(_ name: String) -> String {
    reservedKeywords.contains(name) ? "`\(name)`" : name
}

/// Replaces the whole word `Self` with the concrete mock type name. The mock is
/// `final`, so `Self` resolves to it — but `Self` can't appear in stored property
/// types, where the substitution is needed. Tokenizes by hand to stay available
/// on the macro plugin's deployment target (no `Regex`, which needs macOS 13+).
private func substitutingSelf(_ text: String, with mockName: String) -> String {
    func isIdentifierCharacter(_ c: Character) -> Bool {
        c.isLetter || c.isNumber || c == "_"
    }
    var result = ""
    var token = ""
    for character in text {
        if isIdentifierCharacter(character) {
            token.append(character)
        } else {
            result += (token == "Self" ? mockName : token)
            token = ""
            result.append(character)
        }
    }
    result += (token == "Self" ? mockName : token)
    return result
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

/// Describes a protocol requirement `@Mockable` doesn't generate, or `nil` if the
/// member needs no warning (e.g. a nested type the mock can simply ignore).
private func unsupportedMemberDescription(_ decl: DeclSyntax) -> String? {
    if decl.is(InitializerDeclSyntax.self) { return "`init` requirements" }
    if decl.is(AssociatedTypeDeclSyntax.self) { return "`associatedtype` requirements" }
    return nil
}

/// Whether a function name is an operator (so it can't form an identifier prefix).
private func isOperatorName(_ name: String) -> Bool {
    guard let first = name.first else { return false }
    return !(first.isLetter || first == "_")
}

/// Stable, unique member-name prefixes for subscripts (which have no names).
/// One subscript is just `subscript`; overloads disambiguate by parameter type.
private func subscriptDisambiguatedPrefixes(for subscripts: [SubscriptDeclSyntax]) -> [String] {
    guard subscripts.count > 1 else {
        return subscripts.isEmpty ? [] : ["subscript"]
    }
    var result = subscripts.map { decl -> String in
        let types = decl.parameterClause.parameters
            .map { $0.type.trimmedDescription.alphanumericsOnly.capitalizedFirstLetter }
            .joined()
        return "subscript\(types)"
    }
    // Numeric fallback for any remaining collisions.
    var counts: [String: Int] = [:]
    for prefix in result { counts[prefix, default: 0] += 1 }
    var running: [String: Int] = [:]
    for index in result.indices where counts[result[index]]! > 1 {
        let n = (running[result[index]] ?? 0) + 1
        running[result[index]] = n
        result[index] += "\(n)"
    }
    return result
}

private struct MimicDiagnostic: DiagnosticMessage {
    let message: String
    let diagnosticID = MessageID(domain: "Mimic", id: "unsupported-requirement")
    let severity: DiagnosticSeverity = .warning

    init(_ message: String) { self.message = message }
}

enum MimicError: Error, CustomStringConvertible {
    case notAProtocol

    var description: String {
        switch self {
        case .notAProtocol:
            return "@Mockable can only be attached to a protocol."
        }
    }
}
