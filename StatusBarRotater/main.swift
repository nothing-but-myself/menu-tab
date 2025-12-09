import Cocoa
import ApplicationServices

// MARK: - System Compatibility
struct SystemInfo {
    static let osVersion = ProcessInfo.processInfo.operatingSystemVersion
    static let osMajor = osVersion.majorVersion
    static let osMinor = osVersion.minorVersion

    /// 是否是 macOS 12+
    static var isMontereyOrLater: Bool {
        osMajor >= 12
    }

    /// 是否有刘海（M1/M2/M3 MacBook）
    static var hasNotch: Bool {
        guard isMontereyOrLater else { return false }
        // 检查是否是内置显示器且有刘海
        if let screen = NSScreen.main,
           let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID {
            // 内置显示器 + macOS 12+ + Apple Silicon 大概率有刘海
            return CGDisplayIsBuiltin(displayID) != 0 && isAppleSilicon
        }
        return false
    }

    /// 是否是 Apple Silicon
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

    /// 获取主显示器信息
    static func getMainScreenInfo() -> (width: CGFloat, height: CGFloat, hasNotch: Bool) {
        guard let screen = NSScreen.main else {
            return (1470, 956, false)
        }
        return (screen.frame.width, screen.frame.height, hasNotch)
    }

    /// 系统信息描述
    static var description: String {
        "macOS \(osMajor).\(osMinor), \(isAppleSilicon ? "Apple Silicon" : "Intel"), 刘海: \(hasNotch ? "有" : "无")"
    }
}

// MARK: - Configuration
struct Config: Codable {
    var pinnedApps: [String]  // 固定不轮换的应用 bundle id

    static let configURL: URL = {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/status-bar-rotater")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("config.json")
    }()

    static var `default`: Config {
        Config(pinnedApps: [])
    }

    static func load() -> Config {
        guard let data = try? Data(contentsOf: configURL),
              let config = try? JSONDecoder().decode(Config.self, from: data) else {
            return .default
        }
        return config
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            try? data.write(to: Config.configURL)
        }
    }
}

// MARK: - Status Bar Icon
struct StatusBarIcon {
    let name: String
    let bundleId: String
    let element: AXUIElement
    let x: CGFloat
    let y: CGFloat
    let width: CGFloat

    var centerX: CGFloat { x + width / 2 }
    var centerY: CGFloat { y + 12 }
}

// MARK: - Status Bar Manager
class StatusBarManager {
    static let shared = StatusBarManager()

    var config = Config.load()

    // 自己的 bundle id，永远不参与轮换
    private let selfBundleId = Bundle.main.bundleIdentifier ?? "StatusBarRotater"

    /// 获取所有第三方状态栏图标（按 X 坐标排序）
    func getIcons(excludePinned: Bool = true, excludeSelf: Bool = true) -> [StatusBarIcon] {
        var icons: [StatusBarIcon] = []

        let runningApps = NSWorkspace.shared.runningApplications
        for app in runningApps {
            guard let bundleId = app.bundleIdentifier else { continue }

            // 跳过系统应用
            if bundleId.hasPrefix("com.apple.") { continue }

            // 跳过自己
            if excludeSelf && (bundleId == selfBundleId || app.localizedName == "StatusBarRotater") { continue }

            // 跳过固定的应用
            if excludePinned && config.pinnedApps.contains(bundleId) { continue }

            let appElement = AXUIElementCreateApplication(app.processIdentifier)
            var extras: CFTypeRef?

            if AXUIElementCopyAttributeValue(appElement, "AXExtrasMenuBar" as CFString, &extras) == .success,
               let extrasElement = extras as! AXUIElement?,
               let pos = getPosition(extrasElement),
               let size = getSize(extrasElement),
               size.width > 0 && pos.y < 50 {

                let name = app.localizedName ?? bundleId
                icons.append(StatusBarIcon(
                    name: name,
                    bundleId: bundleId,
                    element: extrasElement,
                    x: pos.x,
                    y: pos.y,
                    width: size.width
                ))
            }
        }

        icons.sort { $0.x < $1.x }
        return icons
    }

    /// 获取自己的图标位置
    private func getSelfIcon() -> StatusBarIcon? {
        let runningApps = NSWorkspace.shared.runningApplications
        for app in runningApps {
            guard let bundleId = app.bundleIdentifier else { continue }

            if bundleId == selfBundleId || app.localizedName == "StatusBarRotater" {
                let appElement = AXUIElementCreateApplication(app.processIdentifier)
                var extras: CFTypeRef?

                if AXUIElementCopyAttributeValue(appElement, "AXExtrasMenuBar" as CFString, &extras) == .success,
                   let extrasElement = extras as! AXUIElement?,
                   let pos = getPosition(extrasElement),
                   let size = getSize(extrasElement),
                   size.width > 0 && pos.y < 50 {
                    return StatusBarIcon(
                        name: "StatusBarRotater",
                        bundleId: bundleId,
                        element: extrasElement,
                        x: pos.x,
                        y: pos.y,
                        width: size.width
                    )
                }
            }
        }
        return nil
    }

