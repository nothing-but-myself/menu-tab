import Cocoa

/// Friendly toast panel with heart icon
class ToastPanel: NSPanel {
    private var iconLabel: NSTextField!
    private var messageLabel: NSTextField!

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
        visualEffect.layer?.cornerRadius = 12
        visualEffect.layer?.masksToBounds = true
        contentView = visualEffect

        // Heart icon
        iconLabel = NSTextField(labelWithString: "")
        iconLabel.font = NSFont.systemFont(ofSize: 32)
        iconLabel.alignment = .center
        visualEffect.addSubview(iconLabel)

        // Message
        messageLabel = NSTextField(labelWithString: "")
        messageLabel.font = NSFont.systemFont(ofSize: 14, weight: .medium)
        messageLabel.textColor = .labelColor
        messageLabel.alignment = .center
        visualEffect.addSubview(messageLabel)
    }

    func show(message: String, on screen: NSScreen, duration: TimeInterval = 1.5) {
        iconLabel.stringValue = "❤️"
        messageLabel.stringValue = message

        // Calculate size
        let messageSize = messageLabel.sizeThatFits(NSSize(width: 300, height: 50))
        let panelWidth = max(messageSize.width + 60, 200)
        let panelHeight: CGFloat = 80

        // Center on the specified screen
        let x = screen.frame.origin.x + (screen.frame.width - panelWidth) / 2
        let y = screen.frame.origin.y + (screen.frame.height - panelHeight) / 2
        setFrame(NSRect(x: x, y: y, width: panelWidth, height: panelHeight), display: true)

        contentView?.frame = NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight)
        iconLabel.frame = NSRect(x: 0, y: 38, width: panelWidth, height: 36)
        messageLabel.frame = NSRect(x: 20, y: 12, width: panelWidth - 40, height: 22)

        // Show animation
        self.alphaValue = 0
        self.orderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            self.animator().alphaValue = 1
        }

        // Auto hide
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
