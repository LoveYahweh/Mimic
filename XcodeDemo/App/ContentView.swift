import SwiftUI

struct ContentView: View {
    @StateObject var viewModel: WeatherViewModel
    @State private var city: String = ""

    var body: some View {
        VStack(spacing: 20) {
            Text("Mimic Demo")
                .font(.largeTitle.bold())

            Text(viewModel.status)
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            TextField("City", text: $city)
                .textFieldStyle(.roundedBorder)

            Button("Load") {
                Task { await viewModel.load(city: city) }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}
