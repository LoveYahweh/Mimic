import XCTest
import Mimic
@testable import MimicDemoApp

/// These tests drive `WeatherViewModel` entirely through `MockWeatherProvider`,
/// which Mimic generated from the `@Mockable protocol WeatherProvider` in the app
/// target. This is the whole point of the package: real app, mocked dependency.
@MainActor
final class WeatherViewModelTests: XCTestCase {

    func testSuccessFormatsTemperature() async {
        let mock = MockWeatherProvider()
        mock.temperatureReturnValue = 72                 // …ReturnValue shorthand

        let viewModel = WeatherViewModel(provider: mock)
        await viewModel.load(city: "London")

        XCTAssertEqual(viewModel.status, "London: 72°")
        XCTAssertEqual(mock.temperatureCalls, ["London"])   // argument recording
        XCTAssertEqual(mock.temperatureCallCount, 1)
    }

    func testFailureShowsFallback() async {
        struct Offline: Error {}
        let mock = MockWeatherProvider()
        mock.temperatureThrowsError(Offline())           // …ThrowsError convenience

        let viewModel = WeatherViewModel(provider: mock)
        await viewModel.load(city: "London")

        XCTAssertEqual(viewModel.status, "Couldn't load London")
    }

    func testEmptyCityNeverCallsProvider() async {
        let mock = MockWeatherProvider()

        let viewModel = WeatherViewModel(provider: mock)
        await viewModel.load(city: "   ")

        XCTAssertEqual(viewModel.status, "Enter a city")
        XCTAssertFalse(mock.temperatureWasCalled)        // interaction assertion
    }

    func testSequentialReturnsAcrossCalls() async {
        let mock = MockWeatherProvider()
        mock.temperatureReturns(50, 60)                  // sequential stubbing

        let viewModel = WeatherViewModel(provider: mock)
        await viewModel.load(city: "A")
        XCTAssertEqual(viewModel.status, "A: 50°")
        await viewModel.load(city: "B")
        XCTAssertEqual(viewModel.status, "B: 60°")
        XCTAssertEqual(mock.temperatureLastCall, "B")
    }
}
