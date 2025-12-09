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
            .appendingPathComponent(".config/menu-bar-rotator")
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
    private let selfBundleId = Bundle.main.bundleIdentifier ?? "MenuBarRotator"

    /// 获取所有第三方状态栏图标（按 X 坐标排序）
    func getIcons(excludePinned: Bool = true, excludeSelf: Bool = true) -> [StatusBarIcon] {
        var icons: [StatusBarIcon] = []

        let runningApps = NSWorkspace.shared.runningApplications
        for app in runningApps {
            guard let bundleId = app.bundleIdentifier else { continue }

            // 跳过系统应用
            if bundleId.hasPrefix("com.apple.") { continue }

            // 跳过自己
            if excludeSelf && (bundleId == selfBundleId || app.localizedName == "MenuBarRotator") { continue }

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

            if bundleId == selfBundleId || app.localizedName == "MenuBarRotator" {
                let appElement = AXUIElementCreateApplication(app.processIdentifier)
                var extras: CFTypeRef?

                if AXUIElementCopyAttributeValue(appElement, "AXExtrasMenuBar" as CFString, &extras) == .success,
                   let extrasElement = extras as! AXUIElement?,
                   let pos = getPosition(extrasElement),
                   let size = getSize(extrasElement),
                   size.width > 0 && pos.y < 50 {
                    return StatusBarIcon(
                        name: "MenuBarRotator",
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

    // MARK: - Switcher Actions

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
    func isIconHidden(_ icon: StatusBarIcon) -> Bool {
        let screenWidth = NSScreen.main?.frame.width ?? 1470
        let notchStart = (screenWidth / 2) - 120
        let notchEnd = (screenWidth / 2) + 120

        // 图标的右边缘在刘海开始之前 = 可见（左侧）
        // 图标的左边缘在刘海结束之后 = 可见（右侧）
        // 否则 = 被遮挡
        let iconLeft = icon.x
        let iconRight = icon.x + icon.width

        return !(iconRight < notchStart || iconLeft > notchEnd)
    }

    /// 激活图标菜单（多策略尝试）
    func activateIcon(icon: StatusBarIcon) {
        // 先关闭任何已打开的菜单
        dismissOpenMenu()

        // 显示菜单栏（全屏模式）
        revealMenuBar()

        // 重新获取图标最新位置
        var icons = getIcons(excludePinned: false, excludeSelf: true)
        guard var currentIcon = icons.first(where: { $0.bundleId == icon.bundleId }) else {
            // 图标可能已消失，尝试用旧的 element 直接触发
            AXUIElementPerformAction(icon.element, kAXPressAction as CFString)
            return
        }

        // 检查图标是否在刘海区域
        if isIconHidden(currentIcon) {
            // 策略: 通过轮换把隐藏图标移到可见区域
            // 计算需要轮换多少次
            let screenWidth = NSScreen.main?.frame.width ?? 1470
            let notchEnd = (screenWidth / 2) + 120

            // 找到目标图标在列表中的位置
            guard let targetIndex = icons.firstIndex(where: { $0.bundleId == icon.bundleId }) else {
                return
            }

            // 找到第一个可见图标的位置
            guard let firstVisibleIndex = icons.firstIndex(where: { !isIconHidden($0) && $0.x > notchEnd }) else {
                // 没有可见图标，直接尝试点击
                clickIconDirectly(currentIcon)
                return
            }

            // 如果目标在可见区域左边，需要向右轮换（把左边的移到右边）
            if targetIndex < firstVisibleIndex {
                let rotationsNeeded = firstVisibleIndex - targetIndex
                for _ in 0..<rotationsNeeded {
                    rotateLeft()  // 把最左边的图标移到最右边
                    usleep(300000)  // 等待轮换完成
                }
            }

            // 轮换后重新获取位置
            usleep(200000)
            icons = getIcons(excludePinned: false, excludeSelf: true)
            guard let updatedIcon = icons.first(where: { $0.bundleId == icon.bundleId }) else {
                return
            }
            currentIcon = updatedIcon
        }

        // 现在图标应该在可见区域了，尝试激活
        // 方法1: AX Press
        let result = AXUIElementPerformAction(currentIcon.element, kAXPressAction as CFString)
        if result == .success {
            return
        }

        // 方法2: 模拟点击
        clickIconDirectly(currentIcon)
    }

    /// 直接点击图标（不移动）
    private func clickIconDirectly(_ icon: StatusBarIcon) {
        let originalPosition = NSEvent.mouseLocation
        let screenHeight = NSScreen.main?.frame.height ?? 0
        let originalCGPoint = CGPoint(x: originalPosition.x, y: screenHeight - originalPosition.y)
        clickIcon(icon, restoreTo: originalCGPoint)
    }

    /// 旧方法名保留兼容
    func moveToVisibleAndClick(icon: StatusBarIcon) {
        activateIcon(icon: icon)
    }

    /// 模拟点击图标，完成后恢复鼠标位置
    private func clickIcon(_ icon: StatusBarIcon, restoreTo originalPosition: CGPoint) {
        let src = CGEventSource(stateID: .combinedSessionState)
        let clickPoint = CGPoint(x: icon.centerX, y: icon.centerY)

        // 移动到图标位置
        CGEvent(mouseEventSource: src, mouseType: .mouseMoved, mouseCursorPosition: clickPoint, mouseButton: .left)?.post(tap: .cghidEventTap)
        usleep(50000)

        // 点击
        let mouseDown = CGEvent(mouseEventSource: src, mouseType: .leftMouseDown, mouseCursorPosition: clickPoint, mouseButton: .left)
        mouseDown?.post(tap: .cghidEventTap)
        usleep(30000)

        let mouseUp = CGEvent(mouseEventSource: src, mouseType: .leftMouseUp, mouseCursorPosition: clickPoint, mouseButton: .left)
        mouseUp?.post(tap: .cghidEventTap)

        // 恢复鼠标位置
        usleep(50000)
        CGEvent(mouseEventSource: src, mouseType: .mouseMoved, mouseCursorPosition: originalPosition, mouseButton: .left)?.post(tap: .cghidEventTap)
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

// MARK: - Switcher Panel (Cmd+Tab style UI)
class SwitcherPanel: NSPanel {
    private var iconViews: [NSImageView] = []
    private var hiddenIndicators: [NSView] = []  // 刘海遮挡标记
    private var nameLabel: NSTextField!
    private var selectionBox: NSBox!
    private var containerView: NSView!
    private var visualEffectView: NSVisualEffectView!

    var icons: [StatusBarIcon] = []
    var selectedIndex: Int = 0 {
        didSet {
            updateSelection(animated: true)
        }
    }

    override init(contentRect: NSRect, styleMask style: NSWindow.StyleMask, backing backingStoreType: NSWindow.BackingStoreType, defer flag: Bool) {
        super.init(contentRect: contentRect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)

        self.level = .floating
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
        selectionBox.borderColor = NSColor.controlAccentColor
        selectionBox.borderWidth = 3
        selectionBox.cornerRadius = 8
        selectionBox.fillColor = NSColor.controlAccentColor.withAlphaComponent(0.2)
        containerView.addSubview(selectionBox)

        nameLabel = NSTextField(labelWithString: "")
        nameLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        nameLabel.textColor = .labelColor
        nameLabel.alignment = .center
        visualEffectView.addSubview(nameLabel)
    }

    func configure(with icons: [StatusBarIcon], lastSelectedBundleId: String? = nil) {
        self.icons = icons

        // Clear old views
        iconViews.forEach { $0.removeFromSuperview() }
        iconViews.removeAll()
        hiddenIndicators.forEach { $0.removeFromSuperview() }
        hiddenIndicators.removeAll()

        let iconSize: CGFloat = 48
        let padding: CGFloat = 16
        let spacing: CGFloat = 12

        let totalWidth = CGFloat(icons.count) * iconSize + CGFloat(icons.count - 1) * spacing + padding * 2
        let panelWidth = max(totalWidth, 200)
        let panelHeight: CGFloat = 100

        // Position panel at screen center
        if let screen = NSScreen.main {
            let x = (screen.frame.width - panelWidth) / 2
            let y = (screen.frame.height - panelHeight) / 2 + 100
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

            containerView.addSubview(iconContainer)
            iconViews.append(imageView)
        }

        // Name label at bottom
        nameLabel.frame = NSRect(x: 0, y: 8, width: panelWidth, height: 18)

        // 恢复上次选中的图标
        if let lastBundleId = lastSelectedBundleId,
           let lastIndex = icons.firstIndex(where: { $0.bundleId == lastBundleId }) {
            self.selectedIndex = lastIndex
        } else {
            self.selectedIndex = 0
        }

        updateSelection(animated: false)
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
}

// MARK: - Switcher Controller
class SwitcherController {
    static let shared = SwitcherController()

    private var panel: SwitcherPanel?
    private var icons: [StatusBarIcon] = []
    private var lastSelectedBundleId: String?  // 记住上次选中
    var isActive: Bool { panel?.isVisible ?? false }

    func show() {
        icons = StatusBarManager.shared.getIcons(excludePinned: false, excludeSelf: true)
        guard !icons.isEmpty else {
            print("⚠️  没有可切换的图标")
            return
        }

        if panel == nil {
            panel = SwitcherPanel(contentRect: .zero, styleMask: [], backing: .buffered, defer: false)
        }

        panel?.configure(with: icons, lastSelectedBundleId: lastSelectedBundleId)
        panel?.showAnimated()
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

        // 记住这次选中的图标
        lastSelectedBundleId = selectedIcon.bundleId

        panel.hideAnimated {
            // Move icon to visible area and click it
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                StatusBarManager.shared.moveToVisibleAndClick(icon: selectedIcon)
            }
        }
    }

    func cancel() {
        panel?.hideAnimated()
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
                        print("🔄 Event tap 已重新启用")
                    }
                    return Unmanaged.passUnretained(event)
                }

                let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
                let flags = event.flags
                let eventType = CGEventType(rawValue: UInt32(type.rawValue))

                // Handle Ctrl release when switcher is active
                if eventType == .flagsChanged {
                    if SwitcherController.shared.isActive && !flags.contains(.maskControl) {
                        DispatchQueue.main.async {
                            SwitcherController.shared.confirm()
                        }
                        return Unmanaged.passUnretained(event)
                    }
                    return Unmanaged.passUnretained(event)
                }

                // Ctrl + ` (keyCode 50) : Show switcher / select next
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

                // Esc : Cancel switcher
                if keyCode == 53 && SwitcherController.shared.isActive {
                    DispatchQueue.main.async {
                        SwitcherController.shared.cancel()
                    }
                    return nil
                }

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

        print("🚀 Menu Bar Rotator 已启动")
        print("   ⌃ `     图标切换器")
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
