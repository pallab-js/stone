import AppKit
import SwiftUI

enum DS {
    enum Color {
        static let accent = SwiftUI.Color(red: 0.851, green: 0.510, blue: 0.169)
        static let accentStrong = SwiftUI.Color(red: 0.729, green: 0.412, blue: 0.110)
        static let accentSoft = accent.opacity(0.14)

        static let success = SwiftUI.Color(red: 0.184, green: 0.620, blue: 0.267)
        static let danger = SwiftUI.Color(red: 0.878, green: 0.192, blue: 0.192)
        static let warning = SwiftUI.Color(red: 0.941, green: 0.549, blue: 0.000)
        static let info = SwiftUI.Color(red: 0.110, green: 0.494, blue: 0.839)

        static let sidebar = SwiftUI.Color(red: 0.063, green: 0.094, blue: 0.145)
        static let sidebarText = SwiftUI.Color.white.opacity(0.92)
        static let sidebarMuted = SwiftUI.Color.white.opacity(0.55)

        static let contentBackground = SwiftUI.Color(nsColor: .textBackgroundColor)
        static let cardBackground = SwiftUI.Color(nsColor: .controlBackgroundColor)
        static let hairline = SwiftUI.Color(nsColor: .separatorColor)

        static func status(_ isActive: Bool) -> SwiftUI.Color {
            isActive ? success : danger
        }
    }

    enum Font {
        static func system(
            _ size: CGFloat,
            weight: SwiftUI.Font.Weight = .regular,
            design: SwiftUI.Font.Design = .default,
            mono: Bool = false
        ) -> SwiftUI.Font {
            let base = SwiftUI.Font.system(size: size, weight: weight, design: design)
            return mono ? base.monospacedDigit() : base
        }

        static let pageTitle = system(22, weight: .semibold)
        static let sectionTitle = system(15, weight: .semibold)
        static let groupLabel = system(11, weight: .semibold)
        static let kpiValue = system(30, weight: .bold, design: .rounded, mono: true)
        static let kpiUnit = system(13, weight: .semibold)
        static let body = system(13)
        static let bodySemibold = system(13, weight: .semibold)
        static let caption = system(12)
        static let captionMono = system(12, mono: true)
        static let tableValue = system(13, mono: true)
        static let footnote = system(11)
    }

    enum Spacing {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 22
        static let xxl: CGFloat = 30
        static let huge: CGFloat = 44
    }

    enum Radius {
        static let small: CGFloat = 6
        static let standard: CGFloat = 10
        static let large: CGFloat = 14
    }

    enum SheetWidth {
        static let editor: CGFloat = 520
        static let editorWide: CGFloat = 620
    }
}