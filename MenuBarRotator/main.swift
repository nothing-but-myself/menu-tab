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

    /// 是否有刘海（使用 safeAreaInsets 判断，苹果官方推荐方式）
    static var hasNotch: Bool {
        guard let screen = NSScreen.main else { return false }
        // 菜单栏通常高度 24，刘海屏的安全区域顶部通常 > 30
        if #available(macOS 12.0, *) {
            return screen.safeAreaInsets.top > 24
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
        "macOS \(osMajor).\(osMinor), \(isAppleSilicon ? "Apple Silicon" : "Intel"), 刘海：\(hasNotch ? "有" : "无")"
    }
}

// MARK: - Configuration
struct Config: Codable {
    var onlyShowHidden: Bool      // 只在隐藏的图标之间切换
    var ignoredApps: [String]     // 忽略列表（不参与切换的应用 Bundle ID）

    static let configURL: URL = {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/menu-bar-rotater")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("config.json")
    }()

    static var `default`: Config {
        Config(onlyShowHidden: false, ignoredApps: [])
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
struct StatusBarIcon: Identifiable, Equatable {
    let id: Int  // 使用 AXUIElement 的哈希值作为唯一标识
    let name: String
    let bundleId: String
    let element: AXUIElement
    let x: CGFloat
    let y: CGFloat
    let width: CGFloat

    var centerX: CGFloat { x + width / 2 }
    var centerY: CGFloat { y + 12 }

    static func == (lhs: StatusBarIcon, rhs: StatusBarIcon) -> Bool {
        return lhs.id == rhs.id
    }
}

// MARK: - Status Bar Manager
class StatusBarManager {
    static let shared = StatusBarManager()

    var config = Config.load()

    // 自己的 bundle id 和 pid
    private let selfBundleId = Bundle.main.bundleIdentifier ?? "MenuBarRotator"
    private let selfPid = ProcessInfo.processInfo.processIdentifier

    // 图标缓存（使用 Serial Queue 保护并发访问）
    private var cachedIcons: [StatusBarIcon] = []
    private var lastCacheTime: Date = .distantPast
    private let cacheTimeout: TimeInterval = 2.0
    private var isPreloading = false
    private let dataQueue = DispatchQueue(label: "com.rotator.data")

    // JXA 脚本缓存（避免重复编译）
    private var scriptCache: [String: NSAppleScript] = [:]

    // 私有初始化，自动启动监听
    private init() {
        setupNotifications()
    }

    /// 监听应用启动/退出通知
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
            self?.lastCacheTime = .distantPast
        }
    }

    /// 预加载缓存（在 Ctrl 按下时调用，后台执行）
    func preloadCache() {
        dataQueue.async { [weak self] in
            guard let self = self, !self.isPreloading else { return }
            self.isPreloading = true

            DispatchQueue.global(qos: .userInitiated).async {
                let icons = self.fetchAllIcons()
                self.dataQueue.async {
                    self.cachedIcons = icons
                    self.lastCacheTime = Date()
                    self.isPreloading = false
                }
            }
        }
    }

    /// 同步获取图标（使用缓存）
    func getIcons(excludeSelf: Bool = true) -> [StatusBarIcon] {
        return dataQueue.sync { [self] in
            // 使用缓存（即使过期也先返回旧数据，保证 UI 响应）
            if !cachedIcons.isEmpty {
                return excludeSelf ? cachedIcons.filter { $0.bundleId != selfBundleId } : cachedIcons
            }
            // 首次调用，同步获取（阻塞但保证线程安全）
            let icons = fetchAllIcons()
            cachedIcons = icons
            lastCacheTime = Date()
            return excludeSelf ? cachedIcons.filter { $0.bundleId != selfBundleId } : cachedIcons
        }
    }

