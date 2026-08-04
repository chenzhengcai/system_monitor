import AppKit

// 入口：直接驱动 NSApplication（agent 应用，不进 Dock），由 AppDelegate 创建悬浮面板。
// NSApplication 的 setup/run 均为 main-actor 隔离 API，故整段在 MainActor 上执行。
@MainActor
func bootstrap() {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}

MainActor.assumeIsolated { bootstrap() }
