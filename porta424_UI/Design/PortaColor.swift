//
//  PortaColor.swift
//  porta424_UI
//
//  Created by John Clem on 10/22/25.
//

import SwiftUI

extension Color {
    init(hex: String) {
        // Trim to alphanumerics so we can accept strings like "#FF00AA" or "0xFF00AA"
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)

        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            // Expand each 4-bit component to 8-bit by multiplying by 17
            (a, r, g, b) = (
                255,
                (int >> 8) * 17,
                ((int >> 4) & 0xF) * 17,
                (int & 0xF) * 17
            )
        case 6: // RRGGBB (24-bit)
            (a, r, g, b) = (
                255,
                (int >> 16) & 0xFF,
                (int >> 8) & 0xFF,
                int & 0xFF
            )
        case 8: // AARRGGBB (32-bit)
            (a, r, g, b) = (
                (int >> 24) & 0xFF,
                (int >> 16) & 0xFF,
                (int >> 8) & 0xFF,
                int & 0xFF
            )
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255.0,
            green: Double(g) / 255.0,
            blue: Double(b) / 255.0,
            opacity: Double(a) / 255.0
        )
    }
}

struct PortaColor {
    static let background = Color(hex: "1E1F24")
    static let surface = Color(hex: "2C2D33")
    static let accentTeal = Color(hex: "00C2B8")
    static let accentOrange = Color(hex: "FF6B35")
    static let accentRed = Color(hex: "FF3B30")
    static let meterGreen = Color(hex: "00FF85")
    static let meterYellow = Color(hex: "FFD60A")
    static let meterRed = Color(hex: "FF3B30")
}
