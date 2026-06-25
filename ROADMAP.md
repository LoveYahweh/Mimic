# Mimic Roadmap

Direction for `@Mockable`. Each milestone is a shippable increment with tests and a
pinned macro-expansion contract. Runtime stays **zero third-party** throughout —
`swift-syntax` is the only dependency and it runs at compile time only.

## v0.1 — Foundation ✅ (shipped)

- `@Mockable` peer macro generating `Mock<Protocol>`
- Per-member `…Handler` stub closures
- `…CallCount` + `…Calls` argument recording (labelled tuples for multi-param)
- `async` / `throws` effect mirroring
- get-only and get/set properties
- Diagnostics: non-protocol attachment, overloaded members rejected

## v0.2 — Overloads & access ✅ (shipped)

- **Overloaded members** — disambiguate handler/recording names by argument labels
  (falling back to types, then a numeric tail) instead of rejecting them
- **Access-level mirroring** — a `public`/`package` protocol generates a mock with
  matching access so it's usable from a separate test module
- **`static` requirements** — generate `static` handlers, counters, and methods
  (storage marked `nonisolated(unsafe)` for the Swift 6 language mode)

## v0.3 — Stubbing ergonomics

- `…ReturnValue` shorthand for the common "always return X" case (no closure needed)
- Sensible default returns for `Void`, `Optional`, and empty collections so trivial
  methods need no stub at all
- `…LastCall` convenience and a `wasCalled` flag per member
- A generated `reset()` that clears all counters, recorded calls, and handlers

## v0.4 — Surface coverage

- Generic methods (`func decode<T: Decodable>(_:) -> T`)
- `subscript` requirements
- Inherited / composed protocol requirements (walk the inheritance clause)
- `mutating` requirements

## v0.5 — Polish & 1.0

- DocC catalog with articles and symbol docs
- GitHub Actions CI (`swift test` on macOS, build on Linux toolchain)
- Expanded examples + a small sample test suite as living documentation
- Tag **1.0.0**

## Non-goals

- Runtime reflection or method swizzling — everything is compile-time source generation
- Third-party runtime dependencies of any kind
- Auto-mocking concrete classes — protocols only, by design