    /// 异步获取图标（强制刷新）
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
                    self.lastCacheTime = Date()
                }
                // 返回时排除自己
                let filtered = icons.filter { $0.bundleId != self.selfBundleId }
                continuation.resume(returning: filtered)
            }
        }
    }

    // MARK: - 忽略列表管理

    /// 检查应用是否被忽略
    func isIgnored(_ bundleId: String) -> Bool {
        return config.ignoredApps.contains(bundleId)
    }

    /// 切换应用的忽略状态
    func toggleIgnore(_ bundleId: String) {
        if let index = config.ignoredApps.firstIndex(of: bundleId) {
            config.ignoredApps.remove(at: index)
        } else {
            config.ignoredApps.append(bundleId)
        }
        config.save()
    }

    /// 实际获取所有图标（IPC 调用，可能耗时）
    private func fetchAllIcons() -> [StatusBarIcon] {
        var icons: [StatusBarIcon] = []
        var seenElementIds = Set<Int>()  // 使用元素 ID 去重，允许同一 App 多个图标

        let runningApps = NSWorkspace.shared.runningApplications
        for app in runningApps {
            guard let bundleId = app.bundleIdentifier else { continue }

            // 跳过自己（使用 pid 更可靠）
            if app.processIdentifier == selfPid { continue }
            if bundleId.hasPrefix("com.apple.") { continue }

            let appElement = AXUIElementCreateApplication(app.processIdentifier)
            var extras: CFTypeRef?

            // AXUIElement 是 CFTypeRef，直接转换
            guard AXUIElementCopyAttributeValue(appElement, "AXExtrasMenuBar" as CFString, &extras) == .success,
                  let extrasRef = extras else { continue }

            // CFTypeRef -> AXUIElement（安全转换，CFGetTypeID 验证）
            guard CFGetTypeID(extrasRef) == AXUIElementGetTypeID() else { continue }
            let extrasElement = extrasRef as! AXUIElement
            guard let pos = getPosition(extrasElement),
                  let size = getSize(extrasElement),
                  size.width > 0 && pos.y < 50 else { continue }

            // 使用 CFHash 生成唯一 ID
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


    // MARK: - Switcher Actions

    /// 关闭已打开的菜单（异步，解决竞态条件）
    func dismissCurrentMenu() async {
        // 1. 激活自己的应用（利用系统焦点机制，macOS 会自动关闭其他菜单）
        NSRunningApplication.current.activate()

        // 2. 发送 ESC（补刀，处理 Lark 等顽固应用）
        sendEscapeKey()

        // 3. 等待系统处理完关闭动画（解决竞态条件）
        try? await Task.sleep(nanoseconds: 50_000_000)  // 50ms
    }

    /// 发送 ESC 键
    private func sendEscapeKey() {
        let src = CGEventSource(stateID: .combinedSessionState)
        let escDown = CGEvent(keyboardEventSource: src, virtualKey: 0x35, keyDown: true)
        escDown?.post(tap: .cghidEventTap)
        let escUp = CGEvent(keyboardEventSource: src, virtualKey: 0x35, keyDown: false)
        escUp?.post(tap: .cghidEventTap)
    }

    /// 通过发送 Escape 键关闭任何已打开的菜单
    private func dismissOpenMenu() {
        let src = CGEventSource(stateID: .combinedSessionState)

        // 发送 Escape 键按下
        let escDown = CGEvent(keyboardEventSource: src, virtualKey: 0x35, keyDown: true)
        escDown?.post(tap: .cghidEventTap)

        // 发送 Escape 键松开
        let escUp = CGEvent(keyboardEventSource: src, virtualKey: 0x35, keyDown: false)
        escUp?.post(tap: .cghidEventTap)

        usleep(50000)  // 等待菜单关闭
    }

    /// 触发菜单栏显示（用于全屏模式）
    private func revealMenuBar() {
        let src = CGEventSource(stateID: .combinedSessionState)
        let screenWidth = NSScreen.main?.frame.width ?? 1470

        // 将鼠标移到屏幕右上角（避开刘海区域），触发菜单栏显示
        let topRight = CGPoint(x: screenWidth - 100, y: 0)
        CGEvent(mouseEventSource: src, mouseType: .mouseMoved, mouseCursorPosition: topRight, mouseButton: .left)?.post(tap: .cghidEventTap)

        // 等待菜单栏动画完成（全屏模式需要更长时间）
        usleep(500000)  // 500ms
    }

    /// 判断图标是否在刘海区域（考虑图标宽度）
    /// 使用 safeAreaInsets 动态计算刘海区域（macOS 12+）
    func isIconHidden(_ icon: StatusBarIcon) -> Bool {
        guard let screen = NSScreen.main else { return false }

        // 使用 safeAreaInsets 获取刘海区域（macOS 12+）
        // safeAreaInsets.top > 0 表示有刘海
        let safeArea = screen.safeAreaInsets
        if safeArea.top == 0 {
            // 没有刘海，所有图标都可见
            return false
        }

        // 刘海区域计算：屏幕中央，宽度约为 safeAreaInsets 暗示的区域
        // 由于 safeAreaInsets 只给出顶部高度，刘海宽度需要估算
        // 实际刘海宽度约 200-240px，我们用屏幕中央 ± 刘海宽度/2
        let screenWidth = screen.frame.width
        let notchWidth: CGFloat = 240  // 保守估计，覆盖所有机型
        let notchStart = (screenWidth / 2) - (notchWidth / 2)
        let notchEnd = (screenWidth / 2) + (notchWidth / 2)

        let iconLeft = icon.x
        let iconRight = icon.x + icon.width

        return !(iconRight < notchStart || iconLeft > notchEnd)
    }

    /// 激活图标菜单（多策略尝试）
    func activateIcon(icon: StatusBarIcon) {
        // 重新获取图标最新位置，使用 ID 精确匹配（解决同一 App 多个图标的问题）
        let icons = getIcons(excludeSelf: true)
        guard let currentIcon = icons.first(where: { $0.id == icon.id }) else {
            print("❌ 图标已失效或找不到：\(icon.name)")
            return
        }

        // 策略 1：递归查找支持 AXPress 的子元素（深度穿透）
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

        // 策略 5：JXA 终极方案（使用 AppleScript，不依赖鼠标）
        // 注意：JXA 对同一 App 多图标有局限性，尽量在前 4 步解决
        clickViaJXA(appName: currentIcon.name, bundleId: currentIcon.bundleId)
    }

    /// 使用 JXA (JavaScript for Automation) 点击菜单栏图标
    /// 这是终极方案，可以穿透刘海区域
    private func clickViaJXA(appName: String, bundleId: String) {
        // 在后台线程执行，避免阻塞 UI（System Events 可能卡顿）
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            autoreleasepool {
                // 检查缓存中是否有编译好的脚本
                if let cachedScript = self?.scriptCache[bundleId] {
                    var error: NSDictionary?
                    cachedScript.executeAndReturnError(&error)
                    return
                }

                // 创建新脚本
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
                    // 编译并缓存（需要在主线程更新缓存）
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

    /// 递归查找可点击的子元素（深度穿透，不限制角色类型）
    private func findClickableChild(_ element: AXUIElement) -> AXUIElement? {
        // 先检查当前元素是否支持 AXPress
        var actionsRef: CFArray?
        if AXUIElementCopyActionNames(element, &actionsRef) == .success,
           let actions = actionsRef as? [String],
           actions.contains(kAXPressAction) {
            return element
        }

        // 遍历所有子元素
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

    /// 递归查找支持 AXShowMenu 的子元素
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

// MARK: - Switcher Panel (Cmd+Tab style UI)
class SwitcherPanel: NSPanel {
    private var iconViews: [NSImageView] = []
    private var iconContainers: [NSView] = []  // 存储图标容器用于鼠标交互
    private var hiddenIndicators: [NSView] = []  // 刘海遮挡标记
    private var nameLabel: NSTextField!
    private var selectionBox: NSBox!
    private var containerView: NSView!
    private var visualEffectView: NSVisualEffectView!

    var icons: [StatusBarIcon] = []
    private var isConfiguring = false  // 配置期间禁用动画
    var selectedIndex: Int = 0 {
        didSet {
            if !isConfiguring {
                updateSelection(animated: true)
            }
        }
    }

    override init(contentRect: NSRect, styleMask style: NSWindow.StyleMask, backing backingStoreType: NSWindow.BackingStoreType, defer flag: Bool) {
        super.init(contentRect: contentRect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)

        // statusBar 层级确保在全屏应用之上（Bilibili、YouTube、Keynote 等）
        self.level = .statusBar
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = true
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.alphaValue = 0  // 初始透明，用于动画

        setupUI()
    }

    private func setupUI() {
        visualEffectView = NSVisualEffectView(frame: .zero)
        visualEffectView.material = .hudWindow
        visualEffectView.state = .active
        visualEffectView.wantsLayer = true
        visualEffectView.layer?.cornerRadius = 12
        visualEffectView.layer?.masksToBounds = true

        contentView = visualEffectView

        containerView = NSView(frame: .zero)
        visualEffectView.addSubview(containerView)

        selectionBox = NSBox(frame: .zero)
        selectionBox.boxType = .custom
        selectionBox.borderWidth = 0  // 无边框，更现代
        selectionBox.cornerRadius = 10
        selectionBox.fillColor = NSColor.labelColor.withAlphaComponent(0.12)  // 半透明高亮背景
        selectionBox.wantsLayer = true
        containerView.addSubview(selectionBox)

        nameLabel = NSTextField(labelWithString: "")
        nameLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        nameLabel.textColor = .labelColor
        nameLabel.alignment = .center
        visualEffectView.addSubview(nameLabel)
    }

    func configure(with icons: [StatusBarIcon]) {
        self.icons = icons

        // Clear old views and tracking areas
        iconContainers.forEach { container in
            container.trackingAreas.forEach { container.removeTrackingArea($0) }
            container.removeFromSuperview()
        }
        iconContainers.removeAll()
        iconViews.removeAll()
        hiddenIndicators.removeAll()

        let iconSize: CGFloat = 48
        let padding: CGFloat = 16
        let spacing: CGFloat = 12

        let totalWidth = CGFloat(icons.count) * iconSize + CGFloat(icons.count - 1) * spacing + padding * 2
        let panelWidth = max(totalWidth, 200)
        let panelHeight: CGFloat = 100

        // 多屏幕支持：面板跟随鼠标位置
        let mouseLoc = NSEvent.mouseLocation
        let targetScreen = NSScreen.screens.first(where: { NSMouseInRect(mouseLoc, $0.frame, false) }) ?? NSScreen.main
        if let screen = targetScreen {
            let x = screen.frame.origin.x + (screen.frame.width - panelWidth) / 2
            let y = screen.frame.origin.y + (screen.frame.height - panelHeight) / 2 + 120
            setFrame(NSRect(x: x, y: y, width: panelWidth, height: panelHeight), display: true)
        }

        contentView?.frame = NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight)
        containerView.frame = NSRect(x: padding, y: 30, width: panelWidth - padding * 2, height: iconSize)

        // Create icon views
        for (index, icon) in icons.enumerated() {
            let xPos = CGFloat(index) * (iconSize + spacing)

            let iconContainer = NSView(frame: NSRect(x: xPos, y: 0, width: iconSize, height: iconSize))
            iconContainer.wantsLayer = true

            let imageView = NSImageView(frame: NSRect(x: 0, y: 0, width: iconSize, height: iconSize))

            // Get app icon
            if let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == icon.bundleId }) {
                imageView.image = app.icon
            } else {
                imageView.image = NSImage(systemSymbolName: "app.fill", accessibilityDescription: nil)
            }
            imageView.imageScaling = .scaleProportionallyUpOrDown

            iconContainer.addSubview(imageView)

            // 添加刘海遮挡标记（半透明遮罩 + 图标）- 使用统一的判断方法
            let isHidden = StatusBarManager.shared.isIconHidden(icon)
            if isHidden {
                let overlay = NSView(frame: NSRect(x: 0, y: 0, width: iconSize, height: iconSize))
                overlay.wantsLayer = true
                overlay.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.4).cgColor
                overlay.layer?.cornerRadius = 6
                iconContainer.addSubview(overlay)
                hiddenIndicators.append(overlay)

                // 小眼睛图标表示隐藏
                let eyeIcon = NSImageView(frame: NSRect(x: iconSize - 16, y: 2, width: 14, height: 14))
                eyeIcon.image = NSImage(systemSymbolName: "eye.slash.fill", accessibilityDescription: "Hidden")
                eyeIcon.contentTintColor = .white
                iconContainer.addSubview(eyeIcon)
            }

            // 添加鼠标追踪区域
            let trackingArea = NSTrackingArea(
                rect: iconContainer.bounds,
                options: [.mouseEnteredAndExited, .activeAlways],
                owner: self,
                userInfo: ["index": index]
            )
            iconContainer.addTrackingArea(trackingArea)

            containerView.addSubview(iconContainer)
            iconContainers.append(iconContainer)
            iconViews.append(imageView)
        }

        // Name label at bottom
        nameLabel.frame = NSRect(x: 0, y: 8, width: panelWidth, height: 18)

        // 每次都从第一个开始（和 Cmd+Tab 一样）
        // 使用 isConfiguring 防止 didSet 触发动画
        isConfiguring = true
        selectedIndex = 0
        isConfiguring = false
        updateSelection(animated: false)  // 瞬移到位，无动画
    }

    private func updateSelection(animated: Bool) {
        guard selectedIndex >= 0 && selectedIndex < iconViews.count else { return }

        let iconSize: CGFloat = 48
        let spacing: CGFloat = 12
        let boxPadding: CGFloat = 4

        let targetX = CGFloat(selectedIndex) * (iconSize + spacing) - boxPadding
        let targetFrame = NSRect(
            x: targetX,
            y: -boxPadding,
            width: iconSize + boxPadding * 2,
            height: iconSize + boxPadding * 2
        )

        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.15
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                selectionBox.animator().frame = targetFrame
            }
        } else {
            selectionBox.frame = targetFrame
        }

        // 更新名称，显示是否被遮挡（使用统一的判断方法）
        let icon = icons[selectedIndex]
        let isHidden = StatusBarManager.shared.isIconHidden(icon)

        nameLabel.stringValue = isHidden ? "\(icon.name) (隐藏)" : icon.name
    }

    func selectNext() {
        selectedIndex = (selectedIndex + 1) % icons.count
    }

    func selectPrev() {
        selectedIndex = (selectedIndex - 1 + icons.count) % icons.count
    }

    // 显示动画
    func showAnimated() {
        self.alphaValue = 0
        self.orderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            self.animator().alphaValue = 1
        }
    }

    // 隐藏动画
    func hideAnimated(completion: (() -> Void)? = nil) {
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.1
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            self.animator().alphaValue = 0
        }, completionHandler: {
            self.orderOut(nil)
            completion?()
        })
    }

    // MARK: - 鼠标交互支持

    override func mouseEntered(with event: NSEvent) {
        // 鼠标进入图标区域时，切换选中
        if let userInfo = event.trackingArea?.userInfo,
           let index = userInfo["index"] as? Int {
            selectedIndex = index
        }
    }

    override func mouseUp(with event: NSEvent) {
        // 鼠标点击直接确认
        SwitcherController.shared.confirm()
    }
}

