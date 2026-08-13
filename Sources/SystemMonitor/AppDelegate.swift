import AppKit
import SwiftUI
import ServiceManagement
import OSLog

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let stats = StatsCollector()
    let settings = WidgetSettings()
    private var panel: WidgetPanel?
    private var observers: [NSObjectProtocol] = []

    private let logger = Logger(subsystem: "com.personal.systemmonitor", category: "lifecycle")
    private let askedLoginKey = "HasConfiguredLoginItem"
    private let originXKey = "WidgetOriginX"
    private let originYKey = "WidgetOriginY"

    func applicationDidFinishLaunching(_ notification: Notification) {
        ProcessInfo.processInfo.disableSuddenTermination()
        stats.start()
        configureLoginItem()   // 仅首次运行且未注册时才注册，尊重用户选择
        showPanel()
        observePower()
    }

    func applicationWillTerminate(_ notification: Notification) {
        ProcessInfo.processInfo.enableSuddenTermination()
        // 收起为标识条时保存展开态位置，重启后恢复为完整浮动面板
        if let panel { saveOrigin(panel.persistableOrigin) }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false   // 面板关闭也不退出，常驻
    }

    // MARK: - 登录项（不再流氓：首次运行注册一次，之后完全由用户通过右键菜单控制）

    /// 仅在首次启动、且当前确实未注册时自动注册；
    /// 一旦用户在任何时候关闭，后续启动都不再悄悄加回。
    private func configureLoginItem() {
        let asked = UserDefaults.standard.bool(forKey: askedLoginKey)
        guard !asked else { return }
        if SMAppService.mainApp.status == .notRegistered {
            do {
                try SMAppService.mainApp.register()
                logger.info("已注册开机自启（首次运行）")
            } catch {
                logger.error("开机自启注册失败: \(error.localizedDescription)")
            }
        }
        UserDefaults.standard.set(true, forKey: askedLoginKey)
    }

    /// 供右键菜单调用：根据当前状态切换登录项。
    func toggleLoginItem() {
        do {
            switch SMAppService.mainApp.status {
            case .enabled:
                try SMAppService.mainApp.unregister()
                logger.info("已关闭开机自启")
            case .notRegistered:
                try SMAppService.mainApp.register()
                logger.info("已开启开机自启")
            default:
                break
            }
        } catch {
            logger.error("登录项切换失败: \(error.localizedDescription)")
        }
    }

    /// 当前是否处于登录项启用状态（供菜单勾选）。
    var isLoginItemEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    // MARK: - 电源状态：休眠/唤醒时暂停/恢复采集（省电）

    private func observePower() {
        let nc = NSWorkspace.shared.notificationCenter
        // 观察者在 .main 队列回调，闭包本身不捕获 self，内部再切回 MainActor 访问隔离成员
        observers.append(nc.addObserver(forName: NSWorkspace.willSleepNotification,
                                         object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { (NSApp.delegate as? AppDelegate)?.handleWillSleep() }
        })
        observers.append(nc.addObserver(forName: NSWorkspace.didWakeNotification,
                                         object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { (NSApp.delegate as? AppDelegate)?.handleDidWake() }
        })
    }

    private func handleWillSleep() {
        stats.stop()
        logger.info("系统即将休眠，暂停采集")
    }

    private func handleDidWake() {
        stats.start()
        logger.info("系统唤醒，恢复采集")
    }

    // MARK: - 面板

    private func showPanel() {
        let rect = NSRect(x: 0, y: 0, width: 224, height: 110)
        let panel = WidgetPanel(contentRect: rect, stats: stats, settings: settings)

        let defaultOrigin = defaultTopRightOrigin(for: panel)
        let origin = if let saved = loadSavedOrigin(), originIsOnScreen(saved, size: panel.frame.size) {
            saved
        } else {
            defaultOrigin
        }
        panel.setFrameOrigin(origin)
        panel.orderFrontRegardless()
        self.panel = panel
        saveOrigin(panel.frame.origin)
        // 位置在启动时恢复、退出时保存（applicationWillTerminate），足以跨重启保留；
        // 不在拖动时实时保存，以避免在并发闭包中跨边界访问主线程隔离的窗口属性。
    }

    private func defaultTopRightOrigin(for panel: NSPanel) -> NSPoint {
        guard let screen = NSScreen.main else { return .zero }
        let vf = screen.visibleFrame
        let f = panel.frame
        return NSPoint(x: vf.maxX - f.width - 20, y: vf.maxY - f.height - 20)
    }

    private func loadSavedOrigin() -> NSPoint? {
        let x = UserDefaults.standard.double(forKey: originXKey)
        let y = UserDefaults.standard.double(forKey: originYKey)
        guard x != 0 || y != 0 else { return nil }
        return NSPoint(x: x, y: y)
    }

    private func saveOrigin(_ point: NSPoint) {
        UserDefaults.standard.set(Double(point.x), forKey: originXKey)
        UserDefaults.standard.set(Double(point.y), forKey: originYKey)
    }

    /// 候选原点 + 面板尺寸构成的矩形，是否与任一屏幕可见区域相交。
    private func originIsOnScreen(_ origin: NSPoint, size: NSSize) -> Bool {
        let rect = NSRect(origin: origin, size: size)
        return NSScreen.screens.contains { $0.visibleFrame.intersects(rect) }
    }
}
