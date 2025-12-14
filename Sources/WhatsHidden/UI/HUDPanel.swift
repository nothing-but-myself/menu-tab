import Cocoa

/// Base class for HUD-style panels with vibrancy effect
class HUDPanel: NSPanel {
    private(set) var visualEffectView: NSVisualEffectView!

    override init(contentRect: NSRect, styleMask style: NSWindow.StyleMask, backing backingStoreType: NSWindow.BackingStoreType, defer flag: Bool) {
        super.init(contentRect: contentRect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)

        self.level = .statusBar
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = true
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.alphaValue = 0

        setupVisualEffect()
        setupContent()
    }

    private func setupVisualEffect() {
        visualEffectView = NSVisualEffectView(frame: .zero)
        visualEffectView.material = .popover
        visualEffectView.state = .active
        visualEffectView.wantsLayer = true
        visualEffectView.layer?.cornerRadius = Design.Switcher.cornerRadius
        visualEffectView.layer?.masksToBounds = true
        // Subtle border for better visibility in both light/dark modes
        visualEffectView.layer?.borderWidth = 0.5
        visualEffectView.layer?.borderColor = NSColor.separatorColor.cgColor

        contentView = visualEffectView
    }

    /// Override in subclasses to add content
    func setupContent() {
        // Subclasses override this
    }

    /// Update border color when appearance changes
    func updateAppearance() {
        visualEffectView.layer?.borderColor = NSColor.separatorColor.cgColor
    }

    // MARK: - Animations

    func showAnimated() {
        updateAppearance()
        self.alphaValue = 0
        self.orderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Design.Animation.panelFadeIn
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            self.animator().alphaValue = 1
        }
    }

    func hideAnimated(completion: (() -> Void)? = nil) {
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = Design.Animation.panelFadeOut
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            self.animator().alphaValue = 0
        }, completionHandler: {
            self.orderOut(nil)
            completion?()
        })
    }
}
