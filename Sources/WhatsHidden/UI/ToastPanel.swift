import Cocoa

/// Friendly toast panel with heart icon - single line layout
class ToastPanel: NSPanel {
    private var visualEffect: NSVisualEffectView!
    private var contentStack: NSStackView!
    private var iconLabel: NSTextField!
    private var messageLabel: NSTextField!

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)

        self.level = .statusBar
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = true
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        setupVisualEffect()
        setupContent()
    }

    private func setupVisualEffect() {
        visualEffect = NSVisualEffectView(frame: .zero)
        visualEffect.material = .popover
        visualEffect.state = .active
        visualEffect.wantsLayer = true
        visualEffect.layer?.cornerRadius = 16
        visualEffect.layer?.masksToBounds = true
        // Subtle border for better visibility in both light/dark modes
        visualEffect.layer?.borderWidth = 0.5
        visualEffect.layer?.borderColor = NSColor.separatorColor.cgColor
        contentView = visualEffect
    }

    private func setupContent() {
        // Heart icon
        iconLabel = NSTextField(labelWithString: "")
        iconLabel.font = NSFont.systemFont(ofSize: 18)
        iconLabel.alignment = .center
        iconLabel.setContentHuggingPriority(.required, for: .horizontal)

        // Message
        messageLabel = NSTextField(labelWithString: "")
        messageLabel.font = NSFont.systemFont(ofSize: 14, weight: .medium)
        messageLabel.textColor = .labelColor
        messageLabel.alignment = .left
        messageLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)

        // Horizontal stack: ❤️ Message
        contentStack = NSStackView(views: [iconLabel, messageLabel])
        contentStack.orientation = .horizontal
        contentStack.spacing = 8
        contentStack.alignment = .centerY
        contentStack.distribution = .fill

        visualEffect.addSubview(contentStack)
    }

    func show(message: String, on screen: NSScreen, duration: TimeInterval = 1.5) {
        iconLabel.stringValue = "❤️"
        messageLabel.stringValue = message

        // Calculate size based on content
        let messageSize = messageLabel.sizeThatFits(NSSize(width: 280, height: 30))
        let iconWidth: CGFloat = 24
        let horizontalPadding: CGFloat = 24
        let spacing: CGFloat = 8
        let panelWidth = max(iconWidth + spacing + messageSize.width + horizontalPadding * 2, 160)
        let panelHeight: CGFloat = 44

        // Center on the specified screen
        let x = screen.frame.origin.x + (screen.frame.width - panelWidth) / 2
        let y = screen.frame.origin.y + (screen.frame.height - panelHeight) / 2
        setFrame(NSRect(x: x, y: y, width: panelWidth, height: panelHeight), display: true)

        visualEffect.frame = NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight)

        // Center the stack vertically
        let contentHeight: CGFloat = 22
        let contentY = (panelHeight - contentHeight) / 2
        contentStack.frame = NSRect(x: horizontalPadding, y: contentY, width: panelWidth - horizontalPadding * 2, height: contentHeight)

        // Update border color for current appearance
        visualEffect.layer?.borderColor = NSColor.separatorColor.cgColor

        // Show animation
        self.alphaValue = 0
        self.orderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Design.Animation.panelFadeIn
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            self.animator().alphaValue = 1
        }

        // Auto hide
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = Design.Animation.toastFadeOut
                context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                self?.animator().alphaValue = 0
            }, completionHandler: {
                self?.orderOut(nil)
            })
        }
    }
}
