import SwiftUI
import Charts

/// Colourful, read-only breakdown of which folders use your disk.
struct AnalyzerView: View {
    @Environment(AppState.self) private var app

    private static let palette: [Color] = [
        .blue, .purple, .pink, .orange, .yellow, .green, .teal, .indigo, .red,
    ]

    private var total: Int64 {
        app.analyzer.usages.reduce(0) { $0 + $1.size }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                if app.analyzer.usages.isEmpty {
                    if app.analyzer.isScanning {
                        VStack(spacing: 8) {
                            ProgressView()
                            Text("Measuring folders — this runs once and can take a minute…")
                                .font(.system(size: 10.5))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.top, 60)
                    }
                } else {
                    Chart(app.analyzer.usages) { usage in
                        SectorMark(
                            angle: .value("Size", usage.size),
                            innerRadius: .ratio(0.6),
                            angularInset: 1.5)
                        .cornerRadius(3)
                        .foregroundStyle(Self.palette[usage.colorIndex % Self.palette.count])
                    }
                    .frame(height: 170)
                    .overlay {
                        VStack(spacing: 0) {
                            Text(total.bytesFormatted)
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                            Text("measured")
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                        }
                    }

                    VStack(spacing: 6) {
                        ForEach(app.analyzer.usages) { usage in
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(Self.palette[usage.colorIndex % Self.palette.count])
                                    .frame(width: 8, height: 8)
                                Text(usage.name)
                                    .font(.system(size: 11.5, weight: .medium))
                                Spacer()
                                Text(usage.size.bytesFormatted)
                                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                                Button {
                                    NSWorkspace.shared.activateFileViewerSelecting([usage.url])
                                } label: {
                                    Image(systemName: "arrow.up.forward.app")
                                        .font(.system(size: 10))
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
            }
            .padding(14)
        }
        .navigationTitle("Storage Analyzer")
        .task { await app.analyzer.scan() }
        .toolbar {
            Button {
                Task { await app.analyzer.scan() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .disabled(app.analyzer.isScanning)
        }
    }
}
