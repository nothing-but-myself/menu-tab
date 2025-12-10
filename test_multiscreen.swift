#!/usr/bin/env swift

import Cocoa
import ApplicationServices

// MARK: - Accessibility Helpers

func getAttributeValue<T>(_ element: AXUIElement, _ attribute: String) -> T? {
    var value: CFTypeRef?
    let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
    if result == .success, let value = value as? T {
        return value
    }
    return nil
}

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

func getAttributeNames(_ element: AXUIElement) -> [String] {
    var names: CFArray?
    guard AXUIElementCopyAttributeNames(element, &names) == .success,
          let nameArray = names as? [String] else { return [] }
    return nameArray
}

func getActionNames(_ element: AXUIElement) -> [String] {
    var names: CFArray?
    guard AXUIElementCopyActionNames(element, &names) == .success,
          let nameArray = names as? [String] else { return [] }
    return nameArray
}

// MARK: - Screen Info

print("=== Screen Information ===\n")
for (index, screen) in NSScreen.screens.enumerated() {
    let isMain = screen == NSScreen.main
    print("Screen \(index)\(isMain ? " (main)" : ""):")
    print("  Frame: \(screen.frame)")
    print("  VisibleFrame: \(screen.visibleFrame)")
    if #available(macOS 12.0, *) {
        print("  SafeAreaInsets: \(screen.safeAreaInsets)")
    }
    print("")
}

// MARK: - Explore SystemUIServer

print("=== SystemUIServer Menu Bars ===\n")

let runningApps = NSWorkspace.shared.runningApplications
if let systemUI = runningApps.first(where: { $0.bundleIdentifier == "com.apple.systemuiserver" }) {
    let appElement = AXUIElementCreateApplication(systemUI.processIdentifier)
    
    print("Attributes of SystemUIServer app element:")
    let attrs = getAttributeNames(appElement)
    for attr in attrs {
        print("  - \(attr)")
    }
    print("")
    
    // Check AXExtrasMenuBar
    var extras: CFTypeRef?
    if AXUIElementCopyAttributeValue(appElement, "AXExtrasMenuBar" as CFString, &extras) == .success {
        print("AXExtrasMenuBar found!")
        if let pos = getPosition(extras as! AXUIElement) {
            print("  Position: \(pos)")
        }
    }
    
    // Check for multiple menu bars
    var menuBars: CFTypeRef?
    if AXUIElementCopyAttributeValue(appElement, "AXMenuBars" as CFString, &menuBars) == .success,
       let bars = menuBars as? [AXUIElement] {
        print("\nAXMenuBars count: \(bars.count)")
        for (i, bar) in bars.enumerated() {
            print("  Bar \(i):")
            if let pos = getPosition(bar) {
                print("    Position: \(pos)")
            }
        }
    }
}

// MARK: - Explore Control Center

print("\n=== Control Center Menu Extras ===\n")

if let controlCenter = runningApps.first(where: { $0.bundleIdentifier == "com.apple.controlcenter" }) {
    let appElement = AXUIElementCreateApplication(controlCenter.processIdentifier)
    
    print("Attributes of Control Center app element:")
    let attrs = getAttributeNames(appElement)
    for attr in attrs {
        print("  - \(attr)")
    }
    
    // Check AXExtrasMenuBar
    var extras: CFTypeRef?
    if AXUIElementCopyAttributeValue(appElement, "AXExtrasMenuBar" as CFString, &extras) == .success,
       let extrasElement = extras {
        print("\nAXExtrasMenuBar found!")
        let extrasAX = extrasElement as! AXUIElement
        if let pos = getPosition(extrasAX), let size = getSize(extrasAX) {
            print("  Position: \(pos), Size: \(size)")
        }
        
        // Get children
        var children: CFTypeRef?
        if AXUIElementCopyAttributeValue(extrasAX, kAXChildrenAttribute as CFString, &children) == .success,
           let childArray = children as? [AXUIElement] {
            print("  Children count: \(childArray.count)")
            for (i, child) in childArray.enumerated() {
                if let pos = getPosition(child), let size = getSize(child) {
                    let title: String? = getAttributeValue(child, kAXTitleAttribute as String)
                    let desc: String? = getAttributeValue(child, kAXDescriptionAttribute as String)
                    print("    Child \(i): pos=\(pos), size=\(size), title=\(title ?? "nil"), desc=\(desc ?? "nil")")
                }
            }
        }
    }
}