// MARK: - Toast 提示
class ToastPanel: NSPanel {
    private var label: NSTextField!

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)

        self.level = .statusBar
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = true
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let visualEffect = NSVisualEffectView(frame: .zero)
        visualEffect.material = .hudWindow
        visualEffect.state = .active
        visualEffect.wantsLayer = true
        visualEffect.layer?.cornerRadius = 10
        visualEffect.layer?.masksToBounds = true
        contentView = visualEffect

        label = NSTextField(labelWithString: "")
        label.font = NSFont.systemFont(ofSize: 14, weight: .medium)
        label.textColor = .labelColor
        label.alignment = .center
        visualEffect.addSubview(label)
    }

    func show(message: String, duration: TimeInterval = 1.5) {
        label.stringValue = message

        // 计算尺寸
        let size = label.sizeThatFits(NSSize(width: 300, height: 50))
        let panelWidth = size.width + 40
        let panelHeight: CGFloat = 44

        // 定位到鼠标所在屏幕中央
        let mouseLoc = NSEvent.mouseLocation
        let targetScreen = NSScreen.screens.first(where: { NSMouseInRect(mouseLoc, $0.frame, false) }) ?? NSScreen.main
        if let screen = targetScreen {
            let x = screen.frame.origin.x + (screen.frame.width - panelWidth) / 2
            let y = screen.frame.origin.y + (screen.frame.height - panelHeight) / 2 + 50
            setFrame(NSRect(x: x, y: y, width: panelWidth, height: panelHeight), display: true)
        }

        contentView?.frame = NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight)
        label.frame = NSRect(x: 20, y: (panelHeight - size.height) / 2, width: panelWidth - 40, height: size.height)

        // 显示动画
        self.alphaValue = 0
        self.orderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            self.animator().alphaValue = 1
        }

        // 自动隐藏
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.2
                self?.animator().alphaValue = 0
            }, completionHandler: {
                self?.orderOut(nil)
            })
        }
    }
}

