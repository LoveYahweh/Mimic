# Stubbing and Verification

Control what a mock returns, and assert how it was used.

## Stub a return value

The quickest stub assigns `…ReturnValue`:

```swift
mock.temperatureReturnValue = 72        // every call returns 72
```

For varied behaviour, assign the `…Handler` closure (it mirrors the method's `async` /
`throws`):

```swift
mock.temperatureHandler = { city in city == "Paris" ? 95 : 60 }
```

Return a different value on each call with `…Returns`, which repeats the last value once
the sequence is exhausted:

```swift
mock.temperatureReturns(60, 70, 80)     // 60, then 70, then 80, then 80…
```

Make a throwing requirement throw with `…ThrowsError`:

```swift
mock.fetchThrowsError(NetworkError.offline)
```

## Argument-matched stubs

`…When` registers a predicate-keyed stub. The stubs are tried in registration order; the
first match wins, otherwise the call falls through to the handler:

```swift
mock.temperatureWhen({ $0 == "Paris" }, return: 95)
mock.temperatureWhen({ $0.hasPrefix("L") }, perform: { _ in throw NetworkError.offline })
```

## Assert on calls

Every member records how it was used:

```swift
mock.temperatureCallCount    // Int
mock.temperatureCalls        // [String] (labelled tuple for multi-parameter members)
mock.temperatureWasCalled    // Bool
mock.temperatureLastCall     // String? (most recent arguments)
```

## Verify ordering

Each mock keeps a type-safe, ordered log of method calls plus a `mimicVerify(_:before:)`
helper:

```swift
#expect(mock.mimicInvocations == [.validate, .reserve, .charge])
#expect(mock.mimicVerify(.validate, before: .charge))
```

## Reset

`mimicReset()` returns a reused mock to a clean slate — clearing handlers, stubs, counts,
recorded calls, and the invocation log:

```swift
mock.mimicReset()
```
