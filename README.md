# Mimic

[![CI](https://github.com/LoveYahweh/Mimic/actions/workflows/ci.yml/badge.svg)](https://github.com/LoveYahweh/Mimic/actions/workflows/ci.yml)

Macro-driven mocks for Swift unit tests — **zero third-party runtime dependencies**.

Annotate a protocol with `@Mockable` and Mimic generates a `Mock<Name>` test double that
records every call and lets you stub behaviour with a closure. No reflection, no code
generation step, no runtime magic — just a Swift macro that writes the boilerplate you'd
write by hand.

```swift
import Mimic

@Mockable
protocol WeatherService {
    var lastCity: String? { get }
    func temperature(in city: String) async throws -> Double
    func refresh()
}
```

That expands, at compile time, to a `MockWeatherService` you use in tests:

```swift
let mock = MockWeatherService()
mock.temperatureHandler = { city in city == "Houston" ? 95 : 60 }

let temp = try await mock.temperature(in: "Houston")   // 95

#expect(mock.temperatureCallCount == 1)
#expect(mock.temperatureCalls == ["Houston"])
```

For the common "just return this" case, skip the closure entirely:

```swift
mock.temperatureReturnValue = 72            // every call returns 72
mock.temperatureReturns(60, 70, 80)         // each call in turn, then 80 repeats
mock.temperatureThrowsError(NetworkError.offline)   // throwing requirements only
mock.mimicReset()                           // back to a fresh mock: handlers, counts, recorded calls
```

## What gets generated

For every protocol requirement the mock gains:

| Member | Generated API |
| --- | --- |
| `func load(id: Int) -> String` | `loadHandler: ((Int) -> String)?` · `loadCallCount` · `loadCalls: [Int]` · `loadWasCalled` · `loadLastCall` |
| multi-parameter method | `…Calls` records a **labelled tuple**, e.g. `[(name: String, value: Int)]` |
| method returning `Optional`/`Array`/`Dictionary`/`Set` | returns an empty value when unstubbed — no handler needed |
| `async` / `throws` method | the handler closure mirrors the effects: `((Int) async throws -> String)?` |
| `func reset()` (void) | handler is optional — no stub needed; the call is still counted |
| `var token: String? { get set }` | a settable stored property |
| `var isReady: Bool { get }` | a settable property (reading before it's set traps with a clear message) |
| non-void method | also a `…ReturnValue` shorthand that stubs a constant-returning handler |
| completion-handler method (`@escaping`) | the closure is captured in the handler so the test can invoke it |
| `throws(MyError)` (typed throws) | effects are copied verbatim, so the typed throw is preserved |
| overloaded methods | handler/recording names are disambiguated by argument label, e.g. `value(for:)` → `valueForHandler`, `value(at:)` → `valueAtHandler` |
| `static` requirements | generated as `static` members on the mock type |

Every mock also gets a `mimicReset()` that clears all handlers, call counts, recorded
arguments, and property values — handy for shared or reused mocks.

## Worked example

[`Sources/MimicDemo`](Sources/MimicDemo) is a small checkout subsystem — a
`CheckoutCoordinator` orchestrating five protocol dependencies (cart, inventory, payment,
coupons, analytics) covering sync methods, `async throws`, a completion handler, a
collection property, and a void analytics call. [`Tests/MimicDemoTests`](Tests/MimicDemoTests)
drives it entirely through the generated mocks — stubbing with `…ReturnValue` and
`…Handler`, asserting on `…CallCount`/`…LastCall`/`…WasCalled`, and resetting with
`mimicReset()`. It doubles as living documentation for how the mocks read in real tests.

[`XcodeDemo/`](XcodeDemo) is a runnable **SwiftUI iOS app** that consumes the package and
tests a view model through a Mimic mock — proof it works inside a real Xcode project, not
just SwiftPM. Run its tests with `xcodebuild test … -skipMacroValidation`.

A non-void method called before its handler is set traps with a message that names the
member, so a missing stub fails loudly instead of silently returning a default.

The generated mock mirrors the protocol's access level: a `public` (or `package`) protocol
produces a `public` (or `package`) mock so it's usable from a separate test module.

## Why no third-party dependencies?

Swift macros require [`swift-syntax`](https://github.com/swiftlang/swift-syntax) — that's
the official swiftlang compiler library, and it only runs **at compile time** inside the
macro plugin. Nothing ships in your app or test binary except `Mimic` itself, which is pure
`Swift`. No mocking runtime, no linker tricks, no Objective-C.

## Installation

Swift Package Manager:

```swift
.package(url: "https://github.com/<you>/Mimic.git", from: "0.1.0")
```

```swift
.testTarget(
    name: "MyAppTests",
    dependencies: ["MyApp", "Mimic"]
)
```

Put `@Mockable` on the protocol in your app target so the mock is generated alongside it,
then `@testable import MyApp` to use it.

## Requirements

- Swift 6.0+ toolchain
- iOS 13+ / macOS 10.15+ / tvOS 13+ / watchOS 6+

## Supported

Sync / `async` / `throws` / typed `throws` methods · **generic methods** (type-erased) ·
**variadic**, `inout`, `borrowing`/`consuming`, closure, tuple, optional, and defaulted
parameters · keyword parameter names · `Self` results and parameters · `mutating` /
`static` requirements · overloads (by label, arity, type, or async-ness) · get-only /
get-set / optional / collection / function-type properties · **`@MainActor` (and custom
global-actor) protocols, including `nonisolated` members** · access-level mirroring.

Generic methods are type-erased: the handler trades in `Any` and the result is force-cast
back to the requested type, so `let x: Int = mock.decode("1")` works while keeping the
mock storable.

## Current limitations

On the [roadmap](ROADMAP.md):

- **`subscript`** and **`rethrows`** requirements aren't generated yet (subscript/`init`/
  `associatedtype` requirements emit a clear warning rather than a confusing conformance
  error).
- A **non-escaping closure hidden behind a `typealias`** can't be detected — a macro can't
  resolve the alias — so it's recorded and won't compile. Use the closure type inline, or
  mark it `@escaping`.
- Effectful property accessors (`{ get async throws }`) aren't supported.
- **Inherited / composed protocols** can't be supported by a peer macro: it only sees the
  annotated protocol's own syntax, never the parent's members. Re-declare (or annotate the
  parent and compose) instead.

## Running the tests

```sh
swift test
```

Behaviour is covered with Swift Testing; the generated source is pinned with
`assertMacroExpansion`.

## License

MIT — see [LICENSE](LICENSE).
