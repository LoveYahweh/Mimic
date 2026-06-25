import Foundation
import Mimic

/// The app's one external dependency — annotated so the test target gets a mock
/// for free. In a real app this would wrap a network call.
@Mockable
protocol WeatherProvider {
    func temperature(for city: String) async throws -> Int
}

/// Drives the screen. All of its behaviour is exercised in `MimicDemoAppTests`
/// with a `MockWeatherProvider` injected in place of the live one.
@MainActor
final class WeatherViewModel: ObservableObject {
    @Published private(set) var status: String = "Enter a city"

    private let provider: WeatherProvider

    init(provider: WeatherProvider) {
        self.provider = provider
    }

    func load(city: String) async {
        let trimmed = city.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            status = "Enter a city"
            return
        }
        status = "Loading \(trimmed)…"
        do {
            let degrees = try await provider.temperature(for: trimmed)
            status = "\(trimmed): \(degrees)°"
        } catch {
            status = "Couldn't load \(trimmed)"
        }
    }
}
