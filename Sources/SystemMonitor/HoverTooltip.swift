import AppKit
import SwiftUI

/// 悬浮提示。
///
/// SwiftUI 原生 `.help()` 在非激活浮动面板（nonactivatingPanel）里不可靠：
/// 其底层 tracking area 默认 `.activeInActiveApp`，当 app 不在前台时
/// mouseEntered 不会触发，tooltip 永远不显示。这里改用 `.activeAlways`
/// 的 NSTrackingArea 自管浮层，保证悬浮必现，且零额外 CPU（仅进出时回调）。

extension View {
    /// 在该视图范围内悬浮时弹出多行提示。
    func hoverTooltip(_ text: String) -> some View {
        background(HoverTracker(text: text))
    }
}

private struct HoverTracker: NSViewRepresentable {
    let text: String

    func makeNSView(context: Context) -> HoverTrackerView {
        HoverTrackerView()
    }

    func updateNSView(_ nsView: HoverTrackerView, context: Context) {
        nsView.currentText = text
        // 悬浮期间 stats 每秒刷新，同步更新已显示的提示文字
        if nsView.isHovering {
            TooltipWindow.shared.refresh(text)
        }
    }
}

private final class HoverTrackerView: NSView {
    var currentText: String = ""
    var isHovering = false
    private var tracking: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = tracking { removeTrackingArea(t) }
        // .inVisibleRect: 跟随视图 bounds；.activeAlways: app 非前台也能收到事件
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
        TooltipWindow.shared.show(currentText, anchor: self)
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        TooltipWindow.shared.hide()
    }
}

/// 单例浮层：承载提示文字的 borderless NSPanel，悬浮于 widget 之上。
/// 延迟 0.3s 显示，避免鼠标快速划过时闪烁；移出即隐藏。
private final class TooltipWindow {
    static let shared = TooltipWindow()

    private let panel: NSPanel
    private let label: NSTextField
    private var showTimer: Timer?

    private init() {
        let label = NSTextField(wrappingLabelWithString: "")
        label.isBezeled = false
        label.drawsBackground = false
        label.isEditable = false
        label.isSelectable = false
        label.font = .systemFont(ofSize: 12, weight: .regular)
        label.textColor = .labelColor
        label.alignment = .left
        label.lineBreakMode = .byWordWrapping
        label.preferredMaxLayoutWidth = 200

        // 毛玻璃背景：.popover 材质在深浅模式下都有良好表现，
        // 外层 1px 描边 + 圆角，配合系统 shadow 呈现立体悬浮感。
        let effect = NSVisualEffectView()
        effect.material = .popover
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 8
        effect.layer?.masksToBounds = true
        // 极细的高光描边，强化"浮起"的立体感
        effect.layer?.borderWidth = 0.5
        effect.layer?.borderColor = NSColor.white.withAlphaComponent(0.15).cgColor

        label.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(label)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: effect.topAnchor, constant: 7),
            label.bottomAnchor.constraint(equalTo: effect.bottomAnchor, constant: -7),
            label.leadingAnchor.constraint(equalTo: effect.leadingAnchor, constant: 11),
            label.trailingAnchor.constraint(equalTo: effect.trailingAnchor, constant: -11),
        ])

        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 200, height: 50),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        panel.contentView = effect

        self.panel = panel
        self.label = label
    }

    func show(_ text: String, anchor: NSView) {
        showTimer?.invalidate()
        label.stringValue = text
        layoutAndPosition(anchor: anchor)
        showTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self] _ in
            self?.panel.orderFrontRegardless()
        }
    }

    func refresh(_ text: String) {
        guard panel.isVisible else { return }
        label.stringValue = text
    }

    func hide() {
        showTimer?.invalidate()
        showTimer = nil
        panel.orderOut(nil)
    }

    /// 计算自适应尺寸，并把浮层定位到锚点下方（放不下则翻到上方），水平夹进屏幕。
    private func layoutAndPosition(anchor: NSView) {
        let container = panel.contentView!
        container.layoutSubtreeIfNeeded()
        var size = container.fittingSize
        size.width = max(size.width, 60)
        panel.setContentSize(size)

        guard let window = anchor.window,
              let screen = window.screen ?? NSScreen.main else { return }
        let rectInWindow = anchor.convert(anchor.bounds, to: nil)
        let rectInScreen = window.convertToScreen(rectInWindow)
        let visible = screen.visibleFrame

        var originX = rectInScreen.midX - size.width / 2
        var originY = rectInScreen.minY - size.height - 6
        if originY < visible.minY {
            originY = rectInScreen.maxY + 6
        }
        originX = min(max(originX, visible.minX + 4), visible.maxX - size.width - 4)
        panel.setFrameOrigin(NSPoint(x: originX, y: originY))
    }
}
