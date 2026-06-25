/// Generates a `Mock<ProtocolName>` test double as a peer of the annotated protocol.
///
/// For each protocol requirement the generated mock provides:
/// - a `<member>Handler` closure you assign to stub behaviour,
/// - a `<member>CallCount` counter, and
/// - a `<member>Calls` array recording the arguments of every call.
///
/// ```swift
/// @Mockable
/// protocol Loader {
///     func load(id: Int) async throws -> String
/// }
///
/// let mock = MockLoader()
/// mock.loadHandler = { id in "item-\(id)" }
/// let value = try await mock.load(id: 7)   // "item-7"
/// #expect(mock.loadCallCount == 1)
/// #expect(mock.loadCalls == [7])
/// ```
@attached(peer, names: prefixed(Mock))
public macro Mockable() = #externalMacro(module: "MimicMacros", type: "MockableMacro")
