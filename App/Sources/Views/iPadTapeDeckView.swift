import SwiftUI

/// iPad-specific tape deck interface with a persistent side drawer layout.
///
/// Layout (landscape — primary):
/// ┌──────────────┬──────────────────────────────────┐
/// │  Side Drawer │         Main Tape Deck            │
/// │   (1/3 w)    │           (2/3 w)                 │
/// │              │  ┌──────────────────────────────┐ │
/// │  • Effects   │  │  VU-L   [Cassette Window]  VU-R│
/// │  • Presets   │  │         [Tape Counter]        │ │
/// │  • Tapes     │  │      [Transport Controls]     │ │
/// │  • Faders    │  └──────────────────────────────┘ │
/// └──────────────┴──────────────────────────────────┘
///
/// Supports all 4 orientations. In portrait, the drawer collapses into a
/// slide-over that can be toggled via a handle button.
struct iPadTapeDeckView: View {
    @Environment(TapeDeckViewModel.self) var viewModel

    @State private var isDrawerOpen = true
    @State private var drawerDragOffset: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            let isLandscape = geo.size.width > geo.size.height
            let drawerWidth = isLandscape
                ? geo.size.width / 3
                : min(340, geo.size.width * 0.75)

            ZStack(alignment: .leading) {
                // Chassis background (full screen)
                chassisBackground

                if isLandscape {
                    // Landscape: persistent side-by-side
                    landscapeLayout(geo: geo, drawerWidth: drawerWidth)
                } else {
                    // Portrait: main deck full-width with slide-over drawer
                    portraitLayout(geo: geo, drawerWidth: drawerWidth)
                }
            }
            .ignoresSafeArea(edges: .all)
            .onChange(of: viewModel.dsp) { _, _ in
                viewModel.syncDSP()
            }
            .onChange(of: isLandscape) { _, newValue in
                // Auto-open drawer when rotating to landscape
                if newValue { isDrawerOpen = true }
            }
        }
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
    }

    // MARK: - Landscape Layout (Primary)

    private func landscapeLayout(geo: GeometryProxy, drawerWidth: CGFloat) -> some View {
        HStack(spacing: 0) {
            // Left: Side drawer (1/3)
            SideDrawerView(viewModel: viewModel)
                .frame(width: drawerWidth)

            // Divider rail
            drawerDivider

            // Right: Main tape deck (2/3)
            mainTapeDeck(geo: geo)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Portrait Layout

    private func portraitLayout(geo: GeometryProxy, drawerWidth: CGFloat) -> some View {
        ZStack(alignment: .leading) {
            // Main deck takes full width
            VStack(spacing: 0) {
                // Drawer toggle in top-left
                portraitToolbar

                mainTapeDeckPortrait(geo: geo)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            // Slide-over drawer
            if isDrawerOpen {
                // Scrim
                Color.black.opacity(0.35)
                    .ignoresSafeArea()
                    .onTapGesture { withAnimation(.spring(response: 0.35)) { isDrawerOpen = false } }
                    .transition(.opacity)

                // Drawer panel
                HStack(spacing: 0) {
                    SideDrawerView(viewModel: viewModel)
                        .frame(width: drawerWidth)
                        .background(Porta.chassis)
                        .shadow(color: .black.opacity(0.3), radius: 12, x: 4, y: 0)
                        .offset(x: drawerDragOffset)
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    drawerDragOffset = min(0, value.translation.width)
                                }
                                .onEnded { value in
                                    if value.translation.width < -80 {
                                        withAnimation(.spring(response: 0.35)) {
                                            isDrawerOpen = false
                                            drawerDragOffset = 0
                                        }
                                    } else {
                                        withAnimation(.spring(response: 0.25)) {
                                            drawerDragOffset = 0
                                        }
                                    }
                                }
                        )
                        .transition(.move(edge: .leading))

                    Spacer()
                }
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: isDrawerOpen)
    }

    private var portraitToolbar: some View {
        HStack {
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    isDrawerOpen.toggle()
                }
                HapticEngine.buttonPress()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isDrawerOpen ? "xmark" : "sidebar.left")
                        .font(.system(size: 14, weight: .semibold))
                    if !isDrawerOpen {
                        Text("DRAWER")
                            .font(.system(size: 10, weight: .heavy, design: .rounded))
                            .tracking(1)
                    }
                }
                .foregroundStyle(Porta.label)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Porta.panel)
                        .shadow(color: Porta.softShadow, radius: 2, y: 1)
                )
            }
            .buttonStyle(.plain)

            Spacer()

            // Header in portrait
            VStack(spacing: 1) {
                Text("PORTA424")
                    .font(.system(size: 20, weight: .black, design: .rounded))
                    .foregroundStyle(Porta.label)
            }

            Spacer()

            // Balance the layout
            Color.clear
                .frame(width: 80, height: 1)
        }
        .padding(.horizontal, 16)
        .padding(.top, 56) // Safe area for status bar / Dynamic Island
        .padding(.bottom, 8)
    }

    // MARK: - Main Tape Deck (Landscape)

    private func mainTapeDeck(geo: GeometryProxy) -> some View {
        VStack(spacing: 0) {
            Spacer()

            // Top row: VU meters flanking the cassette
            HStack(spacing: 16) {
                // Left VU meter
                VUMeterView(value: viewModel.meterL, channel: "L")
                    .frame(maxWidth: 120)

                // Cassette window (hero element)
                VStack(spacing: 12) {
                    CassetteView(
                        transportMode: viewModel.transportMode,
                        tapePosition: viewModel.tapePosition
                    )
                    .padding(10)
                    .portaPanel(cornerRadius: 12)
                }
                .frame(maxWidth: .infinity)

                // Right VU meter
                VUMeterView(value: viewModel.meterR, channel: "R")
                    .frame(maxWidth: 120)
            }
            .padding(.horizontal, 24)

            Spacer().frame(height: 16)

            // Tape counter
            TapeCounterView(
                counterText: viewModel.counterString,
                isRunning: viewModel.isTransportActive,
                onReset: { viewModel.resetCounter() }
            )

            Spacer().frame(height: 16)

            // Transport controls — wider on iPad
            iPadTransportBar

            Spacer()

            // Corner screws
            HStack {
                Porta.Screw()
                Spacer()
                Porta.Screw()
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
        .padding(.horizontal, 12)
    }

    // MARK: - Main Tape Deck (Portrait)

    private func mainTapeDeckPortrait(geo: GeometryProxy) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 20) {
                // VU + Cassette
                HStack(spacing: 12) {
                    VUMeterView(value: viewModel.meterL, channel: "L")
                    CassetteView(
                        transportMode: viewModel.transportMode,
                        tapePosition: viewModel.tapePosition
                    )
                    .padding(8)
                    .portaPanel(cornerRadius: 10)
                    VUMeterView(value: viewModel.meterR, channel: "R")
                }

                // Tape counter
                TapeCounterView(
                    counterText: viewModel.counterString,
                    isRunning: viewModel.isTransportActive,
                    onReset: { viewModel.resetCounter() }
                )

                // Transport
                iPadTransportBar

                // DSP knobs inline for portrait (since drawer is hidden)
                DSPKnobsPanel(viewModel: viewModel)

                // Faders
                HStack(spacing: 24) {
                    RetroFader(
                        value: Bindable(viewModel).dsp.inputGain,
                        label: "INPUT\nGAIN",
                        capColor: Porta.faderCapOrange,
                        height: 130,
                        meterValue: viewModel.meterL
                    )
                    .frame(width: 50)

                    RetroFader(
                        value: Bindable(viewModel).dsp.masterVolume,
                        label: "MASTER\nVOLUME",
                        capColor: Porta.faderCapGreen,
                        height: 130,
                        meterValue: viewModel.meterR
                    )
                    .frame(width: 50)
                }

                PresetPickerButton(viewModel: viewModel)
            }
            .padding(20)
        }
    }

    // MARK: - iPad Transport Bar (larger touch targets)

    private var iPadTransportBar: some View {
        HStack(spacing: 14) {
            RetroTransportButton(
                icon: "backward.fill",
                label: "REW",
                color: Porta.transportBlue,
                isActive: viewModel.transportMode == .rewinding
            ) {
                viewModel.rewind()
            }

            RetroTransportButton(
                icon: "forward.fill",
                label: "FF",
                color: Porta.transportBlue,
                isActive: viewModel.transportMode == .fastForwarding
            ) {
                viewModel.fastForward()
            }

            RetroTransportButton(
                icon: "stop.fill",
                label: "STOP",
                color: Porta.transportOrange,
                isActive: viewModel.transportMode == .stopped
            ) {
                viewModel.stop()
            }

            RetroTransportButton(
                icon: viewModel.transportMode == .paused ? "pause.fill" : "play.fill",
                label: "PLAY",
                color: Porta.transportGreen,
                isActive: viewModel.transportMode == .playing || viewModel.transportMode == .recording
            ) {
                viewModel.togglePlay()
            }

            RetroTransportButton(
                icon: "circle.fill",
                label: "REC",
                color: Porta.transportRed,
                isActive: viewModel.transportMode == .recording
            ) {
                viewModel.toggleRecord()
            }
        }
        .scaleEffect(1.15) // Slightly larger transport buttons for iPad
    }

    // MARK: - Divider Rail

    private var drawerDivider: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [
                        Porta.bezel.opacity(0.3),
                        Porta.bezel.opacity(0.6),
                        Porta.bezel.opacity(0.3)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(width: 2)
            .shadow(color: Porta.deepShadow, radius: 2, x: 1, y: 0)
    }

    // MARK: - Background

    private var chassisBackground: some View {
        ZStack {
            Porta.chassis.ignoresSafeArea()

            Canvas { context, size in
                for _ in 0..<400 {
                    let x = Double.random(in: 0..<size.width)
                    let y = Double.random(in: 0..<size.height)
                    let opacity = Double.random(in: 0.01...0.04)
                    context.fill(
                        Path(CGRect(x: x, y: y, width: 1, height: 1)),
                        with: .color(.black.opacity(opacity))
                    )
                }
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)

            // Corner screws (top only — bottom screws in main deck)
            VStack {
                HStack {
                    Porta.Screw()
                    Spacer()
                    Porta.Screw()
                }
                Spacer()
            }
            .padding(12)
        }
    }
}
