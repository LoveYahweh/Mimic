# Mimic

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

## What gets generated

For every protocol requirement the mock gains:

| Member | Generated API |
| --- | --- |
| `func load(id: Int) -> String` | `loadHandler: ((Int) -> String)?` · `loadCallCount` · `loadCalls: [Int]` |
| multi-parameter method | `…Calls` records a **labelled tuple**, e.g. `[(name: String, value: Int)]` |
| `async` / `throws` method | the handler closure mirrors the effects: `((Int) async throws -> String)?` |
| `func reset()` (void) | handler is optional — no stub needed; the call is still counted |
| `var token: String? { get set }` | a settable stored property |
| `var isReady: Bool { get }` | a settable property (reading before it's set traps with a clear message) |

A non-void method called before its handler is set traps with a message that names the
member, so a missing stub fails loudly instead of silently returning a default.

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

## Current limitations

These are explicit, diagnosed where possible, and on the roadmap:

- **Overloaded members** (same method name, different signatures) are rejected with a
  diagnostic — handler/recording names would collide.
- **Generic methods** and **`static` requirements** aren't generated yet.
- Properties with effectful accessors (`{ get async throws }`) aren't supported.

## Running the tests

```sh
swift test
```

Behaviour is covered with Swift Testing; the generated source is pinned with
`assertMacroExpansion`.

## License

MIT — see [LICENSE](LICENSE).
