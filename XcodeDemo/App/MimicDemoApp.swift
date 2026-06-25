import SwiftUI

/// A live provider so the app runs standalone. The interesting logic lives in
/// `WeatherViewModel`, which is what the tests cover (through a mock).
private struct LiveWeatherProvider: WeatherProvider {
    func temperature(for city: String) async throws -> Int {
        // Deterministic stand-in for a network call.
        60 + abs(city.hashValue % 40)
    }
}

@main
struct MimicDemoApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: WeatherViewModel(provider: LiveWeatherProvider()))
        }
    }
}