// MARK: - Switcher Controller
class SwitcherController {
    static let shared = SwitcherController()

    private var panel: SwitcherPanel?
    private var toastPanel: ToastPanel?
    private var icons: [StatusBarIcon] = []
    var isActive: Bool { panel?.isVisible ?? false }

    /// 根据配置过滤图标
    private func filterIcons(_ icons: [StatusBarIcon]) -> [StatusBarIcon] {
        let manager = StatusBarManager.shared
        var result = icons
        // 过滤掉忽略列表中的应用
        result = result.filter { !manager.isIgnored($0.bundleId) }
        // 如果只显示隐藏图标，过滤掉可见的
        if manager.config.onlyShowHidden {
            result = result.filter { manager.isIconHidden($0) }
        }
        return result
    }

    /// 显示提示信息
    private func showToast(_ message: String) {
        if toastPanel == nil {
            toastPanel = ToastPanel()
        }
        toastPanel?.show(message: message)
    }

    /// Generate empty state message
    private func emptyMessage(allIcons: [StatusBarIcon]) -> String {
        let manager = StatusBarManager.shared
        if allIcons.isEmpty {
            return "No third-party menu bar icons"
        }
        // Check if all ignored
        let nonIgnored = allIcons.filter { !manager.isIgnored($0.bundleId) }
        if nonIgnored.isEmpty {
            return "All icons are in ignore list"
        }
        // Check if all filtered by notch
        if manager.config.onlyShowHidden {
            return "No icons hidden by notch"
        }
        return "No icons to switch"
    }

