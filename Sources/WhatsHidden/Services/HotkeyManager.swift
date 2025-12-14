import Cocoa

/// Global hotkey listener (Ctrl + `)
class HotkeyManager {
    static let shared = HotkeyManager()

    private var eventTap: CFMachPort?

    func start() {
        let eventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.flagsChanged.rawValue)

        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                // Re-enable tap if disabled
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    if let tap = HotkeyManager.shared.eventTap {
                        CGEvent.tapEnable(tap: tap, enable: true)
                    }
                    return Unmanaged.passUnretained(event)
                }

                let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
                let flags = event.flags
                let eventType = type

                // Handle modifier key changes
                if eventType == .flagsChanged {
                    // Preload cache when Ctrl is pressed
                    if flags.contains(.maskControl) && !SwitcherController.shared.isActive {
                        StatusBarManager.shared.preloadCache()
                    }
                    // Confirm selection when Ctrl is released (Cmd+Tab style)
                    if SwitcherController.shared.isActive && !flags.contains(.maskControl) {
                        DispatchQueue.main.async {
                            SwitcherController.shared.confirm()
                        }
                    }
                    return Unmanaged.passUnretained(event)
                }

                // Ctrl + ` : Open Switcher / Select next
                // Ctrl + Shift + ` : Select previous
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

                // Esc : Cancel
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
            print("Failed to create event tap. Check Accessibility permissions.")
            return
        }

        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
    }
}
