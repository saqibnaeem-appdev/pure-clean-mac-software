import SwiftUI

/// Live Trash manager: accurate size across all volumes, an item preview,
/// and a safe Empty Trash with confirmation.
struct TrashView: View {
    @Environment(AppState.self) private var app
    @State private var showEmptyConfirm = false
    @State private var result: CleanResult?

    private var trash: TrashService { app.trash }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.gridSpacing) {
                PageHeader("Trash",
                           subtitle: "Includes the Trash folders on every mounted volume — the same set Finder empties.") {
                    Button {
                        trash.revealInFinder()
                    } label: {
                        Label("Show in Finder", systemImage: "arrow.up.forward.app")
                    }
                    .controlSize(.large)
                }

                if trash.needsFullDiskAccess {
                    accessCard
                } else {
                    heroCard

                    if let result {
                        ResultBanner(result: result)
                    }

                    if !trash.items.isEmpty {
                        itemList
                    }
                }
            }
            .padding(Theme.pagePadding)
        }
        .onAppear { trash.refresh() }
        .confirmationDialog(
            "Empty the Trash?",
            isPresented: $showEmptyConfirm, titleVisibility: .visible
        ) {
            Button("Permanently Erase \(trash.itemCount) Item\(trash.itemCount == 1 ? "" : "s")",
                   role: .destructive) {
                Task { result = await trash.empty() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently removes \(trash.totalSize.bytesFormatted). You can't undo this action.")
        }
    }

    /// Shown when macOS blocks Trash access — honest state, clear fix.
    private var accessCard: some View {
        VStack(spacing: 14) {
            IconBadge(systemName: "lock.shield.fill", tint: .orange, size: 52)
            VStack(spacing: 4) {
                Text("Full Disk Access needed")
                    .font(Theme.display(17, .bold))
                Text("macOS protects the Trash, so PureClean can't measure it yet.\nEnable PureClean in System Settings, then restart the app — macOS only applies the permission to a fresh launch.")
                    .font(Theme.body())
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            HStack(spacing: 10) {
                Button("Open Privacy Settings…") {
                    app.permissions.openFullDiskAccessSettings()
                }
                .controlSize(.large)
                PrimaryGradientButton(title: "Restart PureClean", icon: "arrow.triangle.2.circlepath",
                                      fullWidth: false) {
                    app.permissions.relaunchApp()
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 26)
        .glassCard()
    }

    private var heroCard: some View {
        HStack(spacing: 20) {
            IconBadge(systemName: "trash.fill", tint: .red, size: 52)
            VStack(alignment: .leading, spacing: 2) {
                Text(trash.totalSize.bytesFormatted)
                    .font(Theme.metricLarge())
                    .animatedNumber(trash.totalSize)
                Text("\(trash.itemCount) item\(trash.itemCount == 1 ? "" : "s") in the Trash")
                    .font(Theme.body())
                    .foregroundStyle(.secondary)
                if let emptied = trash.lastEmptied {
                    Text("Last emptied \(emptied.formatted(date: .abbreviated, time: .shortened))")
                        .font(Theme.footnote())
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer()
            if trash.isRefreshing {
                ProgressView().controlSize(.small)
            }
            PrimaryGradientButton(
                title: trash.isEmptying ? "Emptying…" : "Empty Trash",
                icon: "trash",
                isBusy: trash.isEmptying,
                fullWidth: false
            ) {
                result = nil
                showEmptyConfirm = true
            }
            .disabled(trash.itemCount == 0 || trash.isEmptying)
            .opacity(trash.itemCount == 0 ? 0.5 : 1)
        }
        .glassCard()
    }

    private var itemList: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(title: "What's inside")
            VStack(spacing: 3) {
                ForEach(trash.items.prefix(50)) { item in
                    TrashItemRow(item: item)
                }
                if trash.items.count > 50 {
                    Text("+ \(trash.items.count - 50) more items — open Finder to see everything")
                        .font(Theme.footnote())
                        .foregroundStyle(.tertiary)
                        .padding(.top, 4)
                }
            }
        }
        .glassCard()
    }
}

private struct TrashItemRow: View {
    let item: TrashItem
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                .resizable()
                .frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 0) {
                Text(item.url.lastPathComponent)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                if item.modified != .distantPast {
                    Text("Modified \(item.modified.formatted(date: .abbreviated, time: .omitted))")
                        .font(.system(size: 9.5))
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer()
            Text(item.size.bytesFormatted)
                .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(hovering ? AnyShapeStyle(.quaternary.opacity(0.5))
                             : AnyShapeStyle(.clear),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onHover { hovering = $0 }
    }
}
