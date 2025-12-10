#!/usr/bin/env swift

import Cocoa
import ApplicationServices

// MARK: - Accessibility Helpers

func getPosition(_ element: AXUIElement) -> CGPoint? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &value) == .success,
          let val = value, CFGetTypeID(val) == AXValueGetTypeID() else { return nil }
    var point = CGPoint.zero
    AXValueGetValue(val as! AXValue, .cgPoint, &point)
    return point
}

func getSize(_ element: AXUIElement) -> CGSize? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &value) == .success,
          let val = value, CFGetTypeID(val) == AXValueGetTypeID() else { return nil }
    var size = CGSize.zero
    AXValueGetValue(val as! AXValue, .cgSize, &size)
    return size
}

func getActionNames(_ element: AXUIElement) -> [String] {
    var names: CFArray?
    guard AXUIElementCopyActionNames(element, &names) == .success,
          let nameArray = names as? [String] else { return [] }
    return nameArray
}

func getAttributeValue<T>(_ element: AXUIElement, _ attribute: String) -> T? {
    var value: CFTypeRef?
    let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
    if result == .success, let value = value as? T {
        return value
    }
    return nil
}

// 递归查找所有 actions
func findAllActions(_ element: AXUIElement, depth: Int = 0) -> Set<String> {
    var allActions = Set<String>()
    
    // 当前元素的 actions
    let actions = getActionNames(element)
    allActions.formUnion(actions)
    
    // 递归子元素
    if depth < 3 {
        var childrenRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
           let children = childrenRef as? [AXUIElement] {
            for child in children {
                allActions.formUnion(findAllActions(child, depth: depth + 1))
            }
        }
    }
    
    return allActions
}

// MARK: - Main

print("=== Menu Bar Icon Actions Analysis ===\n")
print("Analyzing which apps show menu vs activate app...\n")

let selfPid = ProcessInfo.processInfo.processIdentifier
let runningApps = NSWorkspace.shared.runningApplications

var results: [(name: String, bundleId: String, hasShowMenu: Bool, hasPress: Bool, allActions: Set<String>)] = []

for app in runningApps {
    guard let bundleId = app.bundleIdentifier else { continue }
    if app.processIdentifier == selfPid { continue }
    if bundleId.hasPrefix("com.apple.") { continue }
    
    let appElement = AXUIElementCreateApplication(app.processIdentifier)
    var extras: CFTypeRef?
    
    guard AXUIElementCopyAttributeValue(appElement, "AXExtrasMenuBar" as CFString, &extras) == .success,
          let extrasRef = extras,
          CFGetTypeID(extrasRef) == AXUIElementGetTypeID() else { continue }
    
    let extrasElement = extrasRef as! AXUIElement
    guard let pos = getPosition(extrasElement),
          let size = getSize(extrasElement),
          size.width > 0 && pos.y < 50 else { continue }
    
    let name = app.localizedName ?? bundleId
    
    // 收集所有 actions（包括子元素）
    let allActions = findAllActions(extrasElement)
    
    let hasShowMenu = allActions.contains("AXShowMenu")
    let hasPress = allActions.contains("AXPress")
    
    results.append((name: name, bundleId: bundleId, hasShowMenu: hasShowMenu, hasPress: hasPress, allActions: allActions))
}

// 按名称排序
results.sort { $0.name < $1.name }

// 打印结果
print("App Name             | AXShowMenu | AXPress | Behavior")
print("---------------------|------------|---------|-------------------")

for r in results {
    let behavior: String
    if r.hasShowMenu {
        behavior = "Shows Menu ✓"
    } else if r.hasPress {
        behavior = "May Activate App ⚠️"
    } else {
        behavior = "Unknown"
    }
    
    let name = r.name.padding(toLength: 20, withPad: " ", startingAt: 0)
    let showMenu = (r.hasShowMenu ? "Yes" : "No").padding(toLength: 10, withPad: " ", startingAt: 0)
    let press = (r.hasPress ? "Yes" : "No").padding(toLength: 7, withPad: " ", startingAt: 0)
    print("\(name) | \(showMenu) | \(press) | \(behavior)")
}

print("\n=== Detailed Actions ===\n")

for r in results {
    print("\(r.name) (\(r.bundleId)):")
    print("  Actions: \(r.allActions.sorted())")
    print("")
}

print("=== Summary ===")
let showMenuApps = results.filter { $0.hasShowMenu }
let pressOnlyApps = results.filter { !$0.hasShowMenu && $0.hasPress }

print("Apps with AXShowMenu (will show menu): \(showMenuApps.count)")
print("Apps with only AXPress (may activate app): \(pressOnlyApps.count)")

if !pressOnlyApps.isEmpty {
    print("\nApps that may activate instead of showing menu:")
    for app in pressOnlyApps {
        print("  - \(app.name) (\(app.bundleId))")
    }
}
