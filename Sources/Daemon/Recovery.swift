import CoreGraphics
import Foundation
import IOKit
import ObjectiveC

/// Brightness level saved when a screen sharing session starts.
/// Restored on recovery instead of using a hardcoded value.
private nonisolated(unsafe) var savedBrightnessLevel: Int?

// MARK: - Session Lifecycle

/// Called when a screen sharing session starts. Saves the current brightness
/// so we can restore it if the session ends with the display stuck.
func onSessionStarted() {
    guard let fb = findBuiltInFramebuffer() else { return }
    defer { IOObjectRelease(fb) }

    if let brightness = getBrightnessLevel(fb), brightness > 0 {
        savedBrightnessLevel = brightness
        log("Saved pre-session brightness: \(brightness)")
    }
}

/// Called when a screen sharing session ends. Handles both the black screen bug
/// (brightness stuck at 0) and the True Tone desync that can occur regardless.
///
/// Returns `true` if the display is offline and deferred recovery is needed
/// (corebrightnessd restart must wait until the display comes online).
@discardableResult
func onSessionEnded() -> Bool {
    guard let fb = findBuiltInFramebuffer() else {
        log("No built-in framebuffer found")
        return false
    }
    defer { IOObjectRelease(fb) }

    guard let brightness = getBrightnessLevel(fb) else {
        log("Could not read brightness level")
        return false
    }

    guard brightness == 0 else {
        log("Brightness OK (\(brightness)) — no recovery needed")
        savedBrightnessLevel = nil
        return false
    }

    // Bug triggered: brightness stuck at 0.
    let target = savedBrightnessLevel ?? 5_000_000 // reasonable default (~50% brightness)
    savedBrightnessLevel = nil
    log("DETECTED: Brightness stuck at 0 after screen sharing session ended")
    log("Restoring IOMFBBrightnessLevel to \(target)...")
    guard setBrightnessLevel(fb, target) else {
        log("ERROR: Failed to set brightness level")
        return false
    }
    log("Brightness restored")

    if isBuiltInDisplayOnline() {
        restartCoreBrightness()
        refreshTrueTone()
        log("Recovery complete")
        return false
    } else {
        // Display is offline (lid closed). Brightness was set via IOKit and will
        // take effect when the lid opens. But corebrightnessd restart must wait —
        // restarting it without a display leaves brightness keys broken.
        log("Display offline (lid closed) — deferring corebrightnessd restart")
        return true
    }
}

// MARK: - Startup Check

/// Checks if the display is stuck from a prior session. Only fixes brightness == 0;
/// does NOT touch True Tone (to avoid visibly disrupting the display on daemon restart).
///
/// Returns `true` if the display is offline and deferred recovery is needed.
@discardableResult
func initialBrightnessCheck() -> Bool {
    guard let fb = findBuiltInFramebuffer() else { return false }
    defer { IOObjectRelease(fb) }

    guard let brightness = getBrightnessLevel(fb), brightness == 0 else { return false }
    guard !isScreenSharingActive() else { return false }

    log("DETECTED: Brightness stuck at 0 (initial check)")
    guard setBrightnessLevel(fb, 5_000_000) else {
        log("ERROR: Failed to set brightness level")
        return false
    }
    log("Brightness restored")

    if isBuiltInDisplayOnline() {
        restartCoreBrightness()
        refreshTrueTone()
        log("Recovery complete")
        return false
    } else {
        log("Display offline — deferring corebrightnessd restart")
        return true
    }
}

// MARK: - One-Shot Fix (--fix flag)

/// Immediate recovery for manual use. Always performs the full fix.
func fixDisplayNow() {
    guard let fb = findBuiltInFramebuffer() else {
        print("No built-in framebuffer found (Intel Mac or no internal display)")
        return
    }
    defer { IOObjectRelease(fb) }

    guard let brightness = getBrightnessLevel(fb) else {
        print("Could not read brightness level")
        return
    }

    if brightness == 0 {
        guard setBrightnessLevel(fb, 5_000_000) else {
            print("ERROR: Failed to set brightness level")
            return
        }
        restartCoreBrightness()
        refreshTrueTone()
        print("Display recovered")
    } else {
        print("Brightness is \(brightness) — display appears OK (not stuck)")
    }
}

// MARK: - Status

func reportStatus() {
    guard let fb = findBuiltInFramebuffer() else {
        print("No built-in framebuffer found (Intel Mac or no internal display)")
        return
    }
    defer { IOObjectRelease(fb) }

    let brightness = getBrightnessLevel(fb)
    let sharing = isScreenSharingActive()

    print("Built-in display framebuffer found")
    print("  IOMFBBrightnessLevel: \(brightness.map(String.init) ?? "unreadable")")
    print("  screensharingd running: \(sharing)")
    print("  Saved pre-session brightness: \(savedBrightnessLevel.map(String.init) ?? "none")")

    if brightness == 0, !sharing {
        print("  STATUS: Display appears stuck — run with --fix to recover")
    } else if brightness == 0, sharing {
        print("  STATUS: Brightness is 0 (expected — screen sharing session active)")
    } else {
        print("  STATUS: Display OK")
    }
}

// MARK: - IOKit Helpers