    /// 把自己移到最右边（紧贴系统图标）
    private func moveSelfToRight() {
        guard let selfIcon = getSelfIcon() else { return }
        let icons = getIcons(excludePinned: false, excludeSelf: true)
        guard let rightmost = icons.last else { return }

        // 如果自己已经在最右边，不需要移动
        if selfIcon.x > rightmost.x { return }

        let fromX = selfIcon.centerX
        let fromY = selfIcon.centerY
        let toX = rightmost.x + rightmost.width + 15
        let toY = rightmost.centerY

        usleep(100000) // 等待前一个操作完成
        simulateDrag(from: CGPoint(x: fromX, y: fromY), to: CGPoint(x: toX, y: toY))
    }

    /// 环形轮换：把第一个图标移到最后
    @discardableResult
    func rotateLeft() -> Bool {
        let icons = getIcons()
        guard icons.count >= 2 else {
            print("⚠️  可轮换的图标不足 2 个")
            return false
        }

        let first = icons[0]
        let last = icons[icons.count - 1]

        let fromX = first.centerX
        let fromY = first.centerY
        let toX = last.x + last.width + 15
        let toY = last.centerY

        simulateDrag(from: CGPoint(x: fromX, y: fromY), to: CGPoint(x: toX, y: toY))

        // 轮换后把自己移回最右边
        moveSelfToRight()
        return true
    }

    /// 环形轮换：把最后一个图标移到最前
    @discardableResult
    func rotateRight() -> Bool {
        let icons = getIcons()
        guard icons.count >= 2 else {
            print("⚠️  可轮换的图标不足 2 个")
            return false
        }

        let first = icons[0]
        let last = icons[icons.count - 1]

        let fromX = last.centerX
        let fromY = last.centerY
        let toX = first.x - 15
        let toY = first.centerY

        simulateDrag(from: CGPoint(x: fromX, y: fromY), to: CGPoint(x: toX, y: toY))

        // 轮换后把自己移回最右边
        moveSelfToRight()
        return true
    }

    /// 模拟 Command + 拖拽（优化版：更快、更流畅）
    private func simulateDrag(from: CGPoint, to: CGPoint) {
        // 记录鼠标原始位置
        let originalPosition = NSEvent.mouseLocation
        let screenHeight = NSScreen.main?.frame.height ?? 0
        let originalCGPoint = CGPoint(x: originalPosition.x, y: screenHeight - originalPosition.y)

        let src = CGEventSource(stateID: .combinedSessionState)

        // 1. 移动到起点
        CGEvent(mouseEventSource: src, mouseType: .mouseMoved, mouseCursorPosition: from, mouseButton: .left)?.post(tap: .cghidEventTap)
        usleep(30000)

        // 2. 按下 Command
        let cmdDown = CGEvent(keyboardEventSource: src, virtualKey: 0x37, keyDown: true)
        cmdDown?.flags = .maskCommand
        cmdDown?.post(tap: .cghidEventTap)
        usleep(30000)

        // 3. 鼠标按下
        let mouseDown = CGEvent(mouseEventSource: src, mouseType: .leftMouseDown, mouseCursorPosition: from, mouseButton: .left)
        mouseDown?.flags = .maskCommand
        mouseDown?.post(tap: .cghidEventTap)
        usleep(50000)

        // 4. 快速拖拽
        let steps = 8
        for i in 1...steps {
            let t = CGFloat(i) / CGFloat(steps)
            let x = from.x + (to.x - from.x) * t
            let y = from.y + (to.y - from.y) * t

            let drag = CGEvent(mouseEventSource: src, mouseType: .leftMouseDragged, mouseCursorPosition: CGPoint(x: x, y: y), mouseButton: .left)
            drag?.flags = .maskCommand
            drag?.post(tap: .cghidEventTap)
            usleep(8000)
        }

        // 5. 鼠标松开
        let mouseUp = CGEvent(mouseEventSource: src, mouseType: .leftMouseUp, mouseCursorPosition: to, mouseButton: .left)
        mouseUp?.flags = .maskCommand
        mouseUp?.post(tap: .cghidEventTap)
        usleep(20000)

        // 6. 松开 Command
        let cmdUp = CGEvent(keyboardEventSource: src, virtualKey: 0x37, keyDown: false)
        cmdUp?.post(tap: .cghidEventTap)

        // 7. 恢复鼠标位置
        usleep(20000)
        CGEvent(mouseEventSource: src, mouseType: .mouseMoved, mouseCursorPosition: originalCGPoint, mouseButton: .left)?.post(tap: .cghidEventTap)
    }

    // MARK: - 固定图标管理

