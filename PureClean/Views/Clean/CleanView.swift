import SwiftUI

/// Category-by-category cleaning with review, confirmation and progress.
struct CleanView: View {
    @Environment(AppState.self) private var app
    @State private var showConfirm = false
    @State private var result: CleanResult?

    var body: some View {
        @Bindable var cleaner = app.cleaner
        return VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 8) {
                    if let result { ResultBanner(result: result) }
                    ForEach($cleaner.categories) { $category in
                        CategoryRow(category: $category)
                    }
                    maintenanceCard
                }
                .padding(14)
            }

            Divider()
            footer
        }
        .task { await app.cleaner.scan() }
        .confirmationDialog(
            "Clean selected categories?",
            isPresented: $showConfirm, titleVisibility: .visible
        ) {
            Button("Recover \(app.cleaner.recoverableSelected.bytesFormatted)", role: .destructive) {
                Task { result = await app.cleaner.cleanSelected() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Items are moved to the Trash where possible so you can restore them. Personal files are never touched.")
        }
    }

    private var footer: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(app.cleaner.recoverableSelected.bytesFormatted)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                Text("selected to recover")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                Task { await app.cleaner.scan() }
            } label: {
                Label("Rescan", systemImage: "arrow.clockwise")
            }
            .disabled(app.cleaner.isScanning)

            Button {
                result = nil
                showConfirm = true
            } label: {
                Label(app.cleaner.isCleaning ? "Cleaning…" : "Clean Now", systemImage: "sparkles")
                    .fontWeight(.semibold)
            }
            .buttonStyle(.borderedProminent)
            .disabled(app.cleaner.isCleaning || app.cleaner.recoverableSelected == 0)
        }
        .padding(12)
        .background(.bar)
    }

    private var maintenanceCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Maintenance")
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Flush DNS Cache")
                        .font(.system(size: 12, weight: .medium))
                    Text("Fixes stale name-resolution issues. Asks for your password because it restarts mDNSResponder.")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button("Flush") {
                    let cleaner = app.cleaner
                    Task.detached { _ = cleaner.flushDNS() }
                }
            }
        }
        .cardStyle()
    }
}

private struct CategoryRow: View {
    @Binding var category: CleanCategory

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: category.icon)
                .font(.system(size: 14))
                .foregroundStyle(category.isSelected ? Color.accentColor : .secondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(category.name)
                    .font(.system(size: 12, weight: .medium))
                Text(category.detail)
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            Text(category.scannedSize.bytesFormatted)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(category.scannedSize > 0 ? .primary : .tertiary)
            Toggle("", isOn: $category.isSelected)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
        }
        .padding(10)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 10))
    }
}
