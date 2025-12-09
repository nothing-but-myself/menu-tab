#!/usr/bin/env swift

import Cocoa
import ApplicationServices

// 检查辅助功能权限
func checkAccessibility() -> Bool {
    let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
    return AXIsProcessTrustedWithOptions(options as CFDictionary)
}

// 获取 AXUIElement 的属性值
func getAttributeValue<T>(_ element: AXUIElement, _ attribute: String) -> T? {
    var value: CFTypeRef?
    let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
    if result == .success, let value = value as? T {
        return value
    }
    return nil
}

// 获取元素的位置
func getPosition(_ element: AXUIElement) -> CGPoint? {
    var position: CFTypeRef?
    let result = AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &position)
    if result == .success, let positionValue = position {
        var point = CGPoint.zero
        AXValueGetValue(positionValue as! AXValue, .cgPoint, &point)
        return point
    }
    return nil
}

// 获取元素的大小
func getSize(_ element: AXUIElement) -> CGSize? {
    var size: CFTypeRef?
    let result = AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &size)
    if result == .success, let sizeValue = size {
        var cgSize = CGSize.zero
        AXValueGetValue(sizeValue as! AXValue, .cgSize, &cgSize)
        return cgSize
    }
    return nil
}

// 递归遍历 UI 元素
func exploreElement(_ element: AXUIElement, depth: Int = 0, maxDepth: Int = 5) {
    let indent = String(repeating: "  ", count: depth)

    // 获取角色
    let role: String? = getAttributeValue(element, kAXRoleAttribute as String)
    let subrole: String? = getAttributeValue(element, kAXSubroleAttribute as String)
    let title: String? = getAttributeValue(element, kAXTitleAttribute as String)
    let description: String? = getAttributeValue(element, kAXDescriptionAttribute as String)

    // 获取位置
    let position = getPosition(element)
    let size = getSize(element)

    // 只打印有意义的信息
    if let role = role {
        var info = "\(indent)[\(role)]"
        if let subrole = subrole { info += " subrole=\(subrole)" }
        if let title = title, !title.isEmpty { info += " title=\"\(title)\"" }
        if let description = description, !description.isEmpty { info += " desc=\"\(description)\"" }
        if let pos = position, let sz = size {
            info += " pos=(\(Int(pos.x)),\(Int(pos.y))) size=(\(Int(sz.width))x\(Int(sz.height)))"
        }
        print(info)
    }

    // 递归遍历子元素
    if depth < maxDepth {
        var children: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children)
        if result == .success, let childArray = children as? [AXUIElement] {
            for child in childArray {
                exploreElement(child, depth: depth + 1, maxDepth: maxDepth)
            }
        }
    }
}

// 获取菜单栏
func getMenuBarExtras() {
    print("=== Exploring Menu Bar via Accessibility API ===\n")

    // 方法1: 通过 SystemUIServer 获取
    print("--- Method 1: SystemUIServer ---\n")

    let runningApps = NSWorkspace.shared.runningApplications
    if let systemUI = runningApps.first(where: { $0.bundleIdentifier == "com.apple.systemuiserver" }) {
        let appElement = AXUIElementCreateApplication(systemUI.processIdentifier)
        print("SystemUIServer PID: \(systemUI.processIdentifier)")
        exploreElement(appElement, maxDepth: 4)
    }

    // 方法2: 通过控制中心获取
    print("\n--- Method 2: Control Center ---\n")

    if let controlCenter = runningApps.first(where: { $0.bundleIdentifier == "com.apple.controlcenter" }) {
        let appElement = AXUIElementCreateApplication(controlCenter.processIdentifier)
        print("Control Center PID: \(controlCenter.processIdentifier)")
        exploreElement(appElement, maxDepth: 4)
    }

    // 方法3: 尝试获取所有有 menu bar extra 的应用
    print("\n--- Method 3: Apps with menu extras ---\n")

    let appsToCheck = [
        "com.raycast.macos",
        "com.west2online.ClashXPro",
        "dev.kdrag0n.MacVirt" // OrbStack
    ]

    for bundleId in appsToCheck {
        if let app = runningApps.first(where: { $0.bundleIdentifier == bundleId }) {
            print("\n\(app.localizedName ?? bundleId):")
            let appElement = AXUIElementCreateApplication(app.processIdentifier)
            exploreElement(appElement, maxDepth: 3)
        }
    }
}

// 主函数
print("Checking accessibility permission...\n")
if !checkAccessibility() {
    print("⚠️  Please grant accessibility permission in:")
    print("System Settings > Privacy & Security > Accessibility")
    print("\nThen run this script again.\n")
}

getMenuBarExtras()
