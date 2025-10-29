import SwiftUI

struct Porta424BoardView: View {
    @EnvironmentObject var viewModel: Porta424ViewModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.09, green: 0.16, blue: 0.26),
                        Color(red: 0.11, green: 0.18, blue: 0.30)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                VStack(alignment: .leading, spacing: 16) {
                    Text("TASCAM‑style Porta424")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.92))
                        .padding(.top, 12)

                    HStack(alignment: .top, spacing: 14) {
                        ForEach($viewModel.channels) { $channel in
                            ChannelStripView(channel: $channel)
                                .frame(width: 160)
                        }

                        MasterSectionView()
                            .frame(width: 160)

                        TransportSectionView()
                            .frame(width: 420)
                    }
                    .padding(.horizontal)
                }
                .padding(.bottom, 24)
            }
        }
    }
}
