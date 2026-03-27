import SwiftUI

@main
struct Porta424App: App {
    @State private var viewModel = TapeDeckViewModel()

    var body: some Scene {
        WindowGroup {
            TapeDeckView()
                .environment(viewModel)
                .preferredColorScheme(.light)
                .task {
                    await viewModel.boot()
                }
        }
    }
}
