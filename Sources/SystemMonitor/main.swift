import AppKit

// 入口：直接驱动 NSApplication（agent 应用，不进 Dock），由 AppDelegate 创建悬浮面板。
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
