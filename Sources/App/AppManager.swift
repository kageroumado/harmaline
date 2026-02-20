import AppKit
import Foundation

@Observable
final class AppManager {
    enum DaemonStatus: Equatable {
        case notInstalled
        case installed
        case running
        case installFailed(String)
    }

    private(set) var daemonStatus: DaemonStatus = .notInstalled
    private(set) var recentLogLines: [String] = []

    private static let helperInstallPath = "/Library/PrivilegedHelperTools/harmaline"
    private static let daemonPlistPath = "/Library/LaunchDaemons/glass.kagerou.harmaline.daemon.plist"
    private static let daemonLabel = "glass.kagerou.harmaline.daemon"
    private static let logPath = "/Library/Logs/Harmaline.log"

    init() {
        refreshStatus()
    }

    func refreshStatus() {
        let plistExists = FileManager.default.fileExists(atPath: Self.daemonPlistPath)
        let helperExists = FileManager.default.fileExists(atPath: Self.helperInstallPath)

        if plistExists, helperExists {
            daemonStatus = isProcessRunning("harmaline") ? .running : .installed
        } else {
            daemonStatus = .notInstalled
        }

        recentLogLines = readRecentLog()
    }

    /// Installs the daemon. Shows a macOS password prompt via AppleScript.
    func installDaemon() {
        guard let helperURL = Bundle.main.url(
            forAuxiliaryExecutable: "harmaline-daemon"
        ) else {
            daemonStatus = .installFailed("Daemon binary not found in app bundle")
            return
        }

        guard let plistURL = Bundle.main.url(
            forResource: "glass.kagerou.harmaline.daemon",
            withExtension: "plist",
            subdirectory: "LaunchDaemons"
        ) else {
            daemonStatus = .installFailed("LaunchDaemon plist not found in app bundle")
            return
        }

        let script = """
        do shell script " \
        mkdir -p /Library/PrivilegedHelperTools && \
        cp -f '\(helperURL.path)' '\(Self.helperInstallPath)' && \
        chmod 755 '\(Self.helperInstallPath)' && \
        chown root:wheel '\(Self.helperInstallPath)' && \
        cp -f '\(plistURL.path)' '\(Self.daemonPlistPath)' && \
        chmod 644 '\(Self.daemonPlistPath)' && \
        chown root:wheel '\(Self.daemonPlistPath)' && \
        launchctl bootout system/\(Self.daemonLabel) 2>/dev/null; \
        launchctl bootstrap system '\(Self.daemonPlistPath)' \
        " with administrator privileges
        """

        var error: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&error)

        if let error {
            if let errorNumber = error[NSAppleScript.errorNumber] as? Int, errorNumber == -128 {
                return // User cancelled
            }
            let message = error[NSAppleScript.errorMessage] as? String ?? "Unknown error"
            daemonStatus = .installFailed(message)
        } else {
            daemonStatus = .running
        }
    }

    /// Uninstalls the daemon. Shows a macOS password prompt via AppleScript.
    func uninstallDaemon() {
        let script = """
        do shell script " \
        launchctl bootout system/\(Self.daemonLabel) 2>/dev/null; \
        rm -f '\(Self.daemonPlistPath)' && \
        rm -f '\(Self.helperInstallPath)' \
        " with administrator privileges
        """

        var error: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&error)

        if let error {
            if let errorNumber = error[NSAppleScript.errorNumber] as? Int, errorNumber == -128 {
                return
            }
        }

        refreshStatus()
    }

    // MARK: - Private

    private func isProcessRunning(_ name: String) -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        task.arguments = ["-x", name]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        do {
            try task.run()
            task.waitUntilExit()
            return task.terminationStatus == 0
        } catch {
            return false
        }
    }

    private func readRecentLog() -> [String] {
        guard let data = FileManager.default.contents(atPath: Self.logPath),
              let content = String(data: data, encoding: .utf8)
        else { return [] }

        return content
            .components(separatedBy: "\n")
            .filter { !$0.isEmpty }
            .suffix(12)
            .map { String($0) }
    }
}
