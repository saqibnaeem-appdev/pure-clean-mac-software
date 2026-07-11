import SwiftUI
import Charts

/// Smooth area+line history chart used for CPU / memory sparklines
/// (values expected in 0…1) and, with `yDomain: nil`, for throughput.
struct HistoryChart: View {
    let values: [Double]
    var tint: Color = .blue
    /// Fixed domain (e.g. 0…1 for percentages). nil auto-scales.
    var yDomain: ClosedRange<Double>? = 0...1
    var height: CGFloat = 70
    var showsAxis = false

    private var domain: ClosedRange<Double> {
        if let yDomain { return yDomain }
        let top = max(values.max() ?? 1, 1)
        return 0...(top * 1.25)
    }

    var body: some View {
        Chart(Array(values.enumerated()), id: \.offset) { index, value in
            AreaMark(x: .value("t", index), y: .value("v", value))
                .foregroundStyle(
                    LinearGradient(colors: [tint.opacity(0.32), tint.opacity(0.02)],
                                   startPoint: .top, endPoint: .bottom))
                .interpolationMethod(.catmullRom)
            LineMark(x: .value("t", index), y: .value("v", value))
                .foregroundStyle(tint.gradient)
                .interpolationMethod(.catmullRom)
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
        }
        .chartYScale(domain: domain)
        .chartXScale(domain: 0...59)
        .chartXAxis(.hidden)
        .chartYAxis {
            if showsAxis {
                AxisMarks(values: .automatic(desiredCount: 3)) { _ in
                    AxisGridLine().foregroundStyle(.quaternary)
                }
            }
        }
        .frame(height: height)
        .animation(.linear(duration: 0.4), value: values)
    }
}

/// Two overlaid histories (network down/up, disk read/write), auto-scaled
/// to the larger series.
struct DualHistoryChart: View {
    struct Series: Identifiable {
        let id: String
        let values: [Double]
        let tint: Color
    }

    let series: [Series]
    var height: CGFloat = 70

    private var domain: ClosedRange<Double> {
        let top = series.flatMap(\.values).max() ?? 1
        return 0...(max(top, 1) * 1.25)
    }

    var body: some View {
        Chart {
            ForEach(series) { line in
                ForEach(Array(line.values.enumerated()), id: \.offset) { index, value in
                    AreaMark(x: .value("t", index), y: .value("v", value),
                             series: .value("series", line.id))
                        .foregroundStyle(
                            LinearGradient(colors: [line.tint.opacity(0.22), .clear],
                                           startPoint: .top, endPoint: .bottom))
                        .interpolationMethod(.catmullRom)
                    LineMark(x: .value("t", index), y: .value("v", value),
                             series: .value("series", line.id))
                        .foregroundStyle(line.tint.gradient)
                        .interpolationMethod(.catmullRom)
                        .lineStyle(StrokeStyle(lineWidth: 1.8, lineCap: .round))
                }
            }
        }
        .chartYScale(domain: domain)
        .chartXScale(domain: 0...59)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .frame(height: height)
        .animation(.linear(duration: 0.4), value: series.map(\.values))
    }
}

/// Compact vertical bars for per-core CPU activity.
struct CoreActivityBars: View {
    let values: [Double]
    var tint: Color = .cyan
    var height: CGFloat = 40

    var body: some View {
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(Array(values.enumerated()), id: \.offset) { _, value in
                VStack {
                    Spacer(minLength: 0)
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(tint.gradient.opacity(0.45 + 0.55 * value))
                        .frame(height: max(3, height * value))
                }
            }
        }
        .frame(height: height)
        .animation(.easeOut(duration: 0.5), value: values)
    }
}
