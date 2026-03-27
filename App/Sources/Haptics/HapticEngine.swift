import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Centralized haptic feedback for the tape deck UI.
/// Uses UIKit haptics on iOS, no-ops gracefully elsewhere.
@MainActor
enum HapticEngine {

    // MARK: - Transport actions
    static func transportTap() {
        #if canImport(UIKit) && !os(macOS)
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred(intensity: 0.8)
        #endif
    }

    static func recordEngage() {
        #if canImport(UIKit) && !os(macOS)
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.warning)
        #endif
    }

    // MARK: - Knob / fader interactions
    static func knobDetent() {
        #if canImport(UIKit) && !os(macOS)
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred(intensity: 0.4)
        #endif
    }

    static func knobTick() {
        #if canImport(UIKit) && !os(macOS)
        let generator = UISelectionFeedbackGenerator()
        generator.selectionChanged()
        #endif
    }

    static func faderSnap() {
        #if canImport(UIKit) && !os(macOS)
        let generator = UIImpactFeedbackGenerator(style: .rigid)
        generator.impactOccurred(intensity: 0.3)
        #endif
    }

    // MARK: - Preset / UI
    static func presetSelect() {
        #if canImport(UIKit) && !os(macOS)
        let generator = UIImpactFeedbackGenerator(style: .soft)
        generator.impactOccurred(intensity: 0.5)
        #endif
    }

    static func buttonPress() {
        #if canImport(UIKit) && !os(macOS)
        let generator = UIImpactFeedbackGenerator(style: .rigid)
        generator.impactOccurred(intensity: 0.6)
        #endif
    }
}
