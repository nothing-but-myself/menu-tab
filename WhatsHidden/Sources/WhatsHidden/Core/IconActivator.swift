import Cocoa
import ApplicationServices

// MARK: - Icon Activator
/// 负责激活菜单栏图标
class IconActivator {
    static let shared = IconActivator()
    
    // JXA 脚本缓存
    private var scriptCache: [String: NSAppleScript] = [:]
    
    private init() {}
    
    // MARK: - Public API
    
    /// 关闭已打开的菜单
    func dismissCurrentMenu() async {
        NSRunningApplication.current.activate()
        sendEscapeKey()
        try? await Task.sleep(nanoseconds: 50_000_000)  // 50ms
    }
    
    /// 激活图标菜单
    func activateIcon(_ icon: StatusBarIcon) {
        // 重新获取最新位置
        let icons = IconFetcher.shared.getIcons()
        guard let currentIcon = icons.first(where: { $0.id == icon.id }) else {
            print("❌ 图标已失效：\(icon.name)")
            return
        }
        
        // 策略 1：递归查找支持 AXPress 的子元素
        if let button = findClickableChild(currentIcon.element) {
            if AXUIElementPerformAction(button, kAXPressAction as CFString) == .success {
                return
            }
        }
        
        // 策略 2：递归查找支持 AXShowMenu 的子元素
        if let menuElement = findShowMenuChild(currentIcon.element) {
            if AXUIElementPerformAction(menuElement, "AXShowMenu" as CFString) == .success {
                return
            }
        }
        
        // 策略 3：直接对容器尝试 AXShowMenu
        if AXUIElementPerformAction(currentIcon.element, "AXShowMenu" as CFString) == .success {
            return
        }
        
        // 策略 4：聚焦后 AXPress
        if AXUIElementSetAttributeValue(currentIcon.element, kAXFocusedAttribute as CFString, true as CFTypeRef) == .success {
            if AXUIElementPerformAction(currentIcon.element, kAXPressAction as CFString) == .success {
                return
            }
        }
        
        // 策略 5：JXA 终极方案
        clickViaJXA(appName: currentIcon.name, bundleId: currentIcon.bundleId)
    }
    
    // MARK: - Private
    
    private func sendEscapeKey() {
        let src = CGEventSource(stateID: .combinedSessionState)
        let escDown = CGEvent(keyboardEventSource: src, virtualKey: 0x35, keyDown: true)
        escDown?.post(tap: .cghidEventTap)
        let escUp = CGEvent(keyboardEventSource: src, virtualKey: 0x35, keyDown: false)
        escUp?.post(tap: .cghidEventTap)
    }
    
    private func clickViaJXA(appName: String, bundleId: String) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            autoreleasepool {
                if let cachedScript = self?.scriptCache[bundleId] {
                    var error: NSDictionary?
                    cachedScript.executeAndReturnError(&error)
                    return
                }
                
                let script = """
                (function() {
                    var se = Application("System Events");
                    var procs = se.processes.whose({bundleIdentifier: "\(bundleId)"});
                    if (procs.length > 0) {
                        var proc = procs[0];
                        var menuBar = proc.menuBars[0];
                        if (menuBar) {
                            var items = menuBar.menuBarItems();
                            if (items.length > 0) {
                                items[0].click();
                                return true;
                            }
                        }
                    }
                    return false;
                })();
                """
                
                if let appleScript = NSAppleScript(source: "ObjC.import('stdlib'); \(script)") {
                    var compileError: NSDictionary?
                    if appleScript.compileAndReturnError(&compileError) {
                        DispatchQueue.main.async {
                            self?.scriptCache[bundleId] = appleScript
                        }
                    }
                    var error: NSDictionary?
                    appleScript.executeAndReturnError(&error)
                }
            }
        }
    }
    
    private func findClickableChild(_ element: AXUIElement) -> AXUIElement? {
        var actionsRef: CFArray?
        if AXUIElementCopyActionNames(element, &actionsRef) == .success,
           let actions = actionsRef as? [String],
           actions.contains(kAXPressAction) {
            return element
        }
        
        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let children = childrenRef as? [AXUIElement] else {
            return nil
        }
        
        for child in children {
            if let found = findClickableChild(child) {
                return found
            }
        }
        return nil
    }
    
    private func findShowMenuChild(_ element: AXUIElement) -> AXUIElement? {
        var actionsRef: CFArray?
        if AXUIElementCopyActionNames(element, &actionsRef) == .success,
           let actions = actionsRef as? [String],
           actions.contains("AXShowMenu") {
            return element
        }
        
        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let children = childrenRef as? [AXUIElement] else {
            return nil
        }
        
        for child in children {
            if let found = findShowMenuChild(child) {
                return found
            }
        }
        return nil
    }
}
