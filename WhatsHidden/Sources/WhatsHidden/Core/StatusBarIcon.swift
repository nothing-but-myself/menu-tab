import Cocoa
import ApplicationServices

// MARK: - Status Bar Icon Model
struct StatusBarIcon: Identifiable, Equatable {
    let id: Int  // AXUIElement 的哈希值作为唯一标识
    let name: String
    let bundleId: String
    let element: AXUIElement
    let x: CGFloat
    let y: CGFloat
    let width: CGFloat
    
    static func == (lhs: StatusBarIcon, rhs: StatusBarIcon) -> Bool {
        return lhs.id == rhs.id
    }
}

// MARK: - System Info
struct SystemInfo {
    static let osVersion = ProcessInfo.processInfo.operatingSystemVersion
    static let osMajor = osVersion.majorVersion
    
    /// 是否是 macOS 12+
    static var isMontereyOrLater: Bool {
        osMajor >= 12
    }
    
    /// 是否有刘海
    static var hasNotch: Bool {
        guard let screen = NSScreen.main else { return false }
        if #available(macOS 12.0, *) {
            return screen.safeAreaInsets.top > 24
        }
        return false
    }
}
