//
//  PortaFont.swift
//  porta424_UI
//
//  Created by John Clem on 10/22/25.
//

import SwiftUI

struct PortaFont {
    static func title() -> Font { .system(size: 32, weight: .bold, design: .rounded) }
    static func label() -> Font { .system(size: 14, weight: .semibold, design: .rounded) }
    static func button() -> Font { .system(size: 16, weight: .bold, design: .rounded) }
    static func tapeLabel() -> Font { .system(size: 18, weight: .black, design: .monospaced) }
}

extension PortaFont {
    static func meterLabel() -> Font {
        .system(size: 10, weight: .medium, design: .monospaced)
    }
}
