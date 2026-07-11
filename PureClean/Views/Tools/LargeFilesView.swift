import SwiftUI

struct LargeFilesView: View {
    @Environment(AppState.self) private var app
    @State private var showConfirm = false
    @State private var result: CleanResult?

    private var finder: LargeFileFinder { app.largeFiles }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: Theme.gridSpacing) {
                PageHeader("Large Files",
                           subtitle: "Find the biggest files in your home folder. You review everything before anything moves.") {
                    HStack(spacing: 10) {
                        Picker("", selection: Bindable(app.largeFiles).threshold) {
                            ForEach(LargeFileFinder.Threshold.allCases) { threshold in
                                Text(threshold.label).tag(threshold)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(width: 220)
                        Button {
                            Task { await finder.scan() }
                        } label: {
                            if finder.isScanning {
                                ProgressView().controlSize(.small)
                            } else {
                                Label("Scan", systemImage: "magnifyingglass")
                            }
                        }
                        .controlSize(.large)
                        .disabled(finder.isScanning)
                    }
                }
                if let result {
                    ResultBanner(result: result)
                }
            }
            .padding(Theme.pagePadding)
            .padding(.bottom, result == nil ? 0 : 4)

            if finder.files.isEmpty {
                ContentUnavailableView(
                    finder.isScanning ? "Scanning your home folder…" : "No results yet",
                    systemImage: "doc.zipper",
                    description: Text(finder.isScanning
                        ? "This can take a minute on large disks."
                        : "Pick a size threshold and press Scan."))
                .frame(maxHeight: .infinity)
            } else {
                List(finder.files) { file in
                    LargeFileRow(file: file, finder: finder)
                        .listRowSeparator(.hidden)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)

                Divider().opacity(0.5)
                HStack {
                    Text("\(finder.files.count) files found · \(finder.selection.count) selected")
                        .font(Theme.caption())
                        .foregroundStyle(.secondary)
                    Spacer()
                    PrimaryGradientButton(
                        title: "Move \(finder.selectedBytes.bytesFormatted) to Trash",
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
            "Move \(finder.selection.count) file\(finder.selection.count == 1 ? "" : "s") to Trash?",
            isPresented: $showConfirm, titleVisibility: .visible
        ) {
            Button("Move to Trash", role: .destructive) {
                result = finder.trashSelected()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Files go to the Trash — you can restore them anytime before emptying it.")
        }
    }
}

private struct LargeFileRow: View {
    let file: LargeFile
    let finder: LargeFileFinder

    private var isSelected: Bool { finder.selection.contains(file.url) }

    var body: some View {
        HStack(spacing: 10) {
            Toggle("", isOn: Binding(
                get: { isSelected },
                set: { on in
                    if on { finder.selection.insert(file.url) }
                    else { finder.selection.remove(file.url) }
                }))
            .toggleStyle(.checkbox)
            .labelsHidden()
            Image(nsImage: NSWorkspace.shared.icon(forFile: file.url.path))
                .resizable()
                .frame(width: 26, height: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(file.url.lastPathComponent)
                    .font(.system(size: 12.5, weight: .medium))
                    .lineLimit(1)
                Text(file.url.deletingLastPathComponent().abbreviatedPath)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Text(file.modified.formatted(date: .abbreviated, time: .omitted))
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
            Text(file.size.bytesFormatted)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .frame(width: 76, alignment: .trailing)
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([file.url])
            } label: {
                Image(systemName: "magnifyingglass.circle")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Reveal in Finder")
        }
        .padding(.vertical, 3)
    }
}
