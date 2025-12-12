import Cocoa

// MARK: - Switcher Panel
/// Cmd+Tab 风格的浮窗 UI
class SwitcherPanel: NSPanel {
    private var iconViews: [NSImageView] = []
    private var iconContainers: [NSView] = []
    private var hiddenIndicators: [NSView] = []
    private var nameLabel: NSTextField!
    private var selectionBox: NSBox!
    private var containerView: NSView!
    private var visualEffectView: NSVisualEffectView!
    
    var icons: [StatusBarIcon] = []
    private var isConfiguring = false
    var selectedIndex: Int = 0 {
        didSet {
            if !isConfiguring {
                updateSelection(animated: true)
            }
        }
    }
    
    // 选中回调
    var onConfirm: ((StatusBarIcon) -> Void)?
    
    override init(contentRect: NSRect, styleMask style: NSWindow.StyleMask, backing backingStoreType: NSWindow.BackingStoreType, defer flag: Bool) {
        super.init(contentRect: contentRect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        
        self.level = .statusBar
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = true
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.alphaValue = 0
        
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
        selectionBox.borderWidth = 0
        selectionBox.cornerRadius = 10
        selectionBox.fillColor = NSColor.labelColor.withAlphaComponent(0.12)
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
        
        // Clear old views
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
        
        // 面板跟随鼠标位置
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
            
            if let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == icon.bundleId }) {
                imageView.image = app.icon
            } else {
                imageView.image = NSImage(systemSymbolName: "app.fill", accessibilityDescription: nil)
            }
            imageView.imageScaling = .scaleProportionallyUpOrDown
            
            iconContainer.addSubview(imageView)
            
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
        
        nameLabel.frame = NSRect(x: 0, y: 8, width: panelWidth, height: 18)
        
        isConfiguring = true
        selectedIndex = 0
        isConfiguring = false
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
        
        let icon = icons[selectedIndex]
        nameLabel.stringValue = icon.name
    }
    
    func selectNext() {
        selectedIndex = (selectedIndex + 1) % icons.count
    }
    
    func selectPrev() {
        selectedIndex = (selectedIndex - 1 + icons.count) % icons.count
    }
    
    func showAnimated() {
        self.alphaValue = 0
        self.orderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            self.animator().alphaValue = 1
        }
    }
    
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
    
    // MARK: - Mouse Interaction
    
    override func mouseEntered(with event: NSEvent) {
        if let userInfo = event.trackingArea?.userInfo,
           let index = userInfo["index"] as? Int {
            selectedIndex = index
        }
    }
    
    override func mouseUp(with event: NSEvent) {
        guard selectedIndex >= 0 && selectedIndex < icons.count else { return }
        onConfirm?(icons[selectedIndex])
    }
}

// MARK: - Empty State Panel
/// 空状态提示面板
class EmptyStatePanel: NSPanel {
    private var heartLabel: NSTextField!
    private var messageLabel: NSTextField!
    
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        
        self.level = .statusBar
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = true
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        
        setupUI()
    }
    
    private func setupUI() {
        let visualEffect = NSVisualEffectView(frame: .zero)
        visualEffect.material = .hudWindow
        visualEffect.state = .active
        visualEffect.wantsLayer = true
        visualEffect.layer?.cornerRadius = 12
        visualEffect.layer?.masksToBounds = true
        contentView = visualEffect
        
        heartLabel = NSTextField(labelWithString: "❤️")
        heartLabel.font = NSFont.systemFont(ofSize: 32)
        heartLabel.alignment = .center
        visualEffect.addSubview(heartLabel)
        
        messageLabel = NSTextField(labelWithString: "")
        messageLabel.font = NSFont.systemFont(ofSize: 14, weight: .medium)
        messageLabel.textColor = .secondaryLabelColor
        messageLabel.alignment = .center
        visualEffect.addSubview(messageLabel)
    }
    
    func show(message: String, duration: TimeInterval = 2.0) {
        messageLabel.stringValue = message
        
        let panelWidth: CGFloat = 280
        let panelHeight: CGFloat = 100
        
        let mouseLoc = NSEvent.mouseLocation
        let targetScreen = NSScreen.screens.first(where: { NSMouseInRect(mouseLoc, $0.frame, false) }) ?? NSScreen.main
        if let screen = targetScreen {
            let x = screen.frame.origin.x + (screen.frame.width - panelWidth) / 2
            let y = screen.frame.origin.y + (screen.frame.height - panelHeight) / 2 + 50
            setFrame(NSRect(x: x, y: y, width: panelWidth, height: panelHeight), display: true)
        }
        
        contentView?.frame = NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight)
        heartLabel.frame = NSRect(x: 0, y: 45, width: panelWidth, height: 40)
        messageLabel.frame = NSRect(x: 20, y: 15, width: panelWidth - 40, height: 25)
        
        self.alphaValue = 0
        self.orderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            self.animator().alphaValue = 1
        }
        
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
