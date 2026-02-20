import AppKit
import SwiftUI

struct ContentView: View {
    var manager: AppManager

    var body: some View {
        VStack(spacing: 0) {
            headerSection
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 12)

            statusSection
                .padding(.horizontal, 20)
                .padding(.bottom, 16)

            if !manager.recentLogLines.isEmpty {
                Divider()

                logSection
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
            }
        }
        .frame(width: 360)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            manager.refreshStatus()
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Harmaline")
                .font(.system(size: 16, weight: .bold))

            Text("Fixes the black screen bug after macOS Screen Sharing disconnects in High Performance mode.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Status

    private var statusSection: some View {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                statusIcon

                VStack(alignment: .leading, spacing: 2) {
                    Text(statusTitle)
                        .font(.system(size: 13, weight: .semibold))

                    Text(statusDetail)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }

            actionButton
        }
    }

    private var statusIcon: some View {
        Image(systemName: iconName)
            .symbolRenderingMode(.hierarchical)
            .font(.system(size: 24, weight: .medium))
            .foregroundStyle(iconColor)
            .contentTransition(.symbolEffect(.replace))
            .frame(width: 28)
    }

    private var iconName: String {
        switch manager.daemonStatus {
        case .running: "checkmark.circle.fill"
        case .installed: "circle.fill"
        case .notInstalled: "circle"
        case .installFailed: "exclamationmark.circle.fill"
        }
    }

    private var iconColor: Color {
        switch manager.daemonStatus {
        case .running: .green
        case .installed: .orange
        case .notInstalled: .secondary
        case .installFailed: .red
        }
    }

    private var statusTitle: String {
        switch manager.daemonStatus {
        case .running: "Running"
        case .installed: "Installed (Not Running)"
        case .notInstalled: "Not Installed"
        case .installFailed: "Installation Failed"
        }
    }

    private var statusDetail: String {
        switch manager.daemonStatus {
        case .running:
            "Monitoring for screen sharing sessions"
        case .installed:
            "Daemon installed but not currently running"
        case .notInstalled:
            "Automatically fixes black screen after Screen Sharing disconnect"
        case let .installFailed(message):
            message
        }
    }

    @ViewBuilder
    private var actionButton: some View {
        switch manager.daemonStatus {
        case .notInstalled:
            Button("Enable\u{2026}") { manager.installDaemon() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
        case .installed, .running:
            Button("Disable\u{2026}") { manager.uninstallDaemon() }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .frame(maxWidth: .infinity)
        case .installFailed:
            Button("Retry\u{2026}") { manager.installDaemon() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Log

    private var logSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Recent Activity")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    manager.refreshStatus()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10))
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(manager.recentLogLines, id: \.self) { line in
                        Text(formatLogLine(line))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 160)
        }
    }

    private func formatLogLine(_ line: String) -> String {
        // Strip the date prefix, keep just the time and message.
        // Format: [2026-02-18 16:48:22] Message
        guard line.hasPrefix("["),
              let closeBracket = line.firstIndex(of: "]")
        else { return line }

        let dateStr = line[line.index(after: line.startIndex) ..< closeBracket]
        // Extract just HH:mm:ss from "2026-02-18 16:48:22"
        let components = dateStr.split(separator: " ")
        let time = components.count >= 2 ? String(components[1]) : String(dateStr)
        let message = String(line[line.index(after: closeBracket)...]).trimmingCharacters(in: .whitespaces)

        return "\(time)  \(message)"
    }
}
