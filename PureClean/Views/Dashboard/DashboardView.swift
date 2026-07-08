import SwiftUI

struct DashboardView: View {
    @Environment(AppState.self) private var app
    @State private var showCleanConfirm = false
    @State private var cleanResult: CleanResult?

    private var vm: DashboardViewModel {
        DashboardViewModel(snapshot: app.stats.snapshot, cleaner: app.cleaner)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                header
                smartCleanCard
                if let cleanResult { ResultBanner(result: cleanResult) }
                ringsRow
                statsGrid
                freeMemoryCard
            }
            .padding(14)
        }
        .confirmationDialog(
            "Run Smart Clean?",
            isPresented: $showCleanConfirm, titleVisibility: .visible
        ) {
            Button("Clean \(app.cleaner.recoverableSelected.bytesFormatted)", role: .destructive) {
                Task { cleanResult = await app.cleaner.cleanSelected() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Only caches, logs and temporary files are removed. Items go to the Trash so you can restore them. Personal files are never touched.")
        }
    }

    private var header: some View {
        HStack {
            HStack(spacing: 7) {
                Image(systemName: "sparkles")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(
                        LinearGradient(colors: [.blue, .purple],
                                       startPoint: .top, endPoint: .bottom))
                Text("PureClean")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
            }
            Spacer()
            Text(vm.snapshot.smartStatus == "Verified" ? "Disk: Healthy" : "Disk: \(vm.snapshot.smartStatus)")
                .font(.system(size: 10, weight: .medium))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(.green.opacity(0.15), in: Capsule())
                .foregroundStyle(.green)
        }
    }

    private var smartCleanCard: some View {
        VStack(spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Smart Clean")
                        .font(.system(size: 13, weight: .semibold))
                    Text(vm.recoverableText)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if app.cleaner.isScanning { ProgressView().controlSize(.small) }
            }
            if app.cleaner.isCleaning {
                ProgressView(value: app.cleaner.progress)
                    .progressViewStyle(.linear)
            }
            PrimaryButton(
                title: app.cleaner.isCleaning ? "Cleaning…" : "Smart Clean",
                icon: "sparkles",
                isBusy: app.cleaner.isCleaning
            ) {
                cleanResult = nil
                showCleanConfirm = true
            }
        }
        .cardStyle()
    }

    private var ringsRow: some View {
        HStack(spacing: 12) {
            VStack(spacing: 6) {
                ProgressRing(
                    fraction: vm.storageUsedFraction,
                    label: vm.snapshot.diskFree.bytesFormatted,
                    sublabel: "free of \(vm.snapshot.diskTotal.bytesFormatted)",
                    tint: .blue)
                Text("Storage").font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            VStack(spacing: 6) {
                ProgressRing(
                    fraction: vm.snapshot.memory.usedFraction,
                    label: vm.snapshot.memory.used.bytesFormatted,
                    sublabel: "of \(vm.snapshot.memory.total.bytesFormatted)",
                    tint: .purple)
                Text("Memory").font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            VStack(spacing: 6) {
                ProgressRing(
                    fraction: vm.snapshot.cpuUsage,
                    label: vm.snapshot.cpuUsage.percentFormatted,
                    sublabel: "CPU load",
                    tint: .cyan)
                Text("CPU").font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
        }
        .cardStyle()
    }

    private var statsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
            StatCard(icon: "battery.75percent", title: "Battery",
                     value: vm.batteryText, detail: vm.batteryDetail, tint: .green)
            StatCard(icon: "internaldrive", title: "Cache",
                     value: vm.cacheSize.bytesFormatted, detail: "app + browser", tint: .orange)
            StatCard(icon: "trash", title: "Trash",
                     value: vm.trashSize.bytesFormatted, detail: "restorable", tint: .red)
            StatCard(icon: "clock.arrow.circlepath", title: "Temp Files",
                     value: vm.tempSize.bytesFormatted, detail: "user temp dir", tint: .indigo)
        }
    }

    private var freeMemoryCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Free Memory")
                        .font(.system(size: 13, weight: .semibold))
                    Text(app.memory.explanation)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if let freed = app.memory.lastFreed {
                Text("Freed \(freed.bytesFormatted) ✓")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.green)
            }
            Button {
                Task { await app.memory.freeMemory() }
            } label: {
                HStack(spacing: 6) {
                    if app.memory.isFreeing {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "memorychip")
                    }
                    Text("Free Memory").fontWeight(.medium)
                }
                .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .disabled(app.memory.isFreeing)
        }
        .cardStyle()
    }
}
