import Cocoa

/// Switcher business logic controller
class SwitcherController {
    static let shared = SwitcherController()

    private var panel: SwitcherPanel?
    private var toastPanel: ToastPanel?
    private var icons: [StatusBarIcon] = []
    var isActive: Bool { panel?.isVisible ?? false }

    /// Get current screen (where mouse is located)
    private func getCurrentScreen() -> NSScreen {
        let mouseLoc = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { NSMouseInRect(mouseLoc, $0.frame, false) }) ?? NSScreen.main!
    }

    /// Check if a screen has notch
    private func screenHasNotch(_ screen: NSScreen) -> Bool {
        return SystemInfo.hasNotch(screen: screen)
    }

    /// Show toast message on specified screen
    private func showToast(_ message: String, on screen: NSScreen) {
        if toastPanel == nil {
            toastPanel = ToastPanel()
        }
        toastPanel?.show(message: message, on: screen)
    }

    /// Main entry point - handles all the logic
    func show() {
        let currentScreen = getCurrentScreen()

        // Check if current screen has notch
        if !screenHasNotch(currentScreen) {
            showToast("No notch on this display", on: currentScreen)
            return
        }

        // Screen has notch, check for hidden icons
        let hiddenIcons = StatusBarManager.shared.getHiddenIcons()

        if hiddenIcons.isEmpty {
            // Try async refresh
            Task {
                let freshHiddenIcons = await StatusBarManager.shared.getHiddenIconsAsync()
                await MainActor.run {
                    if freshHiddenIcons.isEmpty {
                        self.showToast("All clear! No hidden icons", on: currentScreen)
                    } else {
                        self.showSwitcher(with: freshHiddenIcons, on: currentScreen)
                    }
                }
            }
        } else {
            // Show switcher immediately with cached data
            showSwitcher(with: hiddenIcons, on: currentScreen)

            // Refresh in background
            Task {
                let freshIcons = await StatusBarManager.shared.getHiddenIconsAsync()
                await MainActor.run {
                    let newIds = freshIcons.map { $0.id }
                    let oldIds = self.icons.map { $0.id }
                    if newIds != oldIds && !freshIcons.isEmpty {
                        self.icons = freshIcons
                        self.panel?.configure(with: self.icons, on: currentScreen)
                    }
                }
            }
        }
    }

    private func showSwitcher(with icons: [StatusBarIcon], on screen: NSScreen) {
        self.icons = icons

        if panel == nil {
            panel = SwitcherPanel(contentRect: .zero, styleMask: [], backing: .buffered, defer: false)
        }

        panel?.configure(with: icons, on: screen)
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

        // Hide panel immediately
        panel.hideAnimated()

        // Dismiss old menu, then activate new icon
        Task {
            await StatusBarManager.shared.dismissCurrentMenu()
            StatusBarManager.shared.activateIcon(icon: selectedIcon)
        }
    }

    func cancel() {
        panel?.hideAnimated()
    }
}
