import Cocoa

/// System compatibility and environment detection
struct SystemInfo {
    static let osVersion = ProcessInfo.processInfo.operatingSystemVersion
    static let osMajor = osVersion.majorVersion
    static let osMinor = osVersion.minorVersion

    /// Is macOS 12+
    static var isMontereyOrLater: Bool {
        osMajor >= 12
    }

    /// Check if a specific screen has notch (using safeAreaInsets)
    static func hasNotch(screen: NSScreen) -> Bool {
        if #available(macOS 12.0, *) {
            return screen.safeAreaInsets.top > 24
        }
        return false
    }

    /// Check if main screen has notch
    static var hasNotch: Bool {
        guard let screen = NSScreen.main else { return false }
        return hasNotch(screen: screen)
    }

    /// Find the built-in display (the one with notch)
    static var builtInScreen: NSScreen? {
        return NSScreen.screens.first { hasNotch(screen: $0) }
    }

    /// Is Apple Silicon
    static var isAppleSilicon: Bool {
        var sysinfo = utsname()
        uname(&sysinfo)
        let machine = withUnsafePointer(to: &sysinfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(validatingUTF8: $0)
            }
        }
        return machine?.contains("arm64") ?? false
    }

    /// System info description
    static var description: String {
        let chip = isAppleSilicon ? "Apple Silicon" : "Intel"
        let notch = hasNotch ? " (Notch)" : ""
        return "macOS \(osMajor).\(osMinor) · \(chip)\(notch)"
    }
}