/// Finds the IOMobileFramebufferAP service for the built-in display.
///
/// Apple Silicon Macs have multiple IOMobileFramebufferAP instances (one per display output).
/// The built-in panel is identified by having `BLMPowergateEnable` (backlight management).
func findBuiltInFramebuffer() -> io_service_t? {
    var iterator: io_iterator_t = 0
    let result = IOServiceGetMatchingServices(
        kIOMainPortDefault,
        IOServiceMatching("IOMobileFramebufferAP"),
        &iterator
    )
    guard result == kIOReturnSuccess else { return nil }
    defer { IOObjectRelease(iterator) }

    var service = IOIteratorNext(iterator)
    while service > 0 {
        var properties: Unmanaged<CFMutableDictionary>?
        IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0)
        if let props = properties?.takeRetainedValue() as? [String: Any],
           props["BLMPowergateEnable"] != nil {
            return service
        }
        IOObjectRelease(service)
        service = IOIteratorNext(iterator)
    }
    return nil
}

func getBrightnessLevel(_ service: io_service_t) -> Int? {
    var properties: Unmanaged<CFMutableDictionary>?
    IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0)
    guard let props = properties?.takeRetainedValue() as? [String: Any] else { return nil }
    return props["IOMFBBrightnessLevel"] as? Int
}

@discardableResult
func setBrightnessLevel(_ service: io_service_t, _ level: Int) -> Bool {
    let cfLevel = level as CFNumber
    return IORegistryEntrySetCFProperty(
        service, "IOMFBBrightnessLevel" as CFString, cfLevel
    ) == kIOReturnSuccess
}

func isScreenSharingActive() -> Bool {
    runProcess("/usr/bin/pgrep", arguments: ["-x", "screensharingd"])
}

/// Returns the PID of a named process, or `nil` if it's not running.
func findProcessPID(_ name: String) -> pid_t? {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
    task.arguments = ["-x", name]
    let pipe = Pipe()
    task.standardOutput = pipe
    task.standardError = FileHandle.nullDevice
    do {
        try task.run()
        task.waitUntilExit()
        guard task.terminationStatus == 0 else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let line = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: "\n")
            .first,
            let pid = pid_t(line) else { return nil }
        return pid
    } catch {
        return nil
    }
}

/// Checks if the built-in display is currently online via CoreGraphics.
/// Returns false when the lid is closed (display deregistered from CG).
func isBuiltInDisplayOnline() -> Bool {
    var displayIDs = [CGDirectDisplayID](repeating: 0, count: 16)
    var count: UInt32 = 0
    CGGetOnlineDisplayList(16, &displayIDs, &count)
    for i in 0 ..< Int(count) {
        if CGDisplayIsBuiltin(displayIDs[i]) != 0 {
            return true
        }
    }
    return false
}

/// Restarts `corebrightnessd` and waits for it to initialize.
func restartCoreBrightness() {
    log("Restarting corebrightnessd...")
    runProcess("/usr/bin/killall", arguments: ["corebrightnessd"])
    Thread.sleep(forTimeInterval: 1.5)
}

// MARK: - True Tone Recovery

/// Toggles True Tone off/on via CoreBrightness private API to force recalibration.
/// Returns `true` if True Tone was successfully toggled, `false` if the display
/// wasn't ready (e.g., lid closed, not supported).
@discardableResult
func refreshTrueTone() -> Bool {
    typealias BoolGetterIMP = @convention(c) (AnyObject, Selector) -> Bool
    typealias BoolSetterIMP = @convention(c) (AnyObject, Selector, Bool) -> Bool

    guard dlopen(
        "/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness",
        RTLD_NOW
    ) != nil else {
        log("Could not load CoreBrightness framework")
        return false
    }

    guard let clientClass = NSClassFromString("CBTrueToneClient") as? NSObject.Type else {
        log("CBTrueToneClient class not found")
        return false
    }

    let client = clientClass.init()
    let supportedSel = NSSelectorFromString("supported")
    let enabledSel = NSSelectorFromString("enabled")
    let setEnabledSel = NSSelectorFromString("setEnabled:")

    let boolGetter = unsafeBitCast(
        class_getMethodImplementation(type(of: client), supportedSel),
        to: BoolGetterIMP.self
    )
    let isSupported = boolGetter(client, supportedSel)
    guard isSupported else {
        log("True Tone not supported (display may not be online yet)")
        return false
    }

    let enabledGetter = unsafeBitCast(
        class_getMethodImplementation(type(of: client), enabledSel),
        to: BoolGetterIMP.self
    )
    let wasEnabled = enabledGetter(client, enabledSel)
    guard wasEnabled else {
        log("True Tone is disabled by user — not toggling")
        return true // not an error, just nothing to do
    }

    let setter = unsafeBitCast(
        class_getMethodImplementation(type(of: client), setEnabledSel),
        to: BoolSetterIMP.self
    )

    log("Toggling True Tone off/on...")
    _ = setter(client, setEnabledSel, false)
    Thread.sleep(forTimeInterval: 0.5)
    _ = setter(client, setEnabledSel, true)
    log("True Tone recalibration triggered")
    return true
}

// MARK: - Deferred Recovery (lid closed)

/// Restarts corebrightnessd and refreshes True Tone. Called by DisplayMonitor
/// when the built-in display comes online after a lid-closed session end.
func runDeferredRecovery() {
    restartCoreBrightness()
    refreshTrueTone()
    log("Deferred recovery complete")
}

// MARK: - Process Helper

@discardableResult
func runProcess(_ path: String, arguments: [String]) -> Bool {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: path)
    task.arguments = arguments
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
