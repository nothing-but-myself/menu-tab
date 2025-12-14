# What's Hidden

A simple switcher for menu bar icons hidden behind the MacBook notch.

## Usage

| Shortcut | Action |
|----------|--------|
| `Ctrl + `` | Open switcher / Next icon |
| `Ctrl + Shift + `` | Previous icon |
| Release `Ctrl` | Confirm selection |
| `Esc` | Cancel |

## How It Works

1. Press `Ctrl + `` on any screen
2. If the current screen has a notch and there are hidden icons, the switcher appears
3. If not, you'll see a friendly message
4. Release `Ctrl` to activate the selected icon's menu

The app only shows icons that are actually hidden behind the notch. No configuration needed.

## Build from Source

```bash
git clone https://github.com/user/whats-hidden.git
cd whats-hidden
swift build -c release
open .build/release/WhatsHidden
```

## Requirements

- macOS 12.0 (Monterey) or later
- Accessibility permission
- MacBook with notch (for full functionality)

## License

MIT with Commercial Restriction. See [LICENSE](LICENSE).

Free for personal use. Commercial use requires permission.
