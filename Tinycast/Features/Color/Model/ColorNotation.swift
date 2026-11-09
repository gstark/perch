import Foundation

/// The notation a colour is copied in by default. See docs/features/colors.md#notation.
enum ColorNotation: String, CaseIterable, Identifiable, Sendable {
    case hex
    case rgb
    case hsl
    case oklch

    var id: Self { self }

    var title: String {
        switch self {
        case .hex: return "Hex"
        case .rgb: return "RGB"
        case .hsl: return "HSL"
        case .oklch: return "Oklch"
        }
    }

    /// The format a colour is stated and copied in: alpha picks the spelling, never the user.
    func format(for color: ColorValue) -> ColorFormat {
        switch self {
        case .hex: return color.hasAlpha ? .hexWithAlpha : .hex
        case .rgb: return .rgba
        case .hsl: return color.hasAlpha ? .hslWithAlpha : .hsl
        case .oklch: return .oklch
        }
    }
}
