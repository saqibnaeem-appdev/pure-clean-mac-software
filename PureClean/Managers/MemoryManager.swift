import Foundation
import Observation

/// RAM insight + the "Free Memory" action.
/// We never force-quit apps — freeing works by asking the kernel to purge
/// its disk caches (`purge`), which is exactly what the button explains.
@MainActor
@Observable
final class MemoryManager {

    private(set) var isFreeing = false
    private(set) var lastFreed: Int64?

    var stats: MemoryStats { SystemStatsManager.readMemory() }

    /// Human explanation shown under the Free Memory button.
    var explanation: String {
        let s = stats
        return "Active \(s.active.bytesFormatted) · Wired \(s.wired.bytesFormatted) · Compressed \(s.compressed.bytesFormatted). Freeing purges disk caches only — no app is ever closed."
    }

    /// Runs `purge` (admin prompt) and reports how much became free.
    func freeMemory() async {
        guard !isFreeing else { return }
        isFreeing = true
        defer { isFreeing = false }

        let before = SystemStatsManager.readMemory().free
        let purged = await Task.detached(priority: .userInitiated) {
            ShellRunner.runPrivileged("/usr/sbin/purge")
        }.value

        // Give the kernel a moment to settle, then measure the gain.
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        let after = SystemStatsManager.readMemory().free
        lastFreed = purged ? max(0, after - before) : nil
    }
}
