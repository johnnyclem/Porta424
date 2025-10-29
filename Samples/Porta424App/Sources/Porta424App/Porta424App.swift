import SwiftUI
import Porta424AudioEngine

@main
struct Porta424App: App {
    @StateObject private var viewModel = Porta424ViewModel()

    var body: some Scene {
        WindowGroup {
            Porta424BoardView()
                .environmentObject(viewModel)
                .onAppear {
                    do {
                        try Porta424Engine.shared.start()
                        viewModel.attachEngine(Porta424Engine.shared)
                    } catch {
                        print("Audio engine failed to start: \(error)")
                    }
                }
        }
        .commands {
            CommandMenu("Transport") {
                Button("Play / Pause") { viewModel.enginePlayPause() }
                    .keyboardShortcut(.space, modifiers: [])
                Button("Stop") { viewModel.engineStop() }
                    .keyboardShortcut("S", modifiers: [.command])
                Button("Record Arm 1") { viewModel.toggleRecordArm(track: 1) }
                    .keyboardShortcut("1", modifiers: [.command, .shift])
                Button("Record Arm 2") { viewModel.toggleRecordArm(track: 2) }
                    .keyboardShortcut("2", modifiers: [.command, .shift])
                Button("Record Arm 3") { viewModel.toggleRecordArm(track: 3) }
                    .keyboardShortcut("3", modifiers: [.command, .shift])
                Button("Record Arm 4") { viewModel.toggleRecordArm(track: 4) }
                    .keyboardShortcut("4", modifiers: [.command, .shift])
            }
        }
    }
}
