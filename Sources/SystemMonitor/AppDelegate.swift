import AppKit
import SwiftUI
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {
    let stats = StatsCollector()
    let settings = WidgetSettings()
    private var panel: NSPanel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        ProcessInfo.processInfo.disableSuddenTermination()
        stats.start()
        registerLoginItem()
        showPanel()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false   // 面板关闭也不退出，常驻
    }

    /// 开机自启：SMAppService 要求最终以 .app bundle 运行（swift run 下注册会失败，仅打印）
    private func registerLoginItem() {
        do {
            try SMAppService.mainApp.register()
        } catch {
            print("[SystemMonitor] 开机自启注册失败（直接 swift run 时正常，打包为 .app 后即可用）: \(error.localizedDescription)")
        }
    }

    private func showPanel() {
        let rect = NSRect(x: 0, y: 0, width: 224, height: 110)
        let panel = WidgetPanel(contentRect: rect, stats: stats, settings: settings)

        // 默认放屏幕右上角
        if let screen = NSScreen.main {
            let vf = screen.visibleFrame
            let f = panel.frame
            panel.setFrameOrigin(NSPoint(x: vf.maxX - f.width - 20,
                                         y: vf.maxY - f.height - 20))
        } else {
            panel.center()
        }
        panel.orderFrontRegardless()
        self.panel = panel
    }
}