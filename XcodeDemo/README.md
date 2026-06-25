# MimicDemoApp

A minimal SwiftUI **iOS app** that consumes the Mimic package and tests it the way a real
app would — a `WeatherViewModel` whose `WeatherProvider` dependency is replaced by a
Mimic-generated mock in the test target.

- `App/WeatherViewModel.swift` — `@Mockable protocol WeatherProvider` and the view model
- `App/MimicDemoApp.swift`, `App/ContentView.swift` — the runnable app
- `Tests/WeatherViewModelTests.swift` — XCTest cases driving the view model through
  `MockWeatherProvider` (`…ReturnValue`, `…ThrowsError`, `…Returns`, `…Calls`,
  `…WasCalled`, `…LastCall`)

## Run the tests

Open `MimicDemoApp.xcodeproj` in Xcode and press ⌘U, or from the command line:

```sh
xcodebuild test \
  -project MimicDemoApp.xcodeproj \
  -scheme MimicDemoApp \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -skipMacroValidation
```

`-skipMacroValidation` trusts the macro plugin non-interactively (in Xcode you'll instead
get a one-time "trust macro" prompt).

The committed `.xcodeproj` is generated from `project.yml` with
[XcodeGen](https://github.com/yonaskolb/XcodeGen); regenerate with `xcodegen generate`.
