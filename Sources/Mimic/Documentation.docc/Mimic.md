# ``Mimic``

Macro-driven mocks for Swift unit tests — with zero third-party runtime dependencies.

## Overview

Annotate a protocol with ``Mockable()`` and Mimic generates a `Mock<Name>` test double, at
compile time, that records every call and lets you stub behaviour with a closure. There's no
reflection, no separate code-generation step, and nothing third-party in your app or test
binary — `swift-syntax` runs only inside the macro plugin while you build.

```swift
import Mimic

@Mockable
protocol WeatherService {
    var lastCity: String? { get }
    func temperature(in city: String) async throws -> Double
}

let mock = MockWeatherService()
mock.temperatureReturnValue = 72
#expect(try await mock.temperature(in: "Paris") == 72)
#expect(mock.temperatureCalls == ["Paris"])
```

The generated members aren't ordinary symbols, so they can't appear in this reference
directly — see <doc:GeneratedAPI> for the full naming scheme.

## Topics

### Essentials

- ``Mockable()``
- <doc:GettingStarted>

### Guides

- <doc:Stubbing>
- <doc:GeneratedAPI>
