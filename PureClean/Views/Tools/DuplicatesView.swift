import SwiftUI

struct DuplicatesView: View {
    @Environment(AppState.self) private var app
    @State private var showConfirm = false
    @State private var result: CleanResult?

    private var finder: DuplicateFinder { app.duplicates }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: Theme.gridSpacing) {
                PageHeader("Duplicates",
                           subtitle: "Byte-for-byte verified with SHA-256 — false matches are impossible.") {
                    Button {
                        pickFolder()
                    } label: {
                        if finder.isScanning {
                            ProgressView().controlSize(.small)
                        } else {
                            Label(finder.scannedFolder == nil ? "Choose Folder…" : "Scan Another Folder…",
                                  systemImage: "folder")
                        }
                    }
                    .controlSize(.large)
                    .disabled(finder.isScanning)
                }
                if let result {
                    ResultBanner(result: result)
                }
            }
            .padding(Theme.pagePadding)

            if finder.groups.isEmpty {
                ContentUnavailableView(
                    finder.isScanning ? "Comparing files…" : "No duplicates found",
                    systemImage: "doc.on.doc",
                    description: Text(finder.isScanning
                        ? "Hashing files to confirm exact matches."
                        : "Choose a folder like Pictures or Downloads to scan."))
                .frame(maxHeight: .infinity)
            } else {
                List {
                    ForEach(finder.groups) { group in
                        Section {
                            ForEach(group.files, id: \.self) { url in
                                DuplicateRow(url: url,
                                             isSelected: finder.selection.contains(url)) { on in
                                    if on { finder.selection.insert(url) }
                                    else { finder.selection.remove(url) }
                                }
                            }
                        } header: {
                            Text("\(group.files.count) copies · \(group.fileSize.bytesFormatted) each · save \(group.recoverable.bytesFormatted)")
                                .font(.system(size: 10, weight: .semibold))
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)

                Divider().opacity(0.5)
                HStack {
                    Text("At least one copy of every file is always kept.")
                        .font(Theme.caption())
                        .foregroundStyle(.secondary)
                    Spacer()
                    PrimaryGradientButton(
                        title: "Remove \(finder.recoverableSelected.bytesFormatted)",
                        icon: "trash", fullWidth: false
                    ) {
                        showConfirm = true
                    }
                    .disabled(finder.selection.isEmpty)
                    .opacity(finder.selection.isEmpty ? 0.5 : 1)
                }
                .padding(.horizontal, Theme.pagePadding)
                .padding(.vertical, 12)
                .background(.bar)
            }
        }
        .confirmationDialog(
            "Move selected copies to Trash?",
            isPresented: $showConfirm, titleVisibility: .visible
        ) {
            Button("Move to Trash", role: .destructive) {
                result = finder.trashSelected()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("At least one copy of every file is always kept, and removed copies stay restorable in the Trash.")
        }
    }

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Scan"
        panel.message = "Choose a folder to scan for duplicate images, videos and documents."
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Pictures")
        if panel.runModal() == .OK, let url = panel.url {
            Task { await finder.scan(folder: url) }
        }
    }
}

private struct DuplicateRow: View {
    let url: URL
    let isSelected: Bool
    let toggle: (Bool) -> Void

    var body: some View {
        HStack(spacing: 10) {
            Toggle("", isOn: Binding(get: { isSelected }, set: toggle))
                .toggleStyle(.checkbox)
                .labelsHidden()
            ThumbnailView(url: url)
            VStack(alignment: .leading, spacing: 1) {
                Text(url.lastPathComponent)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                Text(url.deletingLastPathComponent().abbreviatedPath)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } label: {
                Image(systemName: "magnifyingglass.circle")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Reveal in Finder")
        }
        .padding(.vertical, 2)
    }
}

/// Small file preview: real image thumbnail for pictures, icon otherwise.
private struct ThumbnailView: View {
    let url: URL
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                    .resizable()
            }
        }
        .frame(width: 30, height: 30)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .task {
            let path = url
            image = await Task.detached(priority: .utility) { () -> NSImage? in
                let ext = path.pathExtension.lowercased()
                guard ["jpg", "jpeg", "png", "heic", "gif", "webp", "tiff", "bmp"].contains(ext),
                      let source = CGImageSourceCreateWithURL(path as CFURL, nil),
                      let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                        kCGImageSourceCreateThumbnailFromImageAlways: true,
                        kCGImageSourceThumbnailMaxPixelSize: 64,
                      ] as CFDictionary)
                else { return nil }
                return NSImage(cgImage: cg, size: .zero)
            }.value
        }
    }
}
