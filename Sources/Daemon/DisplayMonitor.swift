import Foundation
import IOKit

/// Monitors for screen sharing session state transitions and triggers
/// recovery when a session ends.
///
/// Fully event-driven — no timers, no polling:
///
/// 1. **Darwin notification** `com.apple.screensharing.agent.launchd` fires when
///    the screen sharing subsystem activates. On receipt, a one-shot check confirms
///    `screensharingd` is running and attaches a kernel process exit watcher.
///
/// 2. **Kernel process source** (`EVFILT_PROC` / `NOTE_EXIT`) on `screensharingd`
///    fires the instant the process terminates. Zero-cost session end detection.
///
/// 3. **IOKit interest notification** on `IOPMrootDomain` fires on power state
///    changes including lid open/close. Used for deferred recovery when the session
///    ends with the lid closed — `AppleClamshellState` changing from closed to open
///    triggers the deferred corebrightnessd restart.
final class DisplayMonitor: @unchecked Sendable {
    private var sessionActive = false
    private var deferredRecoveryPending = false
    private var processSource: (any DispatchSourceProcess)?

    // IOPMrootDomain notification for clamshell/power state changes.
    private var rootDomainService: io_service_t = 0
    private var rootDomainPort: IONotificationPortRef?
    private var rootDomainNotification: io_object_t = 0

    func start() {
        log("Monitoring for screen sharing sessions (event-driven)")

        // Watch for screen sharing activation via Darwin notification.
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque(),
            screenSharingNotificationCallback,
            "com.apple.screensharing.agent.launchd" as CFString,
            nil,
            .deliverImmediately
        )
        log("Watching com.apple.screensharing.agent.launchd")

        // Watch IOPMrootDomain for power state changes (clamshell lid open/close).
        setupPowerStateNotification()

        sessionActive = isScreenSharingActive()
        if sessionActive {
            log("screensharingd is currently running")
            onSessionStarted()
            watchScreenSharingExit()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [self] in
            if initialBrightnessCheck() {
                deferredRecoveryPending = true
            }
        }
    }

    // MARK: - Screen Sharing Notification

    fileprivate func handleScreenSharingNotification() {
        guard !sessionActive else { return }
        guard isScreenSharingActive() else { return }

        log("Screen sharing session started")
        sessionActive = true
        onSessionStarted()
        watchScreenSharingExit()
    }

    // MARK: - Power State Notification (Clamshell)

    private func setupPowerStateNotification() {
        var iterator: io_iterator_t = 0
        IOServiceGetMatchingServices(
            kIOMainPortDefault,
            IOServiceMatching("IOPMrootDomain"),
            &iterator
        )
        rootDomainService = IOIteratorNext(iterator)
        IOObjectRelease(iterator)

        guard rootDomainService != 0 else {
            log("IOPMrootDomain not found — deferred recovery will not auto-trigger on lid open")
            return
        }

        rootDomainPort = IONotificationPortCreate(kIOMainPortDefault)
        IONotificationPortSetDispatchQueue(rootDomainPort!, DispatchQueue.main)

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        let result = IOServiceAddInterestNotification(
            rootDomainPort!,
            rootDomainService,
            kIOGeneralInterest,
            powerStateCallback,
            selfPtr,
            &rootDomainNotification
        )

        if result == kIOReturnSuccess {
            log("Watching IOPMrootDomain for power state changes")
        } else {
            log("Failed to watch IOPMrootDomain (\(result))")
        }
    }

    fileprivate func handlePowerStateChange() {
        guard deferredRecoveryPending else { return }

        // Read AppleClamshellState from IOPMrootDomain.
        var props: Unmanaged<CFMutableDictionary>?
        IORegistryEntryCreateCFProperties(rootDomainService, &props, kCFAllocatorDefault, 0)
        guard let dict = props?.takeRetainedValue() as? [String: Any],
              let clamshellState = dict["AppleClamshellState"] as? Int
        else { return }

        // clamshellState: 0 = open, 1 = closed
        guard clamshellState == 0 else { return }

        // Also confirm the display is actually online.
        guard isBuiltInDisplayOnline() else { return }

        log("Lid opened — scheduling deferred recovery")
        deferredRecoveryPending = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            runDeferredRecovery()
        }
    }

    // MARK: - Process Lifecycle

    /// Watches for `screensharingd` to exit using a zero-cost kernel event source.
    private func watchScreenSharingExit() {
        processSource?.cancel()
        processSource = nil

        guard let pid = findProcessPID("screensharingd") else {
            log("Could not find screensharingd PID")
            return
        }

        log("Watching screensharingd (PID \(pid)) for exit")

        let source = DispatchSource.makeProcessSource(
            identifier: pid,
            eventMask: .exit,
            queue: .main
        )
        source.setEventHandler { [weak self] in
            self?.handleScreenSharingExit()
        }
        source.setCancelHandler { [weak self] in
            self?.processSource = nil
        }
        source.resume()
        processSource = source
    }

    private func handleScreenSharingExit() {
        processSource?.cancel()

        guard sessionActive else { return }
        sessionActive = false
        log("screensharingd exited")

        // Small delay for normal macOS teardown to complete.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [self] in
            if onSessionEnded() {
                deferredRecoveryPending = true
            }
        }
    }
}

// MARK: - C Callbacks

nonisolated private func screenSharingNotificationCallback(
    _: CFNotificationCenter?,
    _ observer: UnsafeMutableRawPointer?,
    _: CFNotificationName?,
    _: UnsafeRawPointer?,
    _: CFDictionary?
) {
    guard let observer else { return }
    let monitor = Unmanaged<DisplayMonitor>.fromOpaque(observer).takeUnretainedValue()
    DispatchQueue.main.async {
        monitor.handleScreenSharingNotification()
    }
}

nonisolated private func powerStateCallback(
    _ refcon: UnsafeMutableRawPointer?,
    _: io_service_t,
    _: UInt32,
    _: UnsafeMutableRawPointer?
) {
    guard let refcon else { return }
    let monitor = Unmanaged<DisplayMonitor>.fromOpaque(refcon).takeUnretainedValue()
    DispatchQueue.main.async {
        monitor.handlePowerStateChange()
    }
}