// MARK: - Explore Third-party Apps

print("\n=== Third-party App Menu Extras ===\n")

// Test with a few common apps
let testApps = [
    "com.raycast.macos",
    "com.tencent.xinWeChat",
    "com.lark.Lark",
    "com.electron.lark"
]

for bundleId in testApps {
    if let app = runningApps.first(where: { $0.bundleIdentifier == bundleId }) {
        print("\(app.localizedName ?? bundleId):")
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        
        let attrs = getAttributeNames(appElement)
        print("  All attributes: \(attrs)")
        
        // Check AXExtrasMenuBar
        var extras: CFTypeRef?
        if AXUIElementCopyAttributeValue(appElement, "AXExtrasMenuBar" as CFString, &extras) == .success,
           let extrasElement = extras {
            let extrasAX = extrasElement as! AXUIElement
            if let pos = getPosition(extrasAX), let size = getSize(extrasAX) {
                print("  AXExtrasMenuBar: pos=\(pos), size=\(size)")
                
                // Which screen is this on?
                for (i, screen) in NSScreen.screens.enumerated() {
                    if screen.frame.contains(CGPoint(x: pos.x, y: pos.y)) {
                        print("  -> On screen \(i)")
                        break
                    }
                }
            }
            
            // Check all attributes of AXExtrasMenuBar
            let extrasAttrs = getAttributeNames(extrasAX)
            print("  AXExtrasMenuBar attributes: \(extrasAttrs)")
            
            // Check actions
            let actions = getActionNames(extrasAX)
            print("  AXExtrasMenuBar actions: \(actions)")
            
            // Check for children (maybe multiple buttons for multiple screens?)
            var children: CFTypeRef?
            if AXUIElementCopyAttributeValue(extrasAX, kAXChildrenAttribute as CFString, &children) == .success,
               let childArray = children as? [AXUIElement] {
                print("  Children count: \(childArray.count)")
                for (i, child) in childArray.enumerated() {
                    if let pos = getPosition(child), let size = getSize(child) {
                        print("    Child \(i): pos=\(pos), size=\(size)")
                        print("      Attributes: \(getAttributeNames(child))")
                        print("      Actions: \(getActionNames(child))")
                    }
                }
            }
        } else {
            print("  No AXExtrasMenuBar")
        }
        print("")
    }
}

// MARK: - System-wide element at specific positions

print("\n=== Element at Menu Bar Positions (each screen) ===\n")

for (index, screen) in NSScreen.screens.enumerated() {
    // Menu bar is at y = screen.frame.maxY - menuBarHeight
    // But in CG coordinates, y=0 is at top
    let menuBarY: CGFloat = 12  // Approximate center of menu bar
    let testX = screen.frame.origin.x + screen.frame.width - 100  // Right side of screen
    
    print("Screen \(index) - Testing position (\(testX), \(menuBarY)):")
    
    let systemWide = AXUIElementCreateSystemWide()
    var element: AXUIElement?
    let result = AXUIElementCopyElementAtPosition(systemWide, Float(testX), Float(menuBarY), &element)
    
    if result == .success, let elem = element {
        let role: String? = getAttributeValue(elem, kAXRoleAttribute as String)
        let title: String? = getAttributeValue(elem, kAXTitleAttribute as String)
        let desc: String? = getAttributeValue(elem, kAXDescriptionAttribute as String)
        if let pos = getPosition(elem), let size = getSize(elem) {
            print("  Found: role=\(role ?? "nil"), title=\(title ?? "nil"), desc=\(desc ?? "nil")")
            print("  Position: \(pos), Size: \(size)")
        }
        
        // Get parent chain to understand hierarchy
        var parent: CFTypeRef?
        if AXUIElementCopyAttributeValue(elem, kAXParentAttribute as CFString, &parent) == .success,
           let parentElem = parent {
            let parentRole: String? = getAttributeValue(parentElem as! AXUIElement, kAXRoleAttribute as String)
            print("  Parent role: \(parentRole ?? "nil")")
        }
    } else {
        print("  No element found at this position (result: \(result.rawValue))")
    }
    print("")
}

print("=== Done ===")
