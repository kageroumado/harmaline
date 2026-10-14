# Harmaline

Harmaline restores a MacBook’s backlight when disconnecting from High Performance Screen Sharing leaves it black. A background daemon detects the session ending and restores brightness and brightness-key behavior, avoiding a forced shutdown.

<a href="https://kagerou.glass/get/harmaline?from=readme"><img src=".github/download.svg" alt="Download Harmaline for Mac" width="360" height="80"></a>

<img src=".github/harmaline-window.png" alt="Harmaline’s daemon setup window" width="420">

## Highlights

- Recover the MacBook backlight after a High Performance Screen Sharing session ends.
- Restore brightness-key behavior without a forced shutdown.
- Keep recovery active after the setup app closes.

<details>
<summary>Full feature list</summary>

- Background detection of Screen Sharing session endings.
- Backlight and brightness-key restoration.
- Menu-bar app for enabling or disabling the daemon.
- CLI installation, `--status` diagnostics, and `--fix` recovery.
- Structured logs at `/Library/Logs/Harmaline.log` and unified logging under `glass.kagerou.harmaline`.

</details>

## Notes

- Archived · macOS 14+ · Apple silicon Mac with a built-in display · administrator approval for the daemon.
- Build the app with `Scripts/build-app.sh`; daemon installation/uninstallation uses `Scripts/install.sh` and `Scripts/uninstall.sh`.
- [Detection and recovery reference](REFERENCE.md).
