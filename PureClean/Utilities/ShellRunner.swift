import Foundation

/// Small helper for the few maintenance actions that need a shell
/// (DNS flush, memory purge). Everything file-related uses FileManager.
enum ShellRunner {

    @discardableResult
    static func run(_ launchPath: String, _ arguments: [String]) -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return (process.terminationStatus, String(data: data, encoding: .utf8) ?? "")
        } catch {
            return (-1, error.localizedDescription)
        }
    }

    /// Runs a command with an admin-privileges prompt (macOS password dialog).
    /// Used only for `purge` and the mDNSResponder DNS flush; the user is
    /// told exactly why before we call this.
    static func runPrivileged(_ command: String) -> Bool {
        let escaped = command.replacingOccurrences(of: "\"", with: "\\\"")
        let source = "do shell script \"\(escaped)\" with administrator privileges"
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
        return error == nil
    }
}
