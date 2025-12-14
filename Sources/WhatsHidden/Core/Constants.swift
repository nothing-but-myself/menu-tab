import Foundation

/// Design constants
enum Design {
    /// Notch dimensions
    enum Notch {
        static let width: CGFloat = 240
        static let safeAreaThreshold: CGFloat = 24
    }

    /// Switcher panel
    enum Switcher {
        static let iconSize: CGFloat = 48
        static let iconSpacing: CGFloat = 12
        static let padding: CGFloat = 16
        static let cornerRadius: CGFloat = 12
        static let selectionCornerRadius: CGFloat = 10
        static let selectionPadding: CGFloat = 4
        static let minWidth: CGFloat = 200
        static let height: CGFloat = 100
        static let verticalOffset: CGFloat = 120  // Above center
        static let nameLabelFontSize: CGFloat = 13
        static let nameLabelHeight: CGFloat = 18
        static let nameLabelBottomMargin: CGFloat = 8
    }

    /// Toast panel
    enum Toast {
        static let cornerRadius: CGFloat = 12
        static let iconFontSize: CGFloat = 32
        static let messageFontSize: CGFloat = 14
        static let minWidth: CGFloat = 200
        static let height: CGFloat = 80
        static let horizontalPadding: CGFloat = 30
        static let defaultDuration: TimeInterval = 1.5
    }

    /// Hidden indicator overlay
    enum HiddenIndicator {
        static let overlayAlpha: CGFloat = 0.3
        static let cornerRadius: CGFloat = 6
        static let eyeIconSize: CGFloat = 14
        static let eyeIconMargin: CGFloat = 2
    }

    /// Animations
    enum Animation {
        static let panelFadeIn: TimeInterval = 0.15
        static let panelFadeOut: TimeInterval = 0.1
        static let selectionMove: TimeInterval = 0.15
        static let toastFadeOut: TimeInterval = 0.2
    }

    /// Selection box appearance
    enum Selection {
        static let fillAlpha: CGFloat = 0.12
    }
}

/// Timing constants
enum Timing {
    static let menuDismissDelay: UInt64 = 50_000_000  // 50ms in nanoseconds
}

/// Accessibility constants
enum AX {
    static let menuBarMaxY: CGFloat = 50  // Menu bar icons should be near top
}
