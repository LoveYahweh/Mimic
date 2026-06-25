# Generated API Reference

The members ``Mockable()`` adds to a mock, and how they're named.

## Overview

The generated members aren't ordinary Swift symbols, so they don't appear in the symbol
reference. This article documents the naming scheme. For a method `foo`, the mock gains:

| Member | Purpose |
| --- | --- |
| `fooHandler` | the stub closure (mirrors the method's `async` / `throws`) |
| `fooReturnValue` | constant-return shorthand (non-void, non-generic) |
| `fooReturns(_:)` | sequential return values, last one repeats |
| `fooThrowsError(_:)` | throw a given error (throwing requirements) |
| `fooWhen(_:return:)` / `fooWhen(_:perform:)` | argument-matched stubs |
| `fooCallCount` | number of calls |
| `fooCalls` | recorded arguments (a labelled tuple for multiple parameters) |
| `fooWasCalled` | `fooCallCount > 0` |
| `fooLastCall` | the most recent arguments |

## Overloads

Overloaded methods are disambiguated by argument label, then parameter type:

```swift
func value(for key: String) -> Int   // → valueForHandler, valueForCalls, …
func value(at index: Int) -> Int     // → valueAtHandler, valueAtCalls, …
```

## Subscripts

A subscript gets separate getter and setter members:

```swift
subscript(index: Int) -> String { get set }
// → subscriptGetHandler, subscriptSetHandler,
//   subscriptGetCalls, subscriptSetCalls (the setter records the new value)
```

## Whole-mock members

| Member | Purpose |
| --- | --- |
| `mimicInvocations` | a type-safe, ordered log of method calls (`[Invocation]`) |
| `mimicVerify(_:before:)` | assert one method was called before another |
| `mimicReset()` | clear all handlers, stubs, counts, recorded calls, and the log |

## Defaults and traps

A method returning `Optional`, `Array`, `Dictionary`, or `Set` returns an empty value when
unstubbed. Any other non-void method **traps** with a message naming the member if it's
called before a stub is set, so a missing stub fails loudly rather than returning a surprise
default.
