import Cocoa

// MARK: - Switcher Controller
/// 切换器控制器 - 协调 UI 和逻辑
class SwitcherController {
    static let shared = SwitcherController()
    
    private var panel: SwitcherPanel?
    private var emptyPanel: EmptyStatePanel?
    private var icons: [StatusBarIcon] = []
    
    var isActive: Bool { panel?.isVisible ?? false }
    
    private init() {}
    
    /// 显示切换器
    func show() {
        let hiddenIcons = IconFetcher.shared.getHiddenIcons()
        icons = hiddenIcons
        
        if panel == nil {
            panel = SwitcherPanel(contentRect: .zero, styleMask: [], backing: .buffered, defer: false)
            panel?.onConfirm = { [weak self] icon in
                self?.confirmSelection(icon)
            }
        }
        
        if icons.isEmpty {
            // 异步刷新
            Task {
                let freshIcons = await IconFetcher.shared.getHiddenIconsAsync()
                await MainActor.run {
                    self.icons = freshIcons
                    if self.icons.isEmpty {
                        self.showEmptyState()
                        return
                    }
                    self.panel?.configure(with: self.icons)
                    self.panel?.showAnimated()
                    HotkeyManager.shared.isActive = true
                    
                    // 立即激活第一个
                    self.activateCurrentIcon()
                }
            }
        } else {
            panel?.configure(with: icons)
            panel?.showAnimated()
            HotkeyManager.shared.isActive = true
            
            // 立即激活第一个
            activateCurrentIcon()
            
            // 后台刷新
            Task {
                let freshIcons = await IconFetcher.shared.getHiddenIconsAsync()
                await MainActor.run {
                    let newIds = freshIcons.map { $0.id }
                    let oldIds = self.icons.map { $0.id }
                    if newIds != oldIds {
                        self.icons = freshIcons
                        self.panel?.configure(with: self.icons)
                    }
                }
            }
        }
    }
    
    /// 选择下一个并激活
    func selectNextAndActivate() {
        panel?.selectNext()
        activateCurrentIcon()
    }
    
    /// 选择上一个并激活
    func selectPrevAndActivate() {
        panel?.selectPrev()
        activateCurrentIcon()
    }
    
    /// 确认选择（松开 Ctrl）
    func confirm() {
        guard let panel = panel, panel.isVisible else { return }
        panel.hideAnimated()
        HotkeyManager.shared.isActive = false
    }
    
    /// 取消
    func cancel() {
        panel?.hideAnimated()
        HotkeyManager.shared.isActive = false
        
        // 关闭当前打开的菜单
        Task {
            await IconActivator.shared.dismissCurrentMenu()
        }
    }
    
    // MARK: - Private
    
    private func activateCurrentIcon() {
        guard let panel = panel,
              panel.selectedIndex >= 0 && panel.selectedIndex < icons.count else { return }
        
        let selectedIcon = icons[panel.selectedIndex]
        
        Task {
            await IconActivator.shared.dismissCurrentMenu()
            IconActivator.shared.activateIcon(selectedIcon)
        }
    }
    
    private func confirmSelection(_ icon: StatusBarIcon) {
        panel?.hideAnimated()
        HotkeyManager.shared.isActive = false
        
        Task {
            await IconActivator.shared.dismissCurrentMenu()
            IconActivator.shared.activateIcon(icon)
        }
    }
    
    private func showEmptyState() {
        if emptyPanel == nil {
            emptyPanel = EmptyStatePanel()
        }
        emptyPanel?.show(message: "All your icons are visible!")
    }
}

// MARK: - App Delegate
class AppDelegate: NSObject, NSApplicationDelegate {
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        print("🔍 What's Hidden?")
        print("   发现并访问被刘海遮挡的菜单栏图标")
        print("")
        
        // 系统检查
        if !SystemInfo.isMontereyOrLater {
            print("⚠️  建议使用 macOS 12 (Monterey) 或更新版本")
        }
        
        if !SystemInfo.hasNotch {
            print("ℹ️  当前显示器没有刘海")
        }
        
        // 权限检查
        if !checkPermissions() {
            print("⚠️  需要辅助功能权限才能正常工作")
        }
        
        // 初始化
        _ = IconFetcher.shared
        setupHotkeys()
        
        print("")
        print("🚀 已启动")
        print("   ⌃ `     显示隐藏图标 / 切换下一个")
        print("   ⌃ ⇧ `   切换上一个")
        print("   松开 ⌃  确认")
        print("   Esc     取消")
    }
    
    private func setupHotkeys() {
        let hotkey = HotkeyManager.shared
        
        hotkey.onPreload = {
            IconFetcher.shared.preloadCache()
        }
        
        hotkey.onActivate = {
            SwitcherController.shared.show()
        }
        
        hotkey.onNext = {
            SwitcherController.shared.selectNextAndActivate()
        }
        
        hotkey.onPrev = {
            SwitcherController.shared.selectPrevAndActivate()
        }
        
        hotkey.onConfirm = {
            SwitcherController.shared.confirm()
        }
        
        hotkey.onCancel = {
            SwitcherController.shared.cancel()
        }
        
        hotkey.start()
    }
    
    @discardableResult
    func checkPermissions() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        return AXIsProcessTrustedWithOptions(options as CFDictionary)
    }
}
