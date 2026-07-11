import SwiftUI

// MARK: - Card chrome

struct GlassCardModifier: ViewModifier {
    var padding: CGFloat = 18

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(.ultraThinMaterial,
                        in: RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                    .strokeBorder(.primary.opacity(0.06)))
            .shadow(color: .black.opacity(0.07), radius: 8, y: 3)
    }
}

struct HoverLiftModifier: ViewModifier {
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(hovering ? 1.012 : 1)
            .shadow(color: .black.opacity(hovering ? 0.16 : 0), radius: 14, y: 8)
            .animation(.spring(response: 0.3, dampingFraction: 0.75), value: hovering)
            .onHover { hovering = $0 }
    }
}

extension View {
    /// Standard glass "card" used across the app.
    func glassCard(padding: CGFloat = 18) -> some View {
        modifier(GlassCardModifier(padding: padding))
    }

    /// Subtle lift when the pointer hovers a card.
    func hoverLift() -> some View { modifier(HoverLiftModifier()) }

    /// Animates numeric text changes with the native rolling-digit effect.
    func animatedNumber(_ value: some Equatable) -> some View {
        self
            .contentTransition(.numericText())
            .animation(.snappy(duration: 0.4), value: value)
    }
}

/// Scale-down feedback for custom buttons.
struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7),
                       value: configuration.isPressed)
    }
}

// MARK: - Text pieces

struct SectionLabel: View {
    let title: String
    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .kerning(0.6)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct Badge: View {
    let text: String
    var color: Color = .secondary

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }
}

/// Rounded-square gradient icon used in list rows and card headers.
struct IconBadge: View {
    let systemName: String
    var tint: Color = .blue
    var size: CGFloat = 30

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size * 0.48, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(tint.gradient,
                        in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
    }
}

// MARK: - Metric displays

/// Circular progress gauge with arbitrary center content.
struct MetricRing<Center: View>: View {
    let fraction: Double
    var lineWidth: CGFloat = 9
    var tint: Color = .accentColor
    var size: CGFloat = 96
    @ViewBuilder let center: () -> Center

    var body: some View {
        ZStack {
            Circle()
                .stroke(.quaternary.opacity(0.6), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.003, min(1, fraction)))
                .stroke(
                    AngularGradient(
                        colors: [tint.opacity(0.55), tint],
                        center: .center,
                        startAngle: .degrees(0),
                        endAngle: .degrees(360 * max(0.003, min(1, fraction)))),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.7), value: fraction)
            center()
        }
        .frame(width: size, height: size)
    }
}

/// Thin horizontal level indicator.
struct LevelBar: View {
    let fraction: Double
    var tint: Color = .accentColor
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary.opacity(0.5))
                Capsule()
                    .fill(tint.gradient)
                    .frame(width: max(height, proxy.size.width * min(1, max(0, fraction))))
                    .animation(.easeOut(duration: 0.5), value: fraction)
            }
        }
        .frame(height: height)
    }
}

/// Multi-segment capacity bar (used / purgeable / free…).
struct SegmentBar: View {
    struct Segment: Identifiable {
        let id: String
        let fraction: Double
        let color: Color
    }

    let segments: [Segment]
    var height: CGFloat = 14

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 2) {
                ForEach(segments.filter { $0.fraction > 0.001 }) { segment in
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(segment.color.gradient)
                        .frame(width: max(4, proxy.size.width * segment.fraction))
                }
                Spacer(minLength: 0)
            }
        }
        .frame(height: height)
        .background(.quaternary.opacity(0.4),
                    in: RoundedRectangle(cornerRadius: 4, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        .animation(.easeOut(duration: 0.6), value: segments.map(\.fraction))
    }
}

/// Small labelled stat tile for dashboard grids.
struct StatTile: View {
    let icon: String
    let tint: Color
    let title: String
    let value: String
    var detail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                IconBadge(systemName: icon, tint: tint, size: 24)
                Text(title)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            Text(value)
                .font(Theme.metricMedium())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .animatedNumber(value)
            if let detail {
                Text(detail)
                    .font(Theme.footnote())
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(padding: 14)
        .hoverLift()
    }
}

// MARK: - Buttons

/// Prominent gradient action button (Smart Scan, Clean…).
struct PrimaryGradientButton: View {
    let title: String
    let icon: String
    var isBusy = false
    var fullWidth = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                if isBusy {
                    ProgressView().controlSize(.small).tint(.white)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .semibold))
                }
                Text(title)
                    .font(.system(size: 13.5, weight: .semibold))
            }
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .padding(.horizontal, 20)
            .padding(.vertical, 11)
            .background(
                Theme.brandGradient,
                in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(.white.opacity(0.18)))
            .foregroundStyle(.white)
            .shadow(color: .blue.opacity(0.3), radius: 8, y: 4)
        }
        .buttonStyle(PressableButtonStyle())
        .disabled(isBusy)
    }
}

// MARK: - Banners

/// Green "done" banner after a clean.
struct ResultBanner: View {
    let result: CleanResult

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 18))
                .foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 1) {
                Text("Recovered \(result.freedBytes.bytesFormatted)")
                    .font(.system(size: 12.5, weight: .semibold))
                Text("\(result.removedItems) items cleaned\(result.failedItems > 0 ? " · \(result.failedItems) skipped" : "")")
                    .font(Theme.footnote())
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(12)
        .background(.green.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - Page scaffold

/// Standard page header with title, subtitle and trailing accessory.
struct PageHeader<Accessory: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var accessory: () -> Accessory

    init(_ title: String, subtitle: String? = nil,
         @ViewBuilder accessory: @escaping () -> Accessory = { EmptyView() }) {
        self.title = title
        self.subtitle = subtitle
        self.accessory = accessory
    }

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(Theme.pageTitle())
                if let subtitle {
                    Text(subtitle)
                        .font(Theme.body())
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            accessory()
        }
    }
}
