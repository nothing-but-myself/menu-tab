import Cocoa
import ApplicationServices

// MARK: - Icon Fetcher
/// 负责获取和缓存菜单栏图标
class IconFetcher {
    static let shared = IconFetcher()
    
    private let selfBundleId = Bundle.main.bundleIdentifier ?? "WhatsHidden"
    private let selfPid = ProcessInfo.processInfo.processIdentifier
    
    // 图标缓存
    private var cachedIcons: [StatusBarIcon] = []
    private var isPreloading = false
    private let dataQueue = DispatchQueue(label: "com.whatshidden.data")
    
    private init() {
        setupNotifications()
    }
    
    // MARK: - Notifications
    
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
    
    // MARK: - Public API
    
    /// 预加载缓存（在 Ctrl 按下时调用）
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
    
    /// 同步获取隐藏图标
    func getHiddenIcons() -> [StatusBarIcon] {
        let allIcons = getIcons()
        return allIcons.filter { isIconHidden($0) }
    }
    
    /// 同步获取所有图标（使用缓存）
    func getIcons() -> [StatusBarIcon] {
        return dataQueue.sync { [self] in
            if !cachedIcons.isEmpty {
                return cachedIcons.filter { $0.bundleId != selfBundleId }
            }
            let icons = fetchAllIcons()
            cachedIcons = icons
            return cachedIcons.filter { $0.bundleId != selfBundleId }
        }
    }
    
    /// 异步获取隐藏图标（强制刷新）
    func getHiddenIconsAsync() async -> [StatusBarIcon] {
        let allIcons = await getIconsAsync()
        return allIcons.filter { isIconHidden($0) }
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
                }
                let filtered = icons.filter { $0.bundleId != self.selfBundleId }
                continuation.resume(returning: filtered)
            }
        }
    }
    
    // MARK: - Hidden Detection
    
    /// 判断图标是否在刘海区域
    func isIconHidden(_ icon: StatusBarIcon) -> Bool {
        guard let screen = findScreen(forIconX: icon.x, iconY: icon.y) else {
            return false
        }
        
        let safeArea = screen.safeAreaInsets
        if safeArea.top == 0 {
            return false
        }
        
        // 刘海区域计算
        let screenWidth = screen.frame.width
        let screenOriginX = screen.frame.origin.x
        let notchWidth: CGFloat = 240
        let notchStart = screenOriginX + (screenWidth / 2) - (notchWidth / 2)
        let notchEnd = screenOriginX + (screenWidth / 2) + (notchWidth / 2)
        
        let iconLeft = icon.x
        let iconRight = icon.x + icon.width
        
        return !(iconRight < notchStart || iconLeft > notchEnd)
    }
    
    // MARK: - Private
    
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
    
    private func findScreen(forIconX iconX: CGFloat, iconY: CGFloat) -> NSScreen? {
        for screen in NSScreen.screens {
            let frame = screen.frame
            if iconX >= frame.origin.x && iconX < frame.origin.x + frame.width {
                return screen
            }
        }
        return NSScreen.main
    }
    
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
