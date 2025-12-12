import Cocoa

// MARK: - Main Entry Point
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate

// 监听 SIGINT (Ctrl+C) 以便在终端调试时优雅退出
signal(SIGINT) { _ in
    print("\n👋 再见!")
    NSApplication.shared.terminate(nil)
}

app.run()
