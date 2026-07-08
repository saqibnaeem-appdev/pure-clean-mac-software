import SwiftUI

struct DuplicatesView: View {
    @Environment(AppState.self) private var app
    @State private var showConfirm = false
    @State private var result: CleanResult?

    private var finder: DuplicateFinder { app.duplicates }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(finder.scannedFolder?.lastPathComponent ?? "No folder selected")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Duplicates are verified byte-for-byte (SHA-256) — no false matches.")
                        .font(.system(size: 9.5))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    pickFolder()
                } label: {
                    if finder.isScanning { ProgressView().controlSize(.small) }
                    else { Label("Choose Folder…", systemImage: "folder") }
                }
                .disabled(finder.isScanning)
            }
            .padding(12)

            Divider()

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
                                DuplicateRow(url: url, size: group.fileSize,
                                             isSelected: finder.selection.contains(url)) { on in
                                    if on { finder.selection.insert(url) }
                                    else { finder.selection.remove(url) }
                                }
                            }
                        } header: {
                            Text("\(group.files.count) copies · \(group.fileSize.bytesFormatted) each · save \(group.recoverable.bytesFormatted)")
                                .font(.system(size: 9.5, weight: .semibold))
                        }
                    }
                }
                .listStyle(.plain)

                Divider()
                HStack {
                    if let result {
                        Text("Removed \(result.removedItems) copies (\(result.freedBytes.bytesFormatted))")
                            .font(.system(size: 10)).foregroundStyle(.green)
                    }
                    Spacer()
                    Button(role: .destructive) { showConfirm = true } label: {
                        Label("Remove \(finder.recoverableSelected.bytesFormatted)", systemImage: "trash")
                    }
                    .disabled(finder.selection.isEmpty)
                }
                .padding(10)
            }
        }
        .navigationTitle("Duplicates")
        .confirmOverlay(
            isPresented: $showConfirm,
            title: "Move selected copies to Trash?",
            message: "At least one copy of every file is always kept, and removed copies stay restorable in the Trash.",
            confirmTitle: "Move to Trash"
        ) {
            result = finder.trashSelected()
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
    let size: Int64
    let isSelected: Bool
    let toggle: (Bool) -> Void

    var body: some View {
        HStack(spacing: 8) {
            Toggle("", isOn: Binding(get: { isSelected }, set: toggle))
                .labelsHidden()
            ThumbnailView(url: url)
            VStack(alignment: .leading, spacing: 1) {
                Text(url.lastPathComponent)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                Text(url.deletingLastPathComponent().path
                    .replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } label: {
                Image(systemName: "magnifyingglass.circle")
            }
            .buttonStyle(.plain)
            .help("Reveal in Finder")
        }
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
        .frame(width: 28, height: 28)
        .clipShape(RoundedRectangle(cornerRadius: 6))
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
