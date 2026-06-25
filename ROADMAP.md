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

## v0.3 — Stubbing ergonomics ✅ (shipped)

- `…ReturnValue` shorthand for the common "always return X" case (no closure needed)
- A generated `mimicReset()` that clears all counters, recorded calls, handlers, and
  property values (namespaced so it can't clash with a protocol requirement)
- **Completion-handler functions** — `@escaping`/`@autoclosure` attributes are stripped
  from the stored closure type, so callback-style APIs mock cleanly
- **Async & throws** — `async`, `throws`, and **typed throws** (`throws(MyError)`) are
  carried through verbatim into both the handler type and the conforming method

## v0.4 — Stubbing ergonomics, continued

- Sensible default returns for `Void`, `Optional`, and empty collections so trivial
  methods need no stub at all
- `…LastCall` convenience and a `wasCalled` flag per member
- Per-handler call-order assertions across members

## v0.5 — Surface coverage

- Generic methods (`func decode<T: Decodable>(_:) -> T`)
- `subscript` requirements
- Inherited / composed protocol requirements (walk the inheritance clause)
- `mutating` and `rethrows` requirements
- Variadic parameters

## v0.6 — Polish & 1.0

- DocC catalog with articles and symbol docs
- GitHub Actions CI (`swift test` on macOS, build on Linux toolchain)
- Expanded examples + a small sample test suite as living documentation
- Tag **1.0.0**

## Non-goals

- Runtime reflection or method swizzling — everything is compile-time source generation
- Third-party runtime dependencies of any kind
- Auto-mocking concrete classes — protocols only, by design
