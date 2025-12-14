import Cocoa
import ApplicationServices

/// App lifecycle and permissions
class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationDidFinishLaunching(_ notification: Notification) {
        // System compatibility check
        print("System: \(SystemInfo.description)")

        if !SystemInfo.isMontereyOrLater {
            print("Warning: macOS 12 (Monterey) or later recommended")
        }

        if !SystemInfo.hasNotch {
            print("Info: No notch detected on current display")
        }

        // Permission check
        if !checkPermissions() {
            print("Warning: Accessibility permission required")
        }

        // Initialize services
        _ = StatusBarManager.shared
        HotkeyManager.shared.start()

        print("")
        print("What's Hidden is running")
        print("  Ctrl + `      Open switcher / Next")
        print("  Ctrl + Shift + `  Previous")
        print("  Release Ctrl  Confirm")
        print("  Esc           Cancel")
    }

    @discardableResult
    func checkPermissions() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        return AXIsProcessTrustedWithOptions(options as CFDictionary)
    }
}