    func show() {
        // 先使用缓存快速展示 UI
        let allIcons = StatusBarManager.shared.getIcons()
        icons = filterIcons(allIcons)

        if panel == nil {
            panel = SwitcherPanel(contentRect: .zero, styleMask: [], backing: .buffered, defer: false)
        }

        if icons.isEmpty {
            // 没有缓存或过滤后为空，异步加载
            Task {
                let freshIcons = await StatusBarManager.shared.getIconsAsync()
                await MainActor.run {
                    self.icons = self.filterIcons(freshIcons)
                    if self.icons.isEmpty {
                        self.showToast(self.emptyMessage(allIcons: freshIcons))
                        return
                    }
                    self.panel?.configure(with: self.icons)
                    self.panel?.showAnimated()
                }
            }
        } else {
            // 有缓存，直接显示
            panel?.configure(with: icons)
            panel?.showAnimated()

            // 后台刷新数据
            Task {
                let freshIcons = await StatusBarManager.shared.getIconsAsync()
                await MainActor.run {
                    let filtered = self.filterIcons(freshIcons)
                    // Diff: 只有 ID 序列变化时才刷新 UI（防止闪烁）
                    let newIds = filtered.map { $0.id }
                    let oldIds = self.icons.map { $0.id }
                    if newIds != oldIds {
                        self.icons = filtered
                        self.panel?.configure(with: self.icons)
                    }
                }
            }
        }
    }

