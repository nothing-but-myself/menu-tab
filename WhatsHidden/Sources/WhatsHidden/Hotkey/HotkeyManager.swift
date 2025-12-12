import Cocoa

// MARK: - Hotkey Manager
/// 全局快捷键监听
class HotkeyManager {
    static let shared = HotkeyManager()
    
    private var eventTap: CFMachPort?
    
    // 回调
    var onActivate: (() -> Void)?      // Ctrl+` 首次激活
    var onNext: (() -> Void)?          // Ctrl+` 下一个
    var onPrev: (() -> Void)?          // Ctrl+Shift+` 上一个
    var onConfirm: (() -> Void)?       // 松开 Ctrl 确认
    var onCancel: (() -> Void)?        // Esc 取消
    var onPreload: (() -> Void)?       // Ctrl 按下预加载
    
    // 状态
    var isActive: Bool = false
    
    private init() {}
    
    func start() {
        let eventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.flagsChanged.rawValue)
        
        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                return HotkeyManager.shared.handleEvent(proxy: proxy, type: type, event: event)
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
    
    private func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // 检测 tap 被禁用，重新启用
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }
        
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags
        
        // 处理修饰键变化
        if type == .flagsChanged {
            // Ctrl 按下时预加载
            if flags.contains(.maskControl) && !isActive {
                DispatchQueue.main.async { self.onPreload?() }
            }
            // 松开 Ctrl 时确认
            if isActive && !flags.contains(.maskControl) {
                DispatchQueue.main.async { self.onConfirm?() }
            }
            return Unmanaged.passUnretained(event)
        }
        
        // Ctrl + ` : 激活 / 下一个
        // Ctrl + Shift + ` : 上一个
        if keyCode == 50 && flags.contains(.maskControl) && !flags.contains(.maskCommand) {
            DispatchQueue.main.async {
                if self.isActive {
                    if flags.contains(.maskShift) {
                        self.onPrev?()
                    } else {
                        self.onNext?()
                    }
                } else {
                    self.onActivate?()
                }
            }
            return nil
        }
        
        // Esc : 取消
        if keyCode == 53 && isActive {
            DispatchQueue.main.async { self.onCancel?() }
            return nil
        }
        
        return Unmanaged.passUnretained(event)
    }
}
