import SwiftUI

enum DreamTheme {
    static let blue      = Color(hex: 0x5BBBDE)
    static let blueDeep  = Color(hex: 0x3A9DC4)
    static let blueSoft  = Color(hex: 0xE5F4FA)
    static let blueTint  = Color(hex: 0xF4FAFD)

    static let ink   = Color(hex: 0x15191D)
    static let ink2  = Color(hex: 0x56636C)
    static let ink3  = Color(hex: 0x8E99A2)
    static let line  = Color(hex: 0xE8ECEE)
    static let error = Color(hex: 0xB83D45)

    static let bg     = Color(hex: 0xFAF8F4)
    static let cream  = Color(hex: 0xF6F1E8)
    static let warm   = Color(hex: 0xEFE6D6)
    static let paper  = Color(hex: 0xFBF8F2)

    enum Layout {
        static let tabBarClearance: CGFloat = 132
    }

    enum Font {
        static func display(_ size: CGFloat, weight: SwiftUI.Font.Weight = .regular, italic: Bool = false) -> SwiftUI.Font {
            let base = SwiftUI.Font.system(size: size, weight: weight, design: .serif)
            return italic ? base.italic() : base
        }
        static func text(_ size: CGFloat, weight: SwiftUI.Font.Weight = .regular) -> SwiftUI.Font {
            .system(size: size, weight: weight, design: .default)
        }
    }
}

struct CategoryPalette {
    let fg: Color
    let bg: Color
    let tint: Color
}

enum DreamCategory: String, CaseIterable, Hashable {
    case tech = "Tech"
    case food = "Food"
    case art = "Art"
    case impact = "Social Impact"
    case education = "Education"
    case health = "Health"
    case music = "Music"
    case sport = "Sport"

    var palette: CategoryPalette {
        switch self {
        case .tech:      return .init(fg: .init(hex: 0x2D6FA8), bg: .init(hex: 0xDEEAF4), tint: .init(hex: 0xF4F8FB))
        case .food:      return .init(fg: .init(hex: 0xC8632B), bg: .init(hex: 0xF4DCC8), tint: .init(hex: 0xFBF1E7))
        case .art:       return .init(fg: .init(hex: 0xA23F87), bg: .init(hex: 0xF0D5E5), tint: .init(hex: 0xFBF0F6))
        case .impact:    return .init(fg: .init(hex: 0x2F7A52), bg: .init(hex: 0xD4E8DA), tint: .init(hex: 0xF0F7F2))
        case .education: return .init(fg: .init(hex: 0xB07908), bg: .init(hex: 0xF4E4B8), tint: .init(hex: 0xFBF6E7))
        case .health:    return .init(fg: .init(hex: 0xB83D45), bg: .init(hex: 0xF4D2D4), tint: .init(hex: 0xFBEEEF))
        case .music:     return .init(fg: .init(hex: 0x5740A8), bg: .init(hex: 0xDDD3F0), tint: .init(hex: 0xF2EEFB))
        case .sport:     return .init(fg: .init(hex: 0x1A8588), bg: .init(hex: 0xC9E4E5), tint: .init(hex: 0xEBF6F6))
        }
    }
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8)  & 0xFF) / 255
        let b = Double( hex        & 0xFF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }
}
