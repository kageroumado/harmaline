import Foundation

let args = CommandLine.arguments

if args.contains("--help") || args.contains("-h") {
    print("""
    harmaline — Fixes black screen after macOS Screen Sharing disconnect
    
    USAGE:
      harmaline              Run as a daemon (monitors and auto-recovers)
      harmaline --fix        One-shot: fix the display now and exit
      harmaline --status     Check current display state
      harmaline --help       Show this help
    
    DESCRIPTION:
      macOS Screen Sharing's "High Performance" mode creates a virtual display
      and blanks the built-in panel by setting its brightness to zero. When the
      session ends, the brightness is sometimes not restored — leaving you with
      a black screen on an otherwise fully functional Mac.
    
      This tool detects the condition and restores the display by:
        1. Writing the saved brightness level back through IOKit
        2. Restarting corebrightnessd to restore brightness key functionality
        3. Toggling True Tone off/on to force recalibration
    
      Daemon mode is fully event-driven with zero polling:
        - Darwin notification for screen sharing session start
        - Kernel process source for session end detection
        - IOKit power state notification for lid open/close
    
    INSTALL:
      sudo Scripts/install.sh       Install as a LaunchDaemon
      sudo Scripts/uninstall.sh     Remove the LaunchDaemon
    """)
} else if args.contains("--fix") {
    fixDisplayNow()
} else if args.contains("--status") {
    reportStatus()
} else {
    // Daemon mode
    log("harmaline v1.0 starting")
    let monitor = DisplayMonitor()
    monitor.start()
    RunLoop.main.run()
}
