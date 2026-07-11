import SwiftUI
import Charts

/// Accurate APFS storage overview + a read-only folder breakdown.
struct StorageView: View {
    @Environment(AppState.self) private var app
    @State private var donutAppeared = false

    private var disk: DiskOverview { app.monitor.snapshot.disk }

    private var folderTotal: Int64 {
        app.disk.usages.reduce(0) { $0 + $1.size }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.gridSpacing) {
                PageHeader("Storage",
                           subtitle: "\(disk.volumeName) · \(disk.fileSystem)") {
                    Button {
                        Task { await app.disk.scanFolders() }
                    } label: {
                        Label("Rescan Folders", systemImage: "arrow.clockwise")
                    }
                    .controlSize(.large)
                    .disabled(app.disk.isScanning)
                }

                volumeCard
                folderCard
            }
            .padding(Theme.pagePadding)
        }
        .task {
            app.disk.refreshOverview()
            if app.disk.usages.isEmpty {
                await app.disk.scanFolders()
            }
        }
    }

    // MARK: - Volume overview

    private var volumeCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(disk.available.bytesFormatted)
                    .font(Theme.metricLarge())
                    .animatedNumber(disk.available)
                Text("available of \(disk.total.bytesFormatted)")
                    .font(Theme.body())
                    .foregroundStyle(.secondary)
            }

            SegmentBar(segments: [
                .init(id: "used", fraction: disk.usedFraction, color: .blue),
                .init(id: "purgeable",
                      fraction: disk.total > 0 ? Double(disk.purgeable) / Double(disk.total) : 0,
                      color: .orange),
            ], height: 18)

            HStack(spacing: 22) {
                legendStat(color: .blue, label: "Used", value: disk.used.bytesFormatted)
                legendStat(color: .orange, label: "Purgeable",
                           value: disk.purgeable.bytesFormatted,
                           hint: "macOS frees this automatically when space is needed")
                legendStat(color: Color.secondary.opacity(0.35), label: "Free",
                           value: disk.free.bytesFormatted)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Reclaimable now")
                        .font(Theme.footnote())
                        .foregroundStyle(.secondary)
                    Text(reclaimable.bytesFormatted)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(.green)
                        .animatedNumber(reclaimable)
                }
            }
        }
        .glassCard()
    }

    /// Junk found by Smart Scan + current Trash contents + purgeable space.
    private var reclaimable: Int64 {
        disk.purgeable + app.trash.totalSize + app.scanner.recoverableTotal
    }

    private func legendStat(color: Color, label: String, value: String,
                            hint: String? = nil) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2.5)
                .fill(color)
                .frame(width: 9, height: 9)
            VStack(alignment: .leading, spacing: 0) {
                Text(label)
                    .font(Theme.footnote())
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                    .animatedNumber(value)
            }
        }
        .help(hint ?? "")
    }

    // MARK: - Folder breakdown

    private var folderCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionLabel(title: "Where your space goes")

            if app.disk.usages.isEmpty {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("Measuring folders — this runs once and can take a minute…")
                        .font(Theme.caption())
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 40)
            } else {
                HStack(alignment: .center, spacing: 26) {
                    donut
                    VStack(spacing: 6) {
                        ForEach(app.disk.usages) { usage in
                            FolderRow(usage: usage, total: folderTotal)
                        }
                    }
                }
                if app.disk.isScanning {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.mini)
                        Text("Still measuring…")
                            .font(Theme.footnote())
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .glassCard()
    }

    private var donut: some View {
        Chart(app.disk.usages) { usage in
            SectorMark(
                angle: .value("Size", usage.size),
                innerRadius: .ratio(0.62),
                angularInset: 1.6)
            .cornerRadius(4)
            .foregroundStyle(Theme.palette[usage.colorIndex % Theme.palette.count].gradient)
        }
        .frame(width: 190, height: 190)
        .overlay {
            VStack(spacing: 0) {
                Text(folderTotal.bytesFormatted)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .animatedNumber(folderTotal)
                Text("measured")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)
            }
        }
        .rotationEffect(.degrees(donutAppeared ? 0 : -14))
        .scaleEffect(donutAppeared ? 1 : 0.88)
        .opacity(donutAppeared ? 1 : 0)
        .onAppear {
            withAnimation(.spring(response: 0.7, dampingFraction: 0.7)) {
                donutAppeared = true
            }
        }
    }
}

private struct FolderRow: View {
    let usage: FolderUsage
    let total: Int64
    @State private var hovering = false

    private var color: Color {
        Theme.palette[usage.colorIndex % Theme.palette.count]
    }

    var body: some View {
        Button {
            NSWorkspace.shared.activateFileViewerSelecting([usage.url])
        } label: {
            HStack(spacing: 9) {
                Circle().fill(color.gradient).frame(width: 9, height: 9)
                Text(usage.name)
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                LevelBar(fraction: total > 0 ? Double(usage.size) / Double(total) : 0,
                         tint: color, height: 5)
                    .frame(width: 90)
                Text(usage.size.bytesFormatted)
                    .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                    .frame(width: 74, alignment: .trailing)
                Image(systemName: "arrow.up.forward.app")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .opacity(hovering ? 1 : 0.35)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(hovering ? AnyShapeStyle(.quaternary.opacity(0.55))
                                 : AnyShapeStyle(.clear),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Reveal \(usage.name) in Finder")
    }
}
