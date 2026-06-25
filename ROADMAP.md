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

## v0.4 — Stubbing ergonomics, continued ✅ (shipped)

- Default returns for `Optional`, `Array`, `Dictionary`, and `Set` so trivial methods
  need no stub at all
- `…LastCall` convenience and a `…WasCalled` flag per member
- A worked `MimicDemo` example subsystem with a full mock-driven test suite

Still open: per-handler call-order assertions across members.

## v0.5 — Surface coverage (in progress)

- **Generic methods** ✅ (`func decode<T>(_:) -> T`) — type-erased to `Any` in storage
  and force-cast back; generic clause + `where` clause preserved on the method
- **Variadic parameters** ✅ (`Int...`) — captured as an array in the handler/recording
- `mutating` requirements ✅ (witnessed by a plain method on the class)
- **`subscript` requirements** ✅ — get / get-set, multi-parameter, and overloaded;
  separate get/set handlers + call recording (set records the new value)
- Still open: `rethrows`
- **Not feasible by a peer macro:** inherited / composed protocol requirements. The
  macro only sees the annotated protocol's own syntax, never the parent's members, so
  it can't generate their implementations. Documented as a limitation instead.

## v0.6 — Richer stubbing ✅ (shipped)

- **Sequential returns** ✅ — `…Returns(x, y, z)` varies the result across calls, then
  repeats the last value
- **`…ThrowsError(_:)`** ✅ convenience for throwing requirements (typed-throws aware)

Deferred past 1.0: argument-matched stubs (`when(arg:)`), an order-aware verification
DSL, and per-mock nice/strict modes.

## v0.7 — Polish & 1.0 ✅ (shipped)

- DocC-friendly symbol docs on the public API
- GitHub Actions CI (`swift test` on macOS)
- An **Xcode demo app** (`XcodeDemo/`) that consumes the package and is verified through
  `xcodebuild test` on the iOS simulator
- `CHANGELOG.md` and the **1.0.0** tag

## 1.1 ✅ (shipped)

- **Argument-matched stubs** — `…When(_ match:, return:)` / `…When(_ match:, perform:)`,
  predicate-keyed, tried before the handler.

## 1.2 ✅ (shipped)

- **Order-aware verification** — `mimicInvocations: [Invocation]` (type-safe ordered log)
  plus `mimicVerify(_:before:)`.

## 1.3 ✅ (shipped)

- **`init` requirements** (incl. failable and throwing) and **`rethrows`** requirements.

## Post-1.3 ideas

- Per-mock nice/strict modes (trap vs. silent default)

- DocC catalog with articles and symbol docs
- GitHub Actions CI (`swift test` on macOS, build on Linux toolchain)
- Expanded examples + a small sample test suite as living documentation
- Tag **1.0.0**

## Non-goals

- Runtime reflection or method swizzling — everything is compile-time source generation
- Third-party runtime dependencies of any kind
- Auto-mocking concrete classes — protocols only, by design
