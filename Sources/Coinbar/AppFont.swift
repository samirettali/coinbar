import AppKit
import SwiftUI

enum AppFont {
    private static let preferredFontName = "JetBrainsMono Nerd Font"

    static func uiFont(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        if NSFont(name: preferredFontName, size: size) != nil {
            return .custom(preferredFontName, size: size).weight(weight)
        }

        return .system(size: size, weight: weight, design: .monospaced)
    }
}
