import SwiftUI

struct LargeFilesView: View {
    @Environment(AppState.self) private var app
    @State private var showConfirm = false
    @State private var result: CleanResult?

    private var finder: LargeFileFinder { app.largeFiles }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("Larger than", selection: Bindable(app.largeFiles).threshold) {
                    ForEach(LargeFileFinder.Threshold.allCases) { t in
                        Text(t.label).tag(t)
                    }
                }
                .pickerStyle(.segmented)
                Button {
                    Task { await finder.scan() }
                } label: {
                    if finder.isScanning { ProgressView().controlSize(.small) }
                    else { Label("Scan", systemImage: "magnifyingglass") }
                }
                .disabled(finder.isScanning)
            }
            .padding(12)

            Divider()

            if finder.files.isEmpty {
                ContentUnavailableView(
                    finder.isScanning ? "Scanning your home folder…" : "No results yet",
                    systemImage: "doc.zipper",
                    description: Text(finder.isScanning
                        ? "This can take a minute on large disks."
                        : "Pick a threshold and press Scan. You review everything before anything is removed."))
                .frame(maxHeight: .infinity)
            } else {
                List(finder.files, selection: Bindable(app.largeFiles).selection) { file in
                    HStack {
                        Toggle("", isOn: Binding(
                            get: { finder.selection.contains(file.url) },
                            set: { on in
                                if on { finder.selection.insert(file.url) }
                                else { finder.selection.remove(file.url) }
                            }))
                        .labelsHidden()
                        VStack(alignment: .leading, spacing: 1) {
                            Text(file.url.lastPathComponent)
                                .font(.system(size: 11.5, weight: .medium))
                                .lineLimit(1)
                            Text(file.url.deletingLastPathComponent().path
                                .replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Text(file.size.bytesFormatted)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                        Button {
                            NSWorkspace.shared.activateFileViewerSelecting([file.url])
                        } label: {
                            Image(systemName: "magnifyingglass.circle")
                        }
                        .buttonStyle(.plain)
                        .help("Reveal in Finder")
                    }
                }
                .listStyle(.plain)

                Divider()
                HStack {
                    if let result {
                        Text("Moved \(result.removedItems) items (\(result.freedBytes.bytesFormatted)) to Trash")
                            .font(.system(size: 10)).foregroundStyle(.green)
                    }
                    Spacer()
                    Button(role: .destructive) {
                        showConfirm = true
                    } label: {
                        Label("Move \(finder.selectedBytes.bytesFormatted) to Trash", systemImage: "trash")
                    }
                    .disabled(finder.selection.isEmpty)
                }
                .padding(10)
            }
        }
        .navigationTitle("Large Files")
        .confirmOverlay(
            isPresented: $showConfirm,
            title: "Move \(finder.selection.count) files to Trash?",
            message: "Files go to the Trash — you can restore them anytime before emptying it.",
            confirmTitle: "Move to Trash"
        ) {
            result = finder.trashSelected()
        }
    }
}
