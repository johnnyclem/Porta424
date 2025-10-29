import SwiftUI

struct MasterSectionView: View {
    @EnvironmentObject var viewModel: Porta424ViewModel

    var body: some View {
        VStack(spacing: 12) {
            Text("MASTER")
                .font(.caption)
                .opacity(0.8)

            HStack(spacing: 12) {
                VStack {
                    Text("EFFECT RETURN")
                        .font(.caption2)
                    HStack(spacing: 10) {
                        RotaryKnob(value: $viewModel.master.effectReturn1, title: "1", size: 40)
                        RotaryKnob(value: $viewModel.master.effectReturn2, title: "2", size: 40)
                    }
                }
                VerticalFader(value: $viewModel.master.stereoFader, label: "STEREO")
                    .frame(width: 72)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(red: 0.10, green: 0.18, blue: 0.28))
                .shadow(color: .black.opacity(0.35), radius: 6, x: 0, y: 4)
        )
        .foregroundStyle(.white)
    }
}