    func selectNext() {
        panel?.selectNext()
    }

    func selectPrev() {
        panel?.selectPrev()
    }

    func confirm() {
        confirmSelection()
    }

    private func confirmSelection() {
        guard let panel = panel, panel.isVisible else { return }

        let selectedIndex = panel.selectedIndex
        guard selectedIndex >= 0 && selectedIndex < icons.count else {
            cancel()
            return
        }

        let selectedIcon = icons[selectedIndex]

        // 隐藏面板（立即响应用户操作）
        panel.hideAnimated()

        // 串行化执行：先关闭旧菜单，再激活新图标（解决竞态条件）
        Task {
            await StatusBarManager.shared.dismissCurrentMenu()
            StatusBarManager.shared.activateIcon(icon: selectedIcon)
        }
    }

    func cancel() {
        panel?.hideAnimated()
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}

// MARK: - Global Hotkey Manager
class HotkeyManager {
    static let shared = HotkeyManager()

    private var eventTap: CFMachPort?

    func start() {
        // Listen for keyDown and flagsChanged
        let eventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.flagsChanged.rawValue)

        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                // 检测 tap 被禁用，重新启用
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    if let tap = HotkeyManager.shared.eventTap {
                        CGEvent.tapEnable(tap: tap, enable: true)
                    }
                    return Unmanaged.passUnretained(event)
                }

                let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
                let flags = event.flags
                let eventType = type

                // 处理修饰键变化
                if eventType == .flagsChanged {
                    // Ctrl 按下时预加载缓存（提前准备数据）
                    if flags.contains(.maskControl) && !SwitcherController.shared.isActive {
                        StatusBarManager.shared.preloadCache()
                    }
                    // 松开 Ctrl 时确认选择（Cmd+Tab 风格）
                    if SwitcherController.shared.isActive && !flags.contains(.maskControl) {
                        DispatchQueue.main.async {
                            SwitcherController.shared.confirm()
                        }
                    }
                    return Unmanaged.passUnretained(event)
                }

