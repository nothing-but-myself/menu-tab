#!/usr/bin/env swift

import Cocoa

// 获取状态栏项目列表
func listStatusBarItems() {
    let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []

    print("=== All Status Bar Items ===\n")

    var statusBarItems: [(name: String, bundleId: String?, x: CGFloat, width: CGFloat)] = []

    for window in windowList {
        guard let layer = window[kCGWindowLayer as String] as? Int,
              layer == 25 || layer == 26, // 状态栏层级
              let bounds = window[kCGWindowBounds as String] as? [String: CGFloat],
              let ownerPID = window[kCGWindowOwnerPID as String] as? pid_t,
              let ownerName = window[kCGWindowOwnerName as String] as? String else {
            continue
        }

        let x = bounds["X"] ?? 0
        let width = bounds["Width"] ?? 0

        let app = NSRunningApplication(processIdentifier: ownerPID)
        let bundleId = app?.bundleIdentifier

        statusBarItems.append((name: ownerName, bundleId: bundleId, x: x, width: width))
    }

    // 按 X 坐标排序
    statusBarItems.sort { $0.x < $1.x }

    // 获取屏幕宽度来估算刘海位置
    let screenWidth = NSScreen.main?.frame.width ?? 1920
    let notchStart = screenWidth / 2 - 120  // 估算刘海起始位置
    let notchEnd = screenWidth / 2 + 120    // 估算刘海结束位置

    print("Screen width: \(Int(screenWidth))")
    print("Estimated notch area: \(Int(notchStart)) - \(Int(notchEnd))\n")

    for (index, item) in statusBarItems.enumerated() {
        let inNotch = item.x > notchStart && item.x < notchEnd
        let notchIndicator = inNotch ? " ⚠️ HIDDEN" : ""
        print("\(index + 1). \(item.name)")
        print("   Bundle: \(item.bundleId ?? "unknown")")
        print("   Position: x=\(Int(item.x)), width=\(Int(item.width))\(notchIndicator)")
        print("")
    }

    let hiddenCount = statusBarItems.filter { $0.x > notchStart && $0.x < notchEnd }.count
    print("=== Summary ===")
    print("Total items: \(statusBarItems.count)")
    print("Potentially hidden by notch: \(hiddenCount)")
}

listStatusBarItems()
