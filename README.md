# Harmaline

Fixes the black screen bug after disconnecting from macOS Screen Sharing in High Performance mode.

## The Problem

macOS Screen Sharing's **High Performance** mode (introduced in Sonoma) creates a virtual display and blanks the built-in panel by setting its backlight brightness to zero via IOKit (`IOMFBBrightnessLevel = 0`). When the session ends, the brightness is supposed to be restored — but it often isn't.

The result: your MacBook screen stays completely black after disconnecting. The system is fully functional (you can type, apps are running), but the display backlight is off. Even sleep/wake cycles don't fix it. Physical brightness keys stop working. The only "fix" most people know is a force shutdown.

This is a [widely reported](https://discussions.apple.com/thread/255783743), unfixed Apple bug affecting Sonoma, Sequoia, and Tahoe on all Apple Silicon MacBooks.

## Install

### App

Download from Releases or build the app from source:

```bash
git clone https://github.com/kirie/harmaline.git
cd harmaline
Scripts/build-app.sh
```
This builds `Harmaline.app` in `.build/`. 

Open it and click **Enable** — you'll be prompted for your admin password to install the background daemon.

The app is only needed for enabling/disabling the daemon. Once enabled, the daemon runs independently in the background and persists across reboots. You can quit or delete the app.

### CLI Only

```bash
git clone https://github.com/kirie/harmaline.git
cd harmaline
sudo Scripts/install.sh
```

## Uninstall

**Via app:** Open Harmaline and click **Disable**.

**Via CLI:**
```bash
sudo Scripts/uninstall.sh
```

## Emergency Fix

If your screen is black right now:

```bash
# SSH into the Mac, then:
swift build -c release
sudo .build/release/harmaline --fix
```

Or check the current display state:
```bash
sudo .build/release/harmaline --status
```

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

## Logs

- **Structured log**: `/Library/Logs/Harmaline.log`
- **Unified logging**: `log show --predicate 'subsystem == "glass.kagerou.harmaline"'`

## Requirements

- macOS 14 (Sonoma) or later
- Apple Silicon Mac with built-in display