                // Ctrl + ` : 打开 Switcher / 选择下一个
                // Ctrl + Shift + ` : 选择上一个
                if keyCode == 50 && flags.contains(.maskControl) && !flags.contains(.maskCommand) {
                    DispatchQueue.main.async {
                        if SwitcherController.shared.isActive {
                            if flags.contains(.maskShift) {
                                SwitcherController.shared.selectPrev()
                            } else {
                                SwitcherController.shared.selectNext()
                            }
                        } else {
                            SwitcherController.shared.show()
                        }
                    }
                    return nil
                }

                // Esc : 取消
                if keyCode == 53 && SwitcherController.shared.isActive {
                    DispatchQueue.main.async {
                        SwitcherController.shared.cancel()
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
        print("🖥  系统信息：\(SystemInfo.description)")

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
        // StatusBarManager 在 init 中自动设置了通知监听
        _ = StatusBarManager.shared  // 确保初始化
        HotkeyManager.shared.start()

        print("🚀 Menu Bar Rotator 已启动")
        print("   ⌃ `     打开切换器 / 选择下一个")
        print("   松开 ⌃  确认选择")
        print("   Esc     取消")
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

        // Hidden Icons Only
        let onlyHiddenItem = NSMenuItem(title: "Hidden Icons Only", action: #selector(toggleOnlyShowHidden), keyEquivalent: "")
        onlyHiddenItem.target = self
        onlyHiddenItem.state = StatusBarManager.shared.config.onlyShowHidden ? .on : .off
        onlyHiddenItem.image = NSImage(systemSymbolName: "eye.slash", accessibilityDescription: nil)
        menu.addItem(onlyHiddenItem)

        menu.addItem(NSMenuItem.separator())

        // Ignore List submenu
        let ignoreItem = NSMenuItem(title: "Ignore List", action: nil, keyEquivalent: "")
        ignoreItem.image = NSImage(systemSymbolName: "minus.circle", accessibilityDescription: nil)
        let ignoreSubmenu = NSMenu()

        // Get all icons
        let allIcons = StatusBarManager.shared.getIcons(excludeSelf: true)

        // Group by bundleId (show each app only once)
        var seenBundleIds = Set<String>()
        for icon in allIcons {
            guard !seenBundleIds.contains(icon.bundleId) else { continue }
            seenBundleIds.insert(icon.bundleId)

            let appItem = NSMenuItem(title: icon.name, action: #selector(toggleIgnoreApp(_:)), keyEquivalent: "")
            appItem.target = self
            appItem.representedObject = icon.bundleId
            appItem.state = StatusBarManager.shared.isIgnored(icon.bundleId) ? NSControl.StateValue.on : NSControl.StateValue.off
            // App icon from bundle
            if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: icon.bundleId) {
                let appIcon = NSWorkspace.shared.icon(forFile: appURL.path)
                appIcon.size = NSSize(width: 16, height: 16)
                appItem.image = appIcon
            }
            ignoreSubmenu.addItem(appItem)
        }

        if ignoreSubmenu.items.isEmpty {
            let emptyItem = NSMenuItem(title: "No Third-Party Icons", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            ignoreSubmenu.addItem(emptyItem)
        }

        ignoreItem.submenu = ignoreSubmenu
        menu.addItem(ignoreItem)

        menu.addItem(NSMenuItem.separator())

        // System info
        let infoItem = NSMenuItem(title: "System: \(SystemInfo.description)", action: nil, keyEquivalent: "")
        infoItem.isEnabled = false
        infoItem.image = NSImage(systemSymbolName: "info.circle", accessibilityDescription: nil)
        menu.addItem(infoItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        quitItem.image = NSImage(systemSymbolName: "power", accessibilityDescription: nil)
        menu.addItem(quitItem)

        statusItem?.menu = menu
    }

    @objc func toggleOnlyShowHidden() {
        StatusBarManager.shared.config.onlyShowHidden.toggle()
        StatusBarManager.shared.config.save()
        updateMenu()
    }

    @objc func toggleIgnoreApp(_ sender: NSMenuItem) {
        guard let bundleId = sender.representedObject as? String else { return }
        StatusBarManager.shared.toggleIgnore(bundleId)
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
