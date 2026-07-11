import SwiftUI
import CoreText

/// Central design tokens so every screen shares the same visual language.
enum Theme {

    // MARK: - Display typeface (Bricolage Grotesque, bundled)

    enum DisplayWeight: String {
        case regular = "BricolageGrotesque-Regular"
        case medium = "BricolageGrotesque-Medium"
        case semibold = "BricolageGrotesque-SemiBold"
        case bold = "BricolageGrotesque-Bold"
        case extrabold = "BricolageGrotesque-ExtraBold"
    }

    /// Headline/metric typeface. `Font.custom` falls back to the system
    /// font automatically if registration ever fails.
    static func display(_ size: CGFloat, _ weight: DisplayWeight = .bold) -> Font {
        Font.custom(weight.rawValue, size: size)
    }

    /// Registers the bundled TTFs for this process. Call once at startup.
    static func registerFonts() {
        guard let urls = Bundle.main.urls(forResourcesWithExtension: "ttf",
                                          subdirectory: nil) else { return }
        for url in urls {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }

    // MARK: - Color

    static let brandColors: [Color] = [.blue, .purple]

    static var brandGradient: LinearGradient {
        LinearGradient(colors: brandColors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    static var brandGradientHorizontal: LinearGradient {
        LinearGradient(colors: brandColors, startPoint: .leading, endPoint: .trailing)
    }

    /// Categorical palette for donut charts / folder breakdowns.
    static let palette: [Color] = [
        .blue, .purple, .pink, .orange, .yellow, .green, .teal, .indigo, .red,
    ]

    // MARK: - Metrics

    static let corner: CGFloat = 18
    static let cornerSmall: CGFloat = 10
    static let pagePadding: CGFloat = 26
    static let gridSpacing: CGFloat = 16

    // MARK: - Typography

    static func pageTitle() -> Font { display(28, .bold) }
    static func cardTitle() -> Font { .system(size: 13, weight: .semibold) }
    static func metricLarge() -> Font { display(32, .bold) }
    static func metricMedium() -> Font { display(18, .semibold) }
    static func body() -> Font { .system(size: 13) }
    static func caption() -> Font { .system(size: 11.5) }
    static func footnote() -> Font { .system(size: 10.5) }
}
