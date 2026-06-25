# Mimic

[![CI](https://github.com/LoveYahweh/Mimic/actions/workflows/ci.yml/badge.svg)](https://github.com/LoveYahweh/Mimic/actions/workflows/ci.yml)
[![Docs](https://github.com/LoveYahweh/Mimic/actions/workflows/docs.yml/badge.svg)](https://loveyahweh.github.io/Mimic/documentation/mimic/)
[![Swift 6](https://img.shields.io/badge/Swift-6-orange.svg)](https://swift.org)
[![Platforms](https://img.shields.io/badge/platforms-iOS%20%7C%20macOS%20%7C%20tvOS%20%7C%20watchOS-blue.svg)](#requirements)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)

**Macro-driven mocks for Swift unit tests — with zero third-party runtime dependencies.**

Annotate a protocol with `@Mockable` and Mimic generates a `Mock<Name>` test double that
records every call and lets you stub behaviour with a closure. No reflection, no separate
code-generation step, no runtime — just a Swift macro that writes, at compile time, the
boilerplate you'd otherwise write by hand.

```swift
import Mimic

@Mockable
protocol WeatherService {
    var lastCity: String? { get }
    func temperature(in city: String) async throws -> Double
    func refresh()
}
```

```swift
let mock = MockWeatherService()
mock.temperatureHandler = { city in city == "Paris" ? 95 : 60 }

let temp = try await mock.temperature(in: "Paris")   // 95

#expect(mock.temperatureCallCount == 1)
#expect(mock.temperatureCalls == ["Paris"])
```

## Why Mimic

- **Zero runtime dependencies.** `swift-syntax` runs only at compile time inside the macro
  plugin. Nothing third-party ships in your app or test binary — no mocking runtime, no
  linker tricks, no Objective-C.
- **Covers the real Swift surface.** Methods, properties, subscripts, generics, `async` /
  `throws` / typed throws, `@MainActor`, overloads, every type form — see [Support](#support).
- **Reads like hand-written tests.** Stub with a closure or a one-liner; assert on call
  counts and recorded arguments. No string-keyed APIs, no magic.
- **Fails loudly, not silently.** A missing stub traps with a message naming the member,
  instead of returning a surprise default.

## Stubbing & assertions

For every requirement you get a `…Handler` closure plus convenience shortcuts:

```swift
mock.temperatureReturnValue = 72                    // always return 72
mock.temperatureReturns(60, 70, 80)                 // 60, then 70, then 80 repeats
mock.temperatureThrowsError(NetworkError.offline)   // throw (throwing requirements only)
mock.mimicReset()                                   // clear handlers, counts, recorded calls
```

**Argument-matched stubs** let different inputs return different results. Each `…When`
registers a predicate; the first match wins, otherwise the call falls through to the handler:

```swift
mock.temperatureWhen({ $0 == "Paris" }, return: 95)
mock.temperatureWhen({ city in city.hasPrefix("L") }, perform: { _ in throw NetworkError.offline })
```

…and recording for assertions:

```swift
mock.temperatureCallCount   // Int
mock.temperatureCalls       // [String]  (labelled tuple for multi-parameter members)
mock.temperatureWasCalled   // Bool
mock.temperatureLastCall    // String?   (most recent arguments)
```

**Order-aware verification.** Every mock keeps a type-safe log of which methods were called,
in order, plus a `mimicVerify(_:before:)` helper:

```swift
mock.mimicInvocations                       // [.validate, .reserve, .charge]
#expect(mock.mimicInvocations == [.validate, .reserve, .charge])
#expect(mock.mimicVerify(.validate, before: .charge))
```

## What gets generated

| Requirement | Generated API |
| --- | --- |
| `func load(id: Int) -> String` | `loadHandler` · `loadReturnValue` · `loadReturns(…)` · `loadWhen(_:return:)` · `loadCallCount` · `loadCalls` · `loadWasCalled` · `loadLastCall` |
| multi-parameter method | `…Calls` records a **labelled tuple**, e.g. `[(name: String, value: Int)]` |
| returns `Optional`/`Array`/`Dictionary`/`Set` | returns an empty value when unstubbed — no handler needed |
| `async` / `throws` / `throws(MyError)` | the handler closure mirrors the effects, typed throws preserved |
| completion handler (`@escaping`) | the closure is captured in the handler so the test can invoke it |
| `subscript(…) -> T { get set }` | `subscriptGetHandler` / `subscriptSetHandler`, with get/set call recording |
| `var token: String? { get set }` | a settable stored property |
| overloaded methods | names disambiguate by label, e.g. `value(for:)` → `valueForHandler`, `value(at:)` → `valueAtHandler` |
| `static` / `mutating` / `nonisolated` | generated with matching modifiers |

The mock mirrors the protocol's access level, so a `public` (or `package`) protocol yields a
`public` (or `package`) mock usable from a separate test module.

## Support

**Requirement kinds** — methods · properties · subscripts (get / get-set / multi-param /
overloaded) · **initializers** (incl. failable and throwing) · `static` · `mutating` ·
`nonisolated`.

**Effects & generics** — `sync` / `async` / `throws` / typed `throws` / `rethrows` ·
generic methods (type-erased to `Any`, force-cast back; generic and `where` clauses
preserved).

**Parameters** — `inout`, variadic (`Int...`), `borrowing` / `consuming`, closures,
`@escaping`, `@autoclosure`, tuples, defaulted, and keyword-named parameters.

**Type forms** — optionals, IUO (`Int!`), nested optionals, arrays / dictionaries / sets,
tuples, function types, existentials (`any P`), compositions (`A & B`), metatypes (`T.Type`),
key paths, nested generics, and `Self` (result and parameter).

**Concurrency** — `@MainActor` and custom global-actor protocols, with isolation propagated
to the mock and its handler closures; `nonisolated` members are reachable off the actor.

## Installation

Swift Package Manager:

```swift
.package(url: "https://github.com/LoveYahweh/Mimic.git", from: "1.0.0")
```

```swift
.testTarget(
    name: "MyAppTests",
    dependencies: ["MyApp", "Mimic"]
)
```

Put `@Mockable` on the protocol in your app target so the mock is generated alongside it,
then `@testable import MyApp` to use it. (For a `public` protocol in a framework, no
`@testable` is needed — the mock is public too.)

## Requirements

- Swift 6.0+ toolchain
- iOS 13+ / macOS 10.15+ / tvOS 13+ / watchOS 6+

## Worked examples

[`Sources/MimicDemo`](Sources/MimicDemo) is a small checkout subsystem — a
`CheckoutCoordinator` orchestrating five protocol dependencies (cart, inventory, payment,
coupons, analytics) covering sync methods, `async throws`, a completion handler, a
collection property, and a void analytics call. [`Tests/MimicDemoTests`](Tests/MimicDemoTests)
drives it entirely through the generated mocks.

[`XcodeDemo/`](XcodeDemo) is a runnable **SwiftUI iOS app** that consumes the package and
tests a view model through a Mimic mock — proof it works inside a real Xcode project, not
just SwiftPM.

## Limitations

- **Inherited / composed protocols** can't be generated by a peer macro — it only sees the
  annotated protocol's own syntax, never the parent's members. Re-declare the requirements,
  or annotate the parent and compose.
- `associatedtype` and operator requirements aren't generated; they emit a clear warning
  rather than a confusing conformance error.
- A non-escaping closure hidden behind a `typealias` can't be detected (a macro can't
  resolve the alias) — use the closure type inline or mark it `@escaping`.

## Documentation

📖 **[loveyahweh.github.io/Mimic](https://loveyahweh.github.io/Mimic/documentation/mimic/)** —
published from the [DocC](https://www.swift.org/documentation/docc/) catalog in
[`Sources/Mimic/Documentation.docc`](Sources/Mimic/Documentation.docc): an overview, a
getting-started guide, a stubbing & verification guide, and a reference for the generated
API. In Xcode: **Product ▸ Build Documentation**. From the command line (the DocC plugin is
opt-in, so it isn't in the default dependency graph):

```sh
MIMIC_DOCC=1 swift package --allow-writing-to-directory ./docs \
  generate-documentation --target Mimic --output-path ./docs
```

## Running the tests

```sh
swift test
```

Behaviour is covered with Swift Testing; the generated source is pinned with
`assertMacroExpansion`. See [ROADMAP.md](ROADMAP.md) and [CHANGELOG.md](CHANGELOG.md).

## License

MIT — see [LICENSE](LICENSE).
