import SwiftUI

struct UninstallerView: View {
    @Environment(AppState.self) private var app
    @State private var reviewing: InstalledApp?
    @State private var result: CleanResult?

    var body: some View {
        VStack(spacing: 0) {
            if app.uninstaller.apps.isEmpty {
                ContentUnavailableView(
                    app.uninstaller.isScanning ? "Finding apps…" : "No apps found",
                    systemImage: "trash.slash")
                .frame(maxHeight: .infinity)
            } else {
                List(app.uninstaller.apps) { installed in
                    HStack(spacing: 8) {
                        Image(nsImage: app.uninstaller.icon(for: installed))
                            .resizable()
                            .frame(width: 26, height: 26)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(installed.name)
                                .font(.system(size: 11.5, weight: .medium))
                            Text(installed.bundleID)
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Text(installed.appSize > 0 ? installed.appSize.bytesFormatted : "…")
                            .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                        Button("Uninstall…") {
                            Task { reviewing = await app.uninstaller.resolveRelatedFiles(for: installed) }
                        }
                        .controlSize(.small)
                    }
                }
                .listStyle(.plain)
            }
            if let result {
                Divider()
                ResultBanner(result: result).padding(10)
            }
        }
        .navigationTitle("App Uninstaller")
        .task { await app.uninstaller.scan() }
        .sheet(item: $reviewing) { appToRemove in
            UninstallReviewSheet(app: appToRemove) { confirmed in
                if confirmed {
                    result = self.app.uninstaller.uninstall(appToRemove)
                }
                reviewing = nil
            }
        }
    }
}

/// Shows exactly what will be trashed before the user commits.
private struct UninstallReviewSheet: View {
    let app: InstalledApp
    let onDismiss: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Uninstall \(app.name)?")
                .font(.headline)
            Text("The following will move to the Trash (restorable) — total \((app.appSize + app.relatedSize).bytesFormatted):")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            List {
                Label(app.bundleURL.path, systemImage: "app.badge")
                    .font(.system(size: 10.5))
                ForEach(app.relatedFiles, id: \.self) { url in
                    Label(url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"),
                          systemImage: "doc")
                        .font(.system(size: 10.5))
                        .lineLimit(1)
                }
            }
            .frame(minHeight: 160)

            HStack {
                Spacer()
                Button("Cancel") { onDismiss(false) }
                Button(role: .destructive) {
                    onDismiss(true)
                } label: {
                    Text("Move to Trash").fontWeight(.semibold)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }
        }
        .padding(16)
        .frame(width: 360)
    }
}
