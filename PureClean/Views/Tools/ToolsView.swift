import SwiftUI

/// Hub for the review-based tools. Each row pushes a dedicated screen.
struct ToolsView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 8) {
                    ToolRow(icon: "doc.zipper", tint: .orange,
                            title: "Large Files",
                            detail: "Find files over 500 MB, 1 GB or 5 GB") {
                        LargeFilesView()
                    }
                    ToolRow(icon: "doc.on.doc", tint: .purple,
                            title: "Duplicate Finder",
                            detail: "Identical photos, videos, PDFs & documents") {
                        DuplicatesView()
                    }
                    ToolRow(icon: "trash.slash", tint: .red,
                            title: "App Uninstaller",
                            detail: "Remove apps with all their leftovers") {
                        UninstallerView()
                    }
                    ToolRow(icon: "power", tint: .green,
                            title: "Startup Items",
                            detail: "Review what launches at login") {
                        StartupView()
                    }
                    ToolRow(icon: "chart.pie", tint: .blue,
                            title: "Storage Analyzer",
                            detail: "See which folders eat your disk") {
                        AnalyzerView()
                    }
                }
                .padding(14)
            }
            .navigationTitle("Tools")
        }
    }
}

private struct ToolRow<Destination: View>: View {
    let icon: String
    let tint: Color
    let title: String
    let detail: String
    @ViewBuilder let destination: () -> Destination

    var body: some View {
        NavigationLink {
            destination()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(tint.gradient, in: RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.system(size: 12.5, weight: .semibold))
                    Text(detail).font(.system(size: 10)).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(10)
            .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 10))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
