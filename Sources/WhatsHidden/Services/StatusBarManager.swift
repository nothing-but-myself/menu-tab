import Cocoa
import ApplicationServices

/// Core service for managing status bar icons
class StatusBarManager {
    static let shared = StatusBarManager()

    // Self bundle id and pid
    private let selfBundleId = Bundle.main.bundleIdentifier ?? "WhatsHidden"
    private let selfPid = ProcessInfo.processInfo.processIdentifier

    // Icon cache (protected by Serial Queue)
    private var cachedIcons: [StatusBarIcon] = []
    private var isPreloading = false
    private let dataQueue = DispatchQueue(label: "com.whatshidden.data")

    // JXA script cache
    private var scriptCache: [String: NSAppleScript] = [:]

    private init() {
        setupNotifications()
    }

    /// Listen for app launch/terminate notifications
    private func setupNotifications() {
        let workspace = NSWorkspace.shared
        workspace.notificationCenter.addObserver(
            self,
            selector: #selector(invalidateCache),
            name: NSWorkspace.didLaunchApplicationNotification,
            object: nil
        )
        workspace.notificationCenter.addObserver(
            self,
            selector: #selector(invalidateCache),
            name: NSWorkspace.didTerminateApplicationNotification,
            object: nil
        )
    }

    @objc private func invalidateCache() {
        dataQueue.async { [weak self] in
            self?.cachedIcons = []
        }
    }

    /// Preload cache (called when Ctrl is pressed)
    func preloadCache() {
        dataQueue.async { [weak self] in
            guard let self = self, !self.isPreloading else { return }
            self.isPreloading = true

            DispatchQueue.global(qos: .userInitiated).async {
                let icons = self.fetchAllIcons()
                self.dataQueue.async {
                    self.cachedIcons = icons
                    self.isPreloading = false
                }
            }
        }
    }

    /// Sync get icons (uses cache)
    func getIcons(excludeSelf: Bool = true) -> [StatusBarIcon] {
        return dataQueue.sync { [self] in
            if !cachedIcons.isEmpty {
                return excludeSelf ? cachedIcons.filter { $0.bundleId != selfBundleId } : cachedIcons
            }
            let icons = fetchAllIcons()
            cachedIcons = icons
            return excludeSelf ? cachedIcons.filter { $0.bundleId != selfBundleId } : cachedIcons
        }
    }

