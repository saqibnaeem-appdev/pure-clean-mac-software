import SwiftUI

struct UninstallerView: View {
    @Environment(AppState.self) private var app
    @State private var reviewing: InstalledApp?
    @State private var result: CleanResult?
    @State private var search = ""

    private var filteredApps: [InstalledApp] {
        guard !search.isEmpty else { return app.uninstaller.apps }
        return app.uninstaller.apps.filter {
            $0.name.localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: Theme.gridSpacing) {
                PageHeader("Uninstaller",
                           subtitle: "Removes an app together with its caches, preferences and support files.") {
                    TextField("Search apps…", text: $search)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 200)
                }
                if let result {
                    ResultBanner(result: result)
                }
            }
            .padding(Theme.pagePadding)

            if app.uninstaller.apps.isEmpty {
                ContentUnavailableView(
                    app.uninstaller.isScanning ? "Finding apps…" : "No apps found",
                    systemImage: "xmark.bin")
                .frame(maxHeight: .infinity)
            } else {
                List(filteredApps) { installed in
                    HStack(spacing: 10) {
                        Image(nsImage: app.uninstaller.icon(for: installed))
                            .resizable()
                            .frame(width: 30, height: 30)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(installed.name)
                                .font(.system(size: 12.5, weight: .medium))
                            Text(installed.bundleID)
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Text(installed.appSize > 0 ? installed.appSize.bytesFormatted : "…")
                            .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                        Button("Uninstall…") {
                            Task { reviewing = await app.uninstaller.resolveRelatedFiles(for: installed) }
                        }
                        .controlSize(.small)
                    }
                    .padding(.vertical, 2)
                    .listRowSeparator(.hidden)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .task { await app.uninstaller.scan() }
        .sheet(item: $reviewing) { appToRemove in
            UninstallReviewSheet(app: appToRemove) { confirmed in
                if confirmed { result = self.app.uninstaller.uninstall(appToRemove) }
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
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: app.bundleURL.path))
                    .resizable()
                    .frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Uninstall \(app.name)?")
                        .font(.system(size: 15, weight: .bold))
                    Text("Everything below moves to the Trash (restorable) — total \((app.appSize + app.relatedSize).bytesFormatted).")
                        .font(Theme.caption())
                        .foregroundStyle(.secondary)
                }
            }

            List {
                Label(app.bundleURL.path, systemImage: "app.badge")
                    .font(.system(size: 11))
                ForEach(app.relatedFiles, id: \.self) { url in
                    Label(url.abbreviatedPath, systemImage: "doc")
                        .font(.system(size: 11))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .frame(minHeight: 180)

            HStack {
                Spacer()
                Button("Cancel") { onDismiss(false) }
                    .keyboardShortcut(.cancelAction)
                Button(role: .destructive) {
                    onDismiss(true)
                } label: {
                    Text("Move to Trash").fontWeight(.semibold)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }
        }
        .padding(18)
        .frame(width: 420)
    }
}
