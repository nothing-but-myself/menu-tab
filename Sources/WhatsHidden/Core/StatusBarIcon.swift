import Cocoa
import ApplicationServices

/// Data model for menu bar icons
struct StatusBarIcon: Identifiable, Equatable {
    let id: Int  // CFHash of AXUIElement as unique identifier
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

extension Array {
    subscript(safe index: Int) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}