    /// Async get icons (force refresh)
    func getIconsAsync() async -> [StatusBarIcon] {
        return await withCheckedContinuation { [weak self] continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                guard let self = self else {
                    continuation.resume(returning: [])
                    return
                }
                let icons = self.fetchAllIcons()
                self.dataQueue.async {
                    self.cachedIcons = icons
                }
                let filtered = icons.filter { $0.bundleId != self.selfBundleId }
                continuation.resume(returning: filtered)
            }
        }
    }

    /// Fetch all icons (IPC call, may be slow)
    private func fetchAllIcons() -> [StatusBarIcon] {
        var icons: [StatusBarIcon] = []
        var seenElementIds = Set<Int>()

        let runningApps = NSWorkspace.shared.runningApplications
        for app in runningApps {
            guard let bundleId = app.bundleIdentifier else { continue }

            if app.processIdentifier == selfPid { continue }
            if bundleId.hasPrefix("com.apple.") { continue }

            let appElement = AXUIElementCreateApplication(app.processIdentifier)
            var extras: CFTypeRef?

            guard AXUIElementCopyAttributeValue(appElement, "AXExtrasMenuBar" as CFString, &extras) == .success,
                  let extrasRef = extras else { continue }

            guard CFGetTypeID(extrasRef) == AXUIElementGetTypeID() else { continue }
            let extrasElement = extrasRef as! AXUIElement
            guard let pos = getPosition(extrasElement),
                  let size = getSize(extrasElement),
                  size.width > 0 && pos.y < 50 else { continue }

            let elementId = Int(CFHash(extrasElement))
            if seenElementIds.contains(elementId) { continue }
            seenElementIds.insert(elementId)

            let name = app.localizedName ?? bundleId
            icons.append(StatusBarIcon(
                id: elementId,
                name: name,
                bundleId: bundleId,
                element: extrasElement,
                x: pos.x,
                y: pos.y,
                width: size.width
            ))
        }

        icons.sort { $0.x < $1.x }
        return icons
    }

    // MARK: - Hidden Detection

    /// Check if icon is hidden behind the notch
    func isIconHidden(_ icon: StatusBarIcon) -> Bool {
        guard let screen = findScreen(forIconX: icon.x, iconY: icon.y) else {
            return false
        }

        let safeArea = screen.safeAreaInsets
        if safeArea.top == 0 {
            return false
        }

        let screenWidth = screen.frame.width
        let screenOriginX = screen.frame.origin.x
        let notchWidth: CGFloat = 240
        let notchStart = screenOriginX + (screenWidth / 2) - (notchWidth / 2)
        let notchEnd = screenOriginX + (screenWidth / 2) + (notchWidth / 2)

        let iconLeft = icon.x
        let iconRight = icon.x + icon.width

        return !(iconRight < notchStart || iconLeft > notchEnd)
    }

    /// Get only hidden icons (behind notch)
    func getHiddenIcons() -> [StatusBarIcon] {
        return getIcons().filter { isIconHidden($0) }
    }

    /// Async get only hidden icons
    func getHiddenIconsAsync() async -> [StatusBarIcon] {
        let icons = await getIconsAsync()
        return icons.filter { isIconHidden($0) }
    }

    /// Find screen by icon's CG coordinates
    private func findScreen(forIconX iconX: CGFloat, iconY: CGFloat) -> NSScreen? {
        for screen in NSScreen.screens {
            let frame = screen.frame
            if iconX >= frame.origin.x && iconX < frame.origin.x + frame.width {
                return screen
            }
        }
        return NSScreen.main
    }

    // MARK: - Icon Activation

    /// Dismiss current menu
    func dismissCurrentMenu() async {
        NSRunningApplication.current.activate()
        sendEscapeKey()
        try? await Task.sleep(nanoseconds: 50_000_000)
    }

    private func sendEscapeKey() {
        let src = CGEventSource(stateID: .combinedSessionState)
        let escDown = CGEvent(keyboardEventSource: src, virtualKey: 0x35, keyDown: true)
        escDown?.post(tap: .cghidEventTap)
        let escUp = CGEvent(keyboardEventSource: src, virtualKey: 0x35, keyDown: false)
        escUp?.post(tap: .cghidEventTap)
    }

    /// Activate icon menu (multiple strategies)
    func activateIcon(icon: StatusBarIcon) {
        let icons = getIcons(excludeSelf: true)
        guard let currentIcon = icons.first(where: { $0.id == icon.id }) else {
            print("Icon not found: \(icon.name)")
            return
        }

        // Strategy 1: Find child with AXPress
        if let button = findClickableChild(currentIcon.element) {
            if AXUIElementPerformAction(button, kAXPressAction as CFString) == .success {
                return
            }
        }

        // Strategy 2: Find child with AXShowMenu
        if let menuElement = findShowMenuChild(currentIcon.element) {
            if AXUIElementPerformAction(menuElement, "AXShowMenu" as CFString) == .success {
                return
            }
        }

        // Strategy 3: Direct AXShowMenu on container
        if AXUIElementPerformAction(currentIcon.element, "AXShowMenu" as CFString) == .success {
            return
        }

        // Strategy 4: Focus then AXPress
        if AXUIElementSetAttributeValue(currentIcon.element, kAXFocusedAttribute as CFString, true as CFTypeRef) == .success {
            if AXUIElementPerformAction(currentIcon.element, kAXPressAction as CFString) == .success {
                return
            }
        }

        // Strategy 5: JXA fallback
        clickViaJXA(appName: currentIcon.name, bundleId: currentIcon.bundleId)
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

    // MARK: - Accessibility Helpers

    private func getPosition(_ element: AXUIElement) -> CGPoint? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &value) == .success,
              CFGetTypeID(value!) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        AXValueGetValue(value as! AXValue, .cgPoint, &point)
        return point
    }

    private func getSize(_ element: AXUIElement) -> CGSize? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &value) == .success,
              CFGetTypeID(value!) == AXValueGetTypeID() else { return nil }
        var size = CGSize.zero
        AXValueGetValue(value as! AXValue, .cgSize, &size)
        return size
    }
}
