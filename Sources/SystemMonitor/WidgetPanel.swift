import AppKit
import SwiftUI
import Combine
import OSLog

/// 悬浮置顶面板：无边框、非激活、半透明毛玻璃、可拖动、跨桌面常驻
final class WidgetPanel: NSPanel {
    private let settings: WidgetSettings
    private let hosting: WidgetHostView
    private var cancellables = Set<AnyCancellable>()
    private let logger = Logger(subsystem: "com.personal.systemmonitor", category: "panel")

    init(contentRect: NSRect, stats: StatsCollector, settings: WidgetSettings) {
        self.settings = settings
        let rootView = AnyView(
            ContentView()
                .environmentObject(stats)
                .environmentObject(settings)
        )
        self.hosting = WidgetHostView(rootView: rootView)

        super.init(contentRect: contentRect,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)

        self.level = .floating
        self.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        self.backgroundColor = .clear
        self.isOpaque = false
        self.isMovableByWindowBackground = true
        self.hidesOnDeactivate = false
        self.titleVisibility = .hidden
        self.titlebarAppearsTransparent = true
        self.standardWindowButton(.closeButton)?.isHidden = true
        self.standardWindowButton(.miniaturizeButton)?.isHidden = true
        self.standardWindowButton(.zoomButton)?.isHidden = true
        self.hasShadow = false   // 透明背景，无需投影

        self.contentView = hosting
        // 初始以 scale=1 的理想尺寸贴合（强制布局确保 fittingSize 已就绪）
        hosting.layoutSubtreeIfNeeded()
        self.setContentSize(hosting.fittingSize)

        // 缩放变化时：重算尺寸并保持右上角锚点不动
        settings.$scale
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.resizeKeepingTopRight()
            }
            .store(in: &cancellables)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// 右键菜单在整个面板区域任意位置生效（含圆环间空隙），
    /// 因为由窗口层接管，不依赖 SwiftUI 子视图的命中区。
    override func rightMouseDown(with event: NSEvent) {
        showContextMenu(with: event)
    }

    /// 构造并弹出右键菜单（供窗口层与 hosting 子类共用）
    func showContextMenu(with event: NSEvent) {
        let menu = NSMenu()

        // 「组件大小」子菜单：三档，当前档打勾
        let sizeItem = menu.addItem(withTitle: "组件大小", action: nil, keyEquivalent: "")
        let sizeMenu = NSMenu()
        for (label, value) in [("小 50%", WidgetSettings.small),
                                ("中 75%", WidgetSettings.medium),
                                ("大 100%", WidgetSettings.large)] {
            let item = sizeMenu.addItem(withTitle: label,
                                        action: #selector(setScale(_:)),
                                        keyEquivalent: "")
            item.target = self
            item.representedObject = value
            item.state = (abs(settings.scale - value) < 1e-6) ? .on : .off
        }
        menu.setSubmenu(sizeMenu, for: sizeItem)

        menu.addItem(.separator())

        // 「开机自启」勾选项：双向同步 SMAppService 状态（用户拥有最终控制权）
        let loginItem = menu.addItem(withTitle: "开机自启",
                                     action: #selector(toggleLoginItem(_:)),
                                     keyEquivalent: "")
        loginItem.target = self
        let enabled = MainActor.assumeIsolated {
            (NSApp.delegate as? AppDelegate)?.isLoginItemEnabled ?? false
        }
        loginItem.state = enabled ? .on : .off

        let actItem = menu.addItem(withTitle: "打开活动监视器",
                                   action: #selector(openActivityMonitor),
                                   keyEquivalent: "")
        actItem.target = self

        let quitItem = menu.addItem(withTitle: "退出软件",
                                    action: #selector(quitApp),
                                    keyEquivalent: "")
        quitItem.target = self

        NSMenu.popUpContextMenu(menu, with: event, for: self.contentView ?? NSView())
    }

    @objc private func setScale(_ sender: NSMenuItem) {
        if let v = sender.representedObject as? Double {
            settings.scale = v
        }
    }

    @objc private func toggleLoginItem(_ sender: NSMenuItem) {
        MainActor.assumeIsolated {
            (NSApp.delegate as? AppDelegate)?.toggleLoginItem()
        }
    }

    @objc private func openActivityMonitor() {
        guard let url = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: "com.apple.ActivityMonitor"
        ) else {
            logger.warning("未找到活动监视器 App")
            let alert = NSAlert()
            alert.messageText = "未找到活动监视器"
            alert.informativeText = "系统可能缺失该工具，请在「访达 → 应用程序」中确认。"
            alert.runModal()
            return
        }
        NSWorkspace.shared.openApplication(at: url,
                                           configuration: NSWorkspace.OpenConfiguration()) { [weak self] _, error in
            if let error {
                self?.logger.error("打开活动监视器失败: \(error.localizedDescription)")
            }
        }
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    /// 按当前内容最小尺寸重设窗口，并保持右上角固定。
    /// 先强制布局，确保 fittingSize 反映最新 scale（避免读到旧尺寸导致裁剪/留白）。
    private func resizeKeepingTopRight() {
        hosting.layoutSubtreeIfNeeded()
        let newSize = hosting.fittingSize
        guard newSize.width > 0, newSize.height > 0 else { return }
        let f = frame
        let maxX = f.maxX
        let maxY = f.maxY
        setContentSize(newSize)
        setFrameOrigin(NSPoint(x: maxX - newSize.width, y: maxY - newSize.height))
    }
}

/// hosting 视图子类：兜底接管「点在圆环/数字内容上」的右键。
/// 空隙处的右键仍由 WidgetPanel.rightMouseDown 处理；两者都调用 showContextMenu。
final class WidgetHostView: NSHostingView<AnyView> {
    required init(rootView: AnyView) {
        super.init(rootView: rootView)
    }
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func rightMouseDown(with event: NSEvent) {
        if let panel = self.window as? WidgetPanel {
            panel.showContextMenu(with: event)
        } else {
            super.rightMouseDown(with: event)
        }
    }
}
