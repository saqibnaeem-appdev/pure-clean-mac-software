import SwiftUI
import Charts

/// A live dot that breathes at the newest data point of a chart.
struct PulsingDot: View {
    var tint: Color = .blue
    @State private var pulse = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(tint.opacity(0.7), lineWidth: 1.5)
                .frame(width: 9, height: 9)
                .scaleEffect(pulse ? 2.6 : 1)
                .opacity(pulse ? 0 : 0.8)
            Circle()
                .fill(tint)
                .frame(width: 9, height: 9)
                .shadow(color: tint.opacity(0.8), radius: 4)
            Circle()
                .fill(.white)
                .frame(width: 3.5, height: 3.5)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) {
                pulse = true
            }
        }
    }
}

/// Positions a pulsing dot on the last sample of a chart series.
private struct LastPointOverlay: View {
    let proxy: ChartProxy
    let geo: GeometryProxy
    let index: Int
    let value: Double
    let tint: Color

    var body: some View {
        if let plotFrame = proxy.plotFrame,
           let x = proxy.position(forX: Double(index)),
           let y = proxy.position(forY: value) {
            let frame = geo[plotFrame]
            PulsingDot(tint: tint)
                .position(x: frame.origin.x + x, y: frame.origin.y + y)
        }
    }
}

/// Bold, layered area+line history chart: a deep gradient fill, two glow
/// halos under a 3 pt line for depth, and a pulsing dot riding the newest
/// sample. Values in 0…1 by default; `yDomain: nil` auto-scales.
struct HistoryChart: View {
    let values: [Double]
    var tint: Color = .blue
    var yDomain: ClosedRange<Double>? = 0...1
    var height: CGFloat = 88

    private var domain: ClosedRange<Double> {
        if let yDomain { return yDomain }
        let top = max(values.max() ?? 1, 1)
        return 0...(top * 1.25)
    }

    var body: some View {
        Chart {
            ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                AreaMark(x: .value("t", index), y: .value("v", value))
                    .foregroundStyle(
                        LinearGradient(colors: [tint.opacity(0.45), tint.opacity(0.14), .clear],
                                       startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.catmullRom)
                // Two glow passes under the line give the "3D" depth.
                LineMark(x: .value("t", index), y: .value("v", value),
                         series: .value("s", "glow-wide"))
                    .foregroundStyle(tint.opacity(0.10))
                    .interpolationMethod(.catmullRom)
                    .lineStyle(StrokeStyle(lineWidth: 15, lineCap: .round))
                LineMark(x: .value("t", index), y: .value("v", value),
                         series: .value("s", "glow"))
                    .foregroundStyle(tint.opacity(0.28))
                    .interpolationMethod(.catmullRom)
                    .lineStyle(StrokeStyle(lineWidth: 7.5, lineCap: .round))
                LineMark(x: .value("t", index), y: .value("v", value),
                         series: .value("s", "line"))
                    .foregroundStyle(
                        LinearGradient(colors: [tint.opacity(0.7), tint],
                                       startPoint: .leading, endPoint: .trailing))
                    .interpolationMethod(.catmullRom)
                    .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))
            }
        }
        .chartYScale(domain: domain)
        .chartXScale(domain: 0...59)
        .chartXAxis(.hidden)
        .chartYAxis {
            AxisMarks(values: .automatic(desiredCount: 3)) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 4]))
                    .foregroundStyle(.quaternary)
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geo in
                if let last = values.last, values.count > 1 {
                    LastPointOverlay(proxy: proxy, geo: geo,
                                     index: values.count - 1, value: last, tint: tint)
                }
            }
        }
        .frame(height: height)
        .animation(.linear(duration: 0.4), value: values)
    }
}

/// Two overlaid histories (network down/up, disk read/write), auto-scaled
/// to the larger series, same glow + pulsing-dot treatment.
struct DualHistoryChart: View {
    struct Series: Identifiable {
        let id: String
        let values: [Double]
        let tint: Color
    }

    let series: [Series]
    var height: CGFloat = 88

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
                            LinearGradient(colors: [line.tint.opacity(0.30), .clear],
                                           startPoint: .top, endPoint: .bottom))
                        .interpolationMethod(.catmullRom)
                    LineMark(x: .value("t", index), y: .value("v", value),
                             series: .value("series", "\(line.id)-glow"))
                        .foregroundStyle(line.tint.opacity(0.22))
                        .interpolationMethod(.catmullRom)
                        .lineStyle(StrokeStyle(lineWidth: 7, lineCap: .round))
                    LineMark(x: .value("t", index), y: .value("v", value),
                             series: .value("series", line.id))
                        .foregroundStyle(line.tint.gradient)
                        .interpolationMethod(.catmullRom)
                        .lineStyle(StrokeStyle(lineWidth: 2.6, lineCap: .round))
                }
            }
        }
        .chartYScale(domain: domain)
        .chartXScale(domain: 0...59)
        .chartXAxis(.hidden)
        .chartYAxis {
            AxisMarks(values: .automatic(desiredCount: 3)) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 4]))
                    .foregroundStyle(.quaternary)
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geo in
                ForEach(series) { line in
                    if let last = line.values.last, line.values.count > 1 {
                        LastPointOverlay(proxy: proxy, geo: geo,
                                         index: line.values.count - 1,
                                         value: last, tint: line.tint)
                    }
                }
            }
        }
        .frame(height: height)
        .animation(.linear(duration: 0.4), value: series.map(\.values))
    }
}

/// Compact vertical bars for per-core CPU activity.
struct CoreActivityBars: View {
    let values: [Double]
    var tint: Color = .cyan
    var height: CGFloat = 42

    var body: some View {
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(Array(values.enumerated()), id: \.offset) { _, value in
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(
                            LinearGradient(colors: [tint, tint.opacity(0.5)],
                                           startPoint: .top, endPoint: .bottom))
                        .frame(height: max(3, height * value))
                        .shadow(color: tint.opacity(0.4 * value), radius: 3, y: 1)
                }
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(.quaternary.opacity(0.35)))
            }
        }
        .frame(height: height)
        .animation(.easeOut(duration: 0.5), value: values)
    }
}
