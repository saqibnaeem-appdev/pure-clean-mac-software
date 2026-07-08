import SwiftUI

/// Circular progress gauge used for storage / memory.
struct ProgressRing: View {
    let fraction: Double
    let label: String
    let sublabel: String
    var tint: Color = .accentColor
    var size: CGFloat = 88

    var body: some View {
        ZStack {
            Circle()
                .stroke(.quaternary, lineWidth: 8)
            Circle()
                .trim(from: 0, to: max(0.001, min(1, fraction)))
                .stroke(
                    AngularGradient(
                        colors: [tint.opacity(0.6), tint],
                        center: .center,
                        startAngle: .degrees(-90),
                        endAngle: .degrees(-90 + 360 * fraction)),
                    style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.6), value: fraction)
            VStack(spacing: 1) {
                Text(label)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                Text(sublabel)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
    }
}

/// Small labelled stat tile for the dashboard grid.
struct StatCard: View {
    let icon: String
    let title: String
    let value: String
    var detail: String?
    var tint: Color = .accentColor

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(tint)
                Text(title)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            Text(value)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if let detail {
                Text(detail)
                    .font(.system(size: 9.5))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }
}

/// Section header used inside scrollable pages.
struct SectionHeader: View {
    let title: String
    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
    }
}

/// Prominent gradient action button (Smart Clean, Free Memory…).
struct PrimaryButton: View {
    let title: String
    let icon: String
    var isBusy = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if isBusy {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: icon)
                }
                Text(title).fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background(
                LinearGradient(colors: [.blue, .purple],
                               startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
    }
}

/// Green "done" banner after a clean.
struct ResultBanner: View {
    let result: CleanResult

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 1) {
                Text("Recovered \(result.freedBytes.bytesFormatted)")
                    .font(.system(size: 12, weight: .semibold))
                Text("\(result.removedItems) items cleaned\(result.failedItems > 0 ? " · \(result.failedItems) skipped" : "") — restorable from Trash")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(10)
        .background(.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
    }
}
