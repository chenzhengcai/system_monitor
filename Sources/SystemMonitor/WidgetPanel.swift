import AppKit
import SwiftUI
import Combine
import OSLog

/// 悬浮置顶面板：无边框、非激活、半透明毛玻璃、可拖动、跨桌面常驻
final class WidgetPanel: NSPanel {
    private let settings: WidgetSettings
    private let hosting: WidgetHostView
    private let glass: NSVisualEffectView
    private let shadowContainer: NSView
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

        // 阴影容器：负责外阴影，不裁剪
        self.shadowContainer = MovableShadowView()
        shadowContainer.wantsLayer = true
        shadowContainer.layer?.backgroundColor = NSColor.clear.cgColor
        shadowContainer.layer?.cornerCurve = .continuous
        shadowContainer.layer?.masksToBounds = false
        shadowContainer.layer?.shadowColor = NSColor.black.withAlphaComponent(0.28).cgColor
        shadowContainer.layer?.shadowOpacity = 1.0
        shadowContainer.layer?.shadowRadius = 22
        shadowContainer.layer?.shadowOffset = CGSize(width: 0, height: 10)

        // 毛玻璃层：圆角裁切 + 透明度
        self.glass = MovableVisualEffectView()
        glass.material = .sheet
        glass.blendingMode = .behindWindow
        glass.state = .active
        glass.wantsLayer = true
        glass.layer?.cornerCurve = .continuous
        glass.layer?.masksToBounds = true
        glass.layer?.borderWidth = 1.0
        glass.layer?.borderColor = NSColor.white.withAlphaComponent(0.22).cgColor

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
        self.hasShadow = false

        self.contentView = shadowContainer

        glass.translatesAutoresizingMaskIntoConstraints = false
        hosting.translatesAutoresizingMaskIntoConstraints = false
        shadowContainer.addSubview(glass)
        shadowContainer.addSubview(hosting)

        NSLayoutConstraint.activate([
            glass.leadingAnchor.constraint(equalTo: shadowContainer.leadingAnchor),
            glass.trailingAnchor.constraint(equalTo: shadowContainer.trailingAnchor),
            glass.topAnchor.constraint(equalTo: shadowContainer.topAnchor),
            glass.bottomAnchor.constraint(equalTo: shadowContainer.bottomAnchor),

            hosting.leadingAnchor.constraint(equalTo: shadowContainer.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: shadowContainer.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: shadowContainer.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: shadowContainer.bottomAnchor),
        ])

        // 初始应用圆角 + 透明度
        applyGlassRadius()
        applyGlassOpacity()
        shadowContainer.layoutSubtreeIfNeeded()
        glass.layoutSubtreeIfNeeded()
        hosting.layoutSubtreeIfNeeded()
        self.setContentSize(hosting.fittingSize)

        // 缩放联动
        settings.$scale
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.resizeKeepingTopRight()
                self?.applyGlassRadius()
            }
            .store(in: &cancellables)

        // 透明度联动
        settings.$opacity
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.applyGlassOpacity()
            }
            .store(in: &cancellables)
    }

    private func applyGlassRadius() {
        let radius = 48 * CGFloat(settings.scale)
        glass.layer?.cornerRadius = radius
        shadowContainer.layer?.cornerRadius = radius
        shadowContainer.layer?.shadowPath = CGPath(
            roundedRect: shadowContainer.bounds,
            cornerWidth: radius,
            cornerHeight: radius,
            transform: nil
        )
    }

    private func applyGlassOpacity() {
        glass.alphaValue = CGFloat(settings.opacity)
    }

    override func layoutIfNeeded() {
        super.layoutIfNeeded()
        let radius = 48 * CGFloat(settings.scale)
        shadowContainer.layer?.shadowPath = CGPath(
            roundedRect: shadowContainer.bounds,
            cornerWidth: radius,
            cornerHeight: radius,
            transform: nil
        )
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func rightMouseDown(with event: NSEvent) {
        showContextMenu(with: event)
    }

    func showContextMenu(with event: NSEvent) {
        let menu = NSMenu()

        // 组件大小子菜单
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

        // 背景透明度子菜单
        let opacityItem = menu.addItem(withTitle: "背景透明度", action: nil, keyEquivalent: "")
        let opacityMenu = NSMenu()
        for (label, value) in [("25%", WidgetSettings.opacity25),
                                ("50%", WidgetSettings.opacity50),
                                ("75%", WidgetSettings.opacity75),
                                ("100%", WidgetSettings.opacity100)] {
            let item = opacityMenu.addItem(withTitle: label,
                                           action: #selector(setOpacity(_:)),
                                           keyEquivalent: "")
            item.target = self
            item.representedObject = value
            item.state = (abs(settings.opacity - value) < 1e-6) ? .on : .off
        }
        menu.setSubmenu(opacityMenu, for: opacityItem)

        menu.addItem(.separator())

        // 开机自启
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

    @objc private func setOpacity(_ sender: NSMenuItem) {
        if let v = sender.representedObject as? Double {
            settings.opacity = v
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

    private func resizeKeepingTopRight() {
        hosting.layoutSubtreeIfNeeded()
        let newSize = hosting.fittingSize
        guard newSize.width > 0, newSize.height > 0 else { return }
        let f = frame
        let maxX = f.maxX
        let maxY = f.maxY
        setContentSize(newSize)
        setFrameOrigin(NSPoint(x: maxX - newSize.width, y: maxY - newSize.height))
        let radius = 48 * CGFloat(settings.scale)
        shadowContainer.layer?.shadowPath = CGPath(
            roundedRect: shadowContainer.bounds,
            cornerWidth: radius,
            cornerHeight: radius,
            transform: nil
        )
    }
}

final class WidgetHostView: NSHostingView<AnyView> {
    required init(rootView: AnyView) {
        super.init(rootView: rootView)
    }
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented)")
    }

    override var mouseDownCanMoveWindow: Bool { true }

    override func rightMouseDown(with event: NSEvent) {
        if let panel = self.window as? WidgetPanel {
            panel.showContextMenu(with: event)
        } else {
            super.rightMouseDown(with: event)
        }
    }
}

private final class MovableShadowView: NSView {
    override var mouseDownCanMoveWindow: Bool { true }
}

private final class MovableVisualEffectView: NSVisualEffectView {
    override var mouseDownCanMoveWindow: Bool { true }
}
