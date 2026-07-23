import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

@main
struct Porta424App: App {
    @State private var viewModel = TapeDeckViewModel()

    var body: some Scene {
        WindowGroup {
            rootView
                .environment(viewModel)
                .preferredColorScheme(.light)
                .task {
                    await viewModel.boot()
                }
        }
    }

    @ViewBuilder
    private var rootView: some View {
        #if os(iOS)
        if UIDevice.current.userInterfaceIdiom == .pad {
            iPadTapeDeckView()
        } else {
            TapeDeckView()
        }
        #else
        // macOS / other: use the full tape-deck layout in a resizable window.
        TapeDeckView()
            .frame(minWidth: 900, minHeight: 560)
        #endif
    }
}
