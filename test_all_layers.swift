#!/usr/bin/env swift

import Cocoa

// 列出所有窗口层级
func listAllLayers() {
    let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []

    var layerMap: [Int: [(name: String, bounds: [String: CGFloat])]] = [:]

    for window in windowList {
        guard let layer = window[kCGWindowLayer as String] as? Int,
              let bounds = window[kCGWindowBounds as String] as? [String: CGFloat],
              let ownerName = window[kCGWindowOwnerName as String] as? String else {
            continue
        }

        let y = bounds["Y"] ?? 0
        let height = bounds["Height"] ?? 0

        // 只关注顶部区域（状态栏）
        if y < 30 && height < 50 {
            if layerMap[layer] == nil {
                layerMap[layer] = []
            }
            layerMap[layer]?.append((name: ownerName, bounds: bounds))
        }
    }

    print("=== Windows in top area (y < 30, height < 50) by Layer ===\n")

    for layer in layerMap.keys.sorted() {
        print("Layer \(layer):")
        for item in layerMap[layer]! {
            let x = item.bounds["X"] ?? 0
            let w = item.bounds["Width"] ?? 0
            print("  - \(item.name): x=\(Int(x)), w=\(Int(w))")
        }
        print("")
    }
}

// 也列出所有菜单栏进程
func listMenuBarExtras() {
    print("=== Menu Bar Extra Apps (running apps with status items) ===\n")

    let workspace = NSWorkspace.shared
    let apps = workspace.runningApplications

    for app in apps {
        if app.activationPolicy == .accessory || app.activationPolicy == .prohibited {
            print("- \(app.localizedName ?? "Unknown") (\(app.bundleIdentifier ?? "?"))")
        }
    }
}

listAllLayers()
print("\n" + String(repeating: "=", count: 50) + "\n")
listMenuBarExtras()