    func togglePin(bundleId: String) {
        if config.pinnedApps.contains(bundleId) {
            config.pinnedApps.removeAll { $0 == bundleId }
        } else {
            config.pinnedApps.append(bundleId)
        }
        config.save()
    }

    func isPinned(bundleId: String) -> Bool {
        config.pinnedApps.contains(bundleId)
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

// MARK: - Global Hotkey Manager
class HotkeyManager {
    static let shared = HotkeyManager()

    private var eventTap: CFMachPort?

    func start() {
        let eventMask = (1 << CGEventType.keyDown.rawValue)

        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
                let flags = event.flags

                // Cmd + Shift + ← : 图标向左流动（右边移到左边）
                if keyCode == 123 && flags.contains(.maskCommand) && flags.contains(.maskShift) && !flags.contains(.maskAlternate) {
                    DispatchQueue.main.async {
                        StatusBarManager.shared.rotateRight()
                    }
                    return nil
                }

                // Cmd + Shift + → : 图标向右流动（左边移到右边）
                if keyCode == 124 && flags.contains(.maskCommand) && flags.contains(.maskShift) && !flags.contains(.maskAlternate) {
                    DispatchQueue.main.async {
                        StatusBarManager.shared.rotateLeft()
                    }
                    return nil
                }

                return Unmanaged.passUnretained(event)
            },
            userInfo: nil
        )

        guard let eventTap = eventTap else {
            print("❌ 无法创建事件监听，请检查辅助功能权限")
            return
        }

        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
    }
}

// MARK: - App Delegate
class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 系统兼容性检查
        print("🖥  系统信息: \(SystemInfo.description)")

        if !SystemInfo.isMontereyOrLater {
            print("⚠️  建议使用 macOS 12 (Monterey) 或更新版本")
        }

        if !SystemInfo.hasNotch {
            print("ℹ️  当前显示器没有刘海，但工具仍可使用")
        }

        // 权限检查
        if !checkPermissions() {
            print("⚠️  需要辅助功能权限才能正常工作")
        }

        setupStatusItem()
        HotkeyManager.shared.start()

        print("🚀 Status Bar Rotater 已启动")
        print("   ⌘ ⇧ ←  向左流动")
        print("   ⌘ ⇧ →  向右流动")
    }

    func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "arrow.left.arrow.right", accessibilityDescription: "Rotate")
        }

        updateMenu()
    }

    func updateMenu() {
        let menu = NSMenu()

        // 轮换操作
        var item = NSMenuItem(title: "向左流动 (⌘⇧←)", action: #selector(rotateRight), keyEquivalent: "")
        item.target = self
        menu.addItem(item)

        item = NSMenuItem(title: "向右流动 (⌘⇧→)", action: #selector(rotateLeft), keyEquivalent: "")
        item.target = self
        menu.addItem(item)

        menu.addItem(NSMenuItem.separator())

        // 固定图标子菜单
        let pinMenu = NSMenu()
        let allIcons = StatusBarManager.shared.getIcons(excludePinned: false, excludeSelf: true)

        if allIcons.isEmpty {
            let emptyItem = NSMenuItem(title: "无第三方图标", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            pinMenu.addItem(emptyItem)
        } else {
            for icon in allIcons {
                let pinItem = NSMenuItem(title: icon.name, action: #selector(togglePinIcon(_:)), keyEquivalent: "")
                pinItem.target = self
                pinItem.representedObject = icon.bundleId
                pinItem.state = StatusBarManager.shared.isPinned(bundleId: icon.bundleId) ? .on : .off
                pinMenu.addItem(pinItem)
            }
        }

        let pinMenuItem = NSMenuItem(title: "固定图标", action: nil, keyEquivalent: "")
        pinMenuItem.submenu = pinMenu
        menu.addItem(pinMenuItem)

        menu.addItem(NSMenuItem.separator())

        // 系统信息
        let infoItem = NSMenuItem(title: "系统: \(SystemInfo.description)", action: nil, keyEquivalent: "")
        infoItem.isEnabled = false
        menu.addItem(infoItem)

        menu.addItem(NSMenuItem.separator())

        item = NSMenuItem(title: "退出", action: #selector(quit), keyEquivalent: "q")
        item.target = self
        menu.addItem(item)

        statusItem?.menu = menu
    }

    @objc func rotateLeft() {
        StatusBarManager.shared.rotateLeft()
    }

    @objc func rotateRight() {
        StatusBarManager.shared.rotateRight()
    }

    @objc func togglePinIcon(_ sender: NSMenuItem) {
        guard let bundleId = sender.representedObject as? String else { return }
        StatusBarManager.shared.togglePin(bundleId: bundleId)
        updateMenu()
    }

    @objc func quit() {
        NSApp.terminate(nil)
    }

    @discardableResult
    func checkPermissions() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        return AXIsProcessTrustedWithOptions(options as CFDictionary)
    }
}

// MARK: - Main
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
