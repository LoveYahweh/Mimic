# Getting Started

Add Mimic, annotate a protocol, and drive it from a test.

## Install

Add the package to your `Package.swift`:

```swift
.package(url: "https://github.com/LoveYahweh/Mimic.git", from: "1.3.0")
```

and depend on it from your test target:

```swift
.testTarget(name: "MyAppTests", dependencies: ["MyApp", "Mimic"])
```

## Annotate a protocol

Put ``Mockable()`` on the protocol **in your app target**, so the mock is generated next to
it:

```swift
import Mimic

@Mockable
protocol UserStore {
    func user(id: Int) async throws -> User
    func save(_ user: User)
}
```

This generates an internal `MockUserStore`. From the test target, reach it with
`@testable import MyApp`. (A `public` protocol produces a `public` mock — no `@testable`
needed.)

## Drive it from a test

```swift
@testable import MyApp
import Mimic
import Testing

@Test func loadsAndCaches() async throws {
    let store = MockUserStore()
    store.userReturnValue = User(id: 1, name: "Ada")

    let model = ProfileModel(store: store)
    try await model.load(id: 1)

    #expect(model.title == "Ada")
    #expect(store.userCalls == [1])      // recorded arguments
    #expect(store.userCallCount == 1)
}
```

## Next steps

- <doc:Stubbing> — return values, sequences, errors, and argument matching
- <doc:GeneratedAPI> — the full set of members the macro generates
