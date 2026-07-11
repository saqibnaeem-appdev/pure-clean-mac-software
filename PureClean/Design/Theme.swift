import SwiftUI

/// Central design tokens so every screen shares the same visual language.
enum Theme {

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

    static let corner: CGFloat = 16
    static let cornerSmall: CGFloat = 10
    static let pagePadding: CGFloat = 24
    static let gridSpacing: CGFloat = 14

    // MARK: - Typography

    static func pageTitle() -> Font { .system(size: 24, weight: .bold) }
    static func cardTitle() -> Font { .system(size: 13, weight: .semibold) }
    static func metricLarge() -> Font { .system(size: 28, weight: .bold, design: .rounded) }
    static func metricMedium() -> Font { .system(size: 17, weight: .bold, design: .rounded) }
    static func body() -> Font { .system(size: 12.5) }
    static func caption() -> Font { .system(size: 11) }
    static func footnote() -> Font { .system(size: 10) }
}
