# harmaline reference

[Overview](README.md)

## How It Works

### Root Cause

Screen Sharing's High Performance mode operates by:

1. Creating a `CGVirtualDisplay` via `SkyLight.framework` and `CoreDisplay.framework`
2. Moving all windows to the virtual display
3. Blanking the physical display by setting `IOMFBBrightnessLevel = 0` on the `IOMobileFramebufferAP` IOKit service

On disconnect, `screensharingd` is supposed to destroy the virtual display and restore brightness. The virtual display teardown usually works, but the brightness restore silently fails — leaving the backlight hardware powered off while the system thinks everything is fine.

### Event-Driven Detection (Zero Polling)

The daemon uses three kernel/system event sources with zero timers and zero polling:

1. **Darwin notification** (`com.apple.screensharing.agent.launchd`) fires when the screen sharing subsystem activates. On receipt, a one-shot check confirms `screensharingd` is running and the daemon saves the current brightness level.

2. **Kernel process source** (`EVFILT_PROC` / `NOTE_EXIT`) on `screensharingd` fires the instant the process terminates. Zero-cost session end detection.

3. **IOKit interest notification** on `IOPMrootDomain` fires on power state changes including lid open/close. Used for deferred recovery when the session ends with the lid closed.

### Recovery

When `screensharingd` exits and `IOMFBBrightnessLevel` is stuck at 0:

1. The saved pre-session brightness is written back via `IORegistryEntrySetCFProperty`, immediately turning the backlight on
2. `corebrightnessd` is restarted to re-sync the brightness subsystem so keyboard brightness keys work again
3. True Tone is toggled off/on via `CBTrueToneClient` (CoreBrightness private API) to force ambient light sensor recalibration

If the lid is closed when the session ends, the `corebrightnessd` restart and True Tone toggle are deferred until the lid opens.

If no recovery is needed (brightness restored normally), the daemon does nothing.

### Built-in Display Identification

Apple Silicon Macs have multiple `IOMobileFramebufferAP` instances (one per display output). The built-in panel is identified by the presence of `BLMPowergateEnable` (backlight power gate management) in its IOKit properties.
