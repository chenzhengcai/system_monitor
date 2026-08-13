import AppKit
import SwiftUI
import Combine
import OSLog

/// 吸附边
enum SnapEdge: Equatable {
    case left, right, top, bottom
}

/// 面板吸附状态
private enum SnapState: Equatable {
    case floating               // 自由浮动
    case collapsed(SnapEdge)    // 已吸附收起（只剩标识条）
    case peeking(SnapEdge)      // 悬停临时展开
}

/// 悬浮置顶面板：无边框、非激活、半透明毛玻璃、可拖动、跨桌面常驻。
/// 支持拖动到屏幕任意边缘自动吸附收起为橙色标识条，悬停标识条自动展开。
final class WidgetPanel: NSPanel {
    private let settings: WidgetSettings
    private let hosting: WidgetHostView
    private let glass: NSVisualEffectView
    private let shadowContainer: TrackingContainerView
    private let indicator: IndicatorView   // 橙色吸附标识条（位图胶囊）
    private var cancellables = Set<AnyCancellable>()
    private let logger = Logger(subsystem: "com.personal.systemmonitor", category: "panel")

    // MARK: - 吸附相关状态

    private var snapState: SnapState = .floating
    private var expandedFrame: NSRect = .zero   // 完整展开时的 frame（吸附前的位置）
    private var isDragging = false
    private var dragOffset: NSPoint = .zero
    private var recollapseWork: DispatchWorkItem?
    /// 鼠标按下时的屏幕坐标（用于区分「点击」与「拖动」）
    private var mouseDownLocation: NSPoint = .zero
    /// 本次按下后是否真正移动过（超过阈值）—— 点击不触发吸附/收回
    private var didMoveDuringDrag = false
    /// 收起动画期间的悬停屏蔽期：动画 resize 会重建 tracking area，AppKit 对
    /// 「光标恰在区域内」补发假 mouseEntered，不屏蔽会导致刚收起就弹跳展开。
    private var suppressHoverUntil: Date = .distantPast

    /// 内容视图（玻璃 + hosting）撑满容器的约束：浮动/展开态生效
    private var contentConstraints: [NSLayoutConstraint] = []
    /// 收起态下内容视图「固定尺寸居中」的停泊约束：
    /// 细条窗口只有十几 pt 宽，hosting 固有尺寸约 310pt，若仍四边撑满会约束冲突，
    /// Auto Layout 随机打破约束时可能把标识条压没（右侧吸附看不到橙条就是这个原因）。
    private var parkedConstraints: [NSLayoutConstraint] = []

    /// 吸附触发阈值（拖动结束后面板边距屏幕边 ≤ 该值即吸附）
    private static let snapThreshold: CGFloat = 40
    /// 标识条视觉厚度（全圆角胶囊）
    private static let stripThickness: CGFloat = 8
    /// 标识条两端预留的命中/光晕 padding
    private static let stripPadding: CGFloat = 5

    /// 标识条当前生效的约束（随吸附边方向重建）
    private var indicatorConstraints: [NSLayoutConstraint] = []

    /// 供 AppDelegate 在退出时持久化：收起状态下保存展开时的位置，重启后恢复为浮动面板
    var persistableOrigin: NSPoint {
        switch snapState {
        case .floating: return frame.origin
        case .collapsed, .peeking: return expandedFrame.origin
        }
    }

    init(contentRect: NSRect, stats: StatsCollector, settings: WidgetSettings) {
        self.settings = settings
        let rootView = AnyView(
            ContentView()
                .environmentObject(stats)
                .environmentObject(settings)
        )
        self.hosting = WidgetHostView(rootView: rootView)

        // 阴影容器：负责外阴影 + 悬停跟踪 + 收起态拖动，不裁剪
        self.shadowContainer = TrackingContainerView()
        shadowContainer.wantsLayer = true
        shadowContainer.layer?.backgroundColor = NSColor.clear.cgColor
        shadowContainer.layer?.cornerCurve = .continuous
        shadowContainer.layer?.masksToBounds = false
        shadowContainer.layer?.shadowColor = NSColor.black.withAlphaComponent(0.28).cgColor
        shadowContainer.layer?.shadowOpacity = 1.0
        shadowContainer.layer?.shadowRadius = 22
        shadowContainer.layer?.shadowOffset = CGSize(width: 0, height: 10)

        // 毛玻璃层：圆角裁切 + 透明度
        self.glass = DragForwardingVisualEffectView()
        glass.material = .sheet
        glass.blendingMode = .behindWindow
        glass.state = .active
        glass.wantsLayer = true
        glass.layer?.cornerCurve = .continuous
        glass.layer?.masksToBounds = true
        glass.layer?.borderWidth = 1.0
        glass.layer?.borderColor = NSColor.white.withAlphaComponent(0.22).cgColor

        // 橙色标识条（吸附收起后唯一可见内容）
        self.indicator = IndicatorView()

        super.init(contentRect: contentRect,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)

        self.level = .floating
        self.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        self.backgroundColor = .clear
        self.isOpaque = false
        self.isMovableByWindowBackground = false   // 拖动由子视图手动接管（需要拖动结束回调做吸附）
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
        indicator.translatesAutoresizingMaskIntoConstraints = false
        shadowContainer.addSubview(glass)
        shadowContainer.addSubview(hosting)
        shadowContainer.addSubview(indicator)

        // 内容撑满约束（浮动/展开态生效；收起态会停用并换停泊约束）
        contentConstraints = [
            glass.leadingAnchor.constraint(equalTo: shadowContainer.leadingAnchor),
            glass.trailingAnchor.constraint(equalTo: shadowContainer.trailingAnchor),
            glass.topAnchor.constraint(equalTo: shadowContainer.topAnchor),
            glass.bottomAnchor.constraint(equalTo: shadowContainer.bottomAnchor),
            hosting.leadingAnchor.constraint(equalTo: shadowContainer.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: shadowContainer.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: shadowContainer.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: shadowContainer.bottomAnchor),
        ]
        NSLayoutConstraint.activate(contentConstraints)

        // 标识条初始仅占位（隐藏）。占位约束必须放进 indicatorConstraints，
        // 否则 pinIndicator 停用时漏掉它们，新旧约束冲突会把标识条压成 0×0。
        indicatorConstraints = [
            indicator.centerXAnchor.constraint(equalTo: shadowContainer.centerXAnchor),
            indicator.centerYAnchor.constraint(equalTo: shadowContainer.centerYAnchor),
            indicator.widthAnchor.constraint(equalToConstant: 0),
            indicator.heightAnchor.constraint(equalToConstant: 0),
        ]
        NSLayoutConstraint.activate(indicatorConstraints)

        indicator.isHidden = true
        indicator.alphaValue = 0

        // 初始应用圆角 + 透明度
        applyGlassRadius()
        applyGlassOpacity()
        shadowContainer.layoutSubtreeIfNeeded()
        glass.layoutSubtreeIfNeeded()
        hosting.layoutSubtreeIfNeeded()
        self.setContentSize(hosting.fittingSize)

        // 悬停回调：收起态 → 展开；展开态 → 取消收回计划 / 安排收回
        shadowContainer.onMouseEntered = { [weak self] in self?.handleMouseEntered() }
        shadowContainer.onMouseExited = { [weak self] in self?.handleMouseExited() }

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

    // MARK: - 标识条视图

    /// 标识条：NSImageView 显示离线渲染的胶囊位图。
    /// 为什么不用 draw(_:)/CALayer 拼装：父容器 layer-backed 会强制子视图走
    /// 「位图拉伸而非重绘」的管线，任何重尺寸时序问题都会把圆角拉成尖角；
    /// 离线渲染成与视图等大的 NSImage 后，显示内容完全确定，不受 AppKit 重绘策略影响。
    /// scaleNone + 居中：即使 frame 异常也只居中显示，绝不拉伸变形。
    private final class IndicatorView: NSImageView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }   // 事件穿透到容器
        init() {
            super.init(frame: .zero)
            imageScaling = .scaleNone
            imageAlignment = .alignCenter
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    }

    /// 发光留白（位图比可视胶囊大一圈，容纳外发光）
    private static let glowPad: CGFloat = 4

    /// 离线渲染橙色胶囊（两端标准半圆 + 外发光 + 渐变 + 顶部高光）。
    /// 关键教训（已在隔离环境完整复现验证）：不要给 NSImage 塞 2x 像素的 rep ——
    /// NSImageView 会按像素当点显示，导致只显示上半截；位图像素 = 点（scale 1）
    /// + 翻转上下文修正行序，显示才正确。
    private func makeStripImage(edge: SnapEdge) -> NSImage {
        let glowPad = Self.glowPad
        let len = stripLength(for: edge)
        let t = Self.stripThickness
        let vertical = (edge == .left || edge == .right)
        let viewSize = vertical
            ? NSSize(width: t + glowPad * 2, height: len + glowPad * 2)
            : NSSize(width: len + glowPad * 2, height: t + glowPad * 2)

        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(viewSize.width),
            pixelsHigh: Int(viewSize.height),
            bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0
        ) else { return NSImage(size: viewSize) }

        NSGraphicsContext.saveGraphicsState()
        if let gc = NSGraphicsContext(bitmapImageRep: rep) {
            NSGraphicsContext.current = gc
            let ctx = gc.cgContext
            // 翻转为 y 向下：CGImage 第 0 行 = 设计顶部，NSImageView 直接显示不颠倒
            ctx.translateBy(x: 0, y: viewSize.height)
            ctx.scaleBy(x: 1, y: -1)

            let rect = NSRect(x: glowPad + 0.5, y: glowPad + 0.5,
                              width: (vertical ? t : len) - 1,
                              height: (vertical ? len : t) - 1)
            let cap = min(rect.width, rect.height) / 2
            let path = NSBezierPath(roundedRect: rect, xRadius: cap, yRadius: cap)

            // 1. 外发光（沿胶囊轮廓）
            ctx.saveGState()
            let glow = NSShadow()
            glow.shadowColor = NSColor(red: 1.0, green: 0.55, blue: 0.05, alpha: 0.6)
            glow.shadowBlurRadius = 3.5
            glow.shadowOffset = .zero
            glow.set()
            NSColor(red: 1.0, green: 0.58, blue: 0.10, alpha: 1).setFill()
            path.fill()
            ctx.restoreGState()

            // 2. 渐变填充（翻转上下文 y 向下：angle 90 使亮色在顶部）
            if let gradient = NSGradient(colors: [
                NSColor(red: 1.00, green: 0.74, blue: 0.34, alpha: 1),
                NSColor(red: 1.00, green: 0.58, blue: 0.10, alpha: 1),
                NSColor(red: 0.92, green: 0.44, blue: 0.02, alpha: 1)
            ], atLocations: [0, 0.5, 1], colorSpace: .sRGB) {
                gradient.draw(in: path, angle: 90)
            }

            // 3. 顶部细高光（翻转上下文：顶部 = minY）
            ctx.saveGState()
            path.addClip()
            let rimRect = NSRect(x: rect.minX + cap, y: rect.minY + 0.8,
                                 width: max(0, rect.width - cap * 2), height: 1)
            NSColor.white.withAlphaComponent(0.5).setFill()
            NSBezierPath(rect: rimRect).fill()
            ctx.restoreGState()

            gc.flushGraphics()
        }
        NSGraphicsContext.restoreGraphicsState()

        let img = NSImage(size: viewSize)
        img.addRepresentation(rep)
        return img
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
        // 收起/展开动画期间由动画接管，仅浮动态直接应用
        if case .floating = snapState {
            glass.alphaValue = CGFloat(settings.opacity)
        }
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    // MARK: - 手动拖动（子视图转发）

    /// 点击与拖动的位移阈值：超过才算拖动
    private static let dragThreshold: CGFloat = 3

    func beginDrag() {
        recollapseWork?.cancel()
        didMoveDuringDrag = false
        mouseDownLocation = NSEvent.mouseLocation
        isDragging = true

        if case .collapsed(let edge) = snapState {
            // 点击橙色标识条 → 展开吸附的组件（动画）；
            // 若按住继续拖动，则进入拖动流程直接拖出（见 continueDrag）。
            peek(from: edge)
        }
    }

    func continueDrag() {
        guard isDragging else { return }
        let m = NSEvent.mouseLocation

        if !didMoveDuringDrag {
            // 未超过阈值：视为点击，不动窗口
            guard abs(m.x - mouseDownLocation.x) > Self.dragThreshold
               || abs(m.y - mouseDownLocation.y) > Self.dragThreshold else { return }
            didMoveDuringDrag = true
            if case .peeking(let edge) = snapState {
                // 展开动画可能进行中：立即钉到目标位置，再脱离边缘进入自由拖动
                snapState = .floating
                indicator.alphaValue = 0
                indicator.isHidden = true
                unparkContent()
                glass.isHidden = false
                hosting.isHidden = false
                glass.alphaValue = CGFloat(settings.opacity)
                hosting.alphaValue = 1
                shadowContainer.layer?.shadowOpacity = 1
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0
                    self.animator().setFrame(self.expandedFrameAt(edge: edge), display: true)
                }
            }
            dragOffset = NSPoint(x: m.x - frame.minX, y: m.y - frame.minY)
        }

        if case .peeking = snapState {
            snapState = .floating
        }
        setFrameOrigin(NSPoint(x: m.x - dragOffset.x, y: m.y - dragOffset.y))
    }

    func endDrag() {
        guard isDragging else { return }
        isDragging = false
        // 只有真正拖动过才做吸附判断；纯点击不改变状态
        // （点击橙色条 = 展开；点击展开的面板 = 不做任何操作）
        if didMoveDuringDrag {
            attemptSnap()
        }
    }

    // MARK: - 吸附逻辑

    /// 当前窗口所在屏幕（优先鼠标所在屏，其次与窗口相交面积最大的屏）
    private func currentScreen() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        if let s = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) { return s }
        return NSScreen.screens.max(by: {
            $0.visibleFrame.intersection(frame).width * $0.visibleFrame.intersection(frame).height <
            $1.visibleFrame.intersection(frame).width * $1.visibleFrame.intersection(frame).height
        }) ?? NSScreen.main
    }

    /// 拖动结束：距某条边足够近则吸附收起
    private func attemptSnap() {
        guard let screen = currentScreen() else { return }
        let vf = screen.visibleFrame
        let f = frame

        // 各边距离（负值表示已越界，同样视为贴边）
        let candidates: [(SnapEdge, CGFloat)] = [
            (.left,   f.minX - vf.minX),
            (.right,  vf.maxX - f.maxX),
            (.top,    vf.maxY - f.maxY),
            (.bottom, f.minY - vf.minY)
        ]
        guard let (edge, dist) = candidates.min(by: { $0.1 < $1.1 }),
              dist <= Self.snapThreshold else {
            snapState = .floating
            return
        }
        collapse(to: edge)
    }

    /// 标识条目标 frame（窗口本身缩小为条）。
    /// 注意：以「夹取后的展开位置」expandedFrameAt 为基准居中，
    /// 否则面板部分在屏外时，标识条和展开面板的位置会对不上。
    private func stripFrame(for edge: SnapEdge) -> NSRect {
        guard let screen = currentScreen() else { return frame }
        let vf = screen.visibleFrame
        let f = expandedFrameAt(edge: edge)
        let t = Self.stripThickness + Self.stripPadding * 2   // 窗口厚度（含 padding）

        switch edge {
        case .left, .right:
            let len = stripLength(for: edge) + Self.stripPadding * 2
            let y = min(max(f.midY - len / 2, vf.minY + 4), vf.maxY - len - 4)
            let x = (edge == .left) ? vf.minX : vf.maxX - t
            return NSRect(x: x, y: y, width: t, height: len)
        case .top, .bottom:
            let len = stripLength(for: edge) + Self.stripPadding * 2
            let x = min(max(f.midX - len / 2, vf.minX + 4), vf.maxX - len - 4)
            let y = (edge == .bottom) ? vf.minY : vf.maxY - t
            return NSRect(x: x, y: y, width: len, height: t)
        }
    }

    /// 标识条可视长度（不含 padding）
    private func stripLength(for edge: SnapEdge) -> CGFloat {
        switch edge {
        case .left, .right: return max(56, min(180, expandedFrame.height * 0.5))
        case .top, .bottom: return max(72, min(220, expandedFrame.width * 0.5))
        }
    }

    /// 按吸附边重建标识条约束并渲染位图：细条固定在对应边，垂直/水平居中
    private func pinIndicator(to edge: SnapEdge) {
        NSLayoutConstraint.deactivate(indicatorConstraints)
        let c = shadowContainer
        // 视图比可视胶囊大 glowPad 一圈容纳发光；胶囊距屏幕边 stripPadding
        let p = Self.stripPadding - Self.glowPad
        let t = Self.stripThickness + Self.glowPad * 2
        let len = stripLength(for: edge) + Self.glowPad * 2
        switch edge {
        case .left:
            indicatorConstraints = [
                indicator.leadingAnchor.constraint(equalTo: c.leadingAnchor, constant: p),
                indicator.centerYAnchor.constraint(equalTo: c.centerYAnchor),
                indicator.widthAnchor.constraint(equalToConstant: t),
                indicator.heightAnchor.constraint(equalToConstant: len),
            ]
        case .right:
            indicatorConstraints = [
                indicator.trailingAnchor.constraint(equalTo: c.trailingAnchor, constant: -p),
                indicator.centerYAnchor.constraint(equalTo: c.centerYAnchor),
                indicator.widthAnchor.constraint(equalToConstant: t),
                indicator.heightAnchor.constraint(equalToConstant: len),
            ]
        case .top:
            indicatorConstraints = [
                indicator.topAnchor.constraint(equalTo: c.topAnchor, constant: p),
                indicator.centerXAnchor.constraint(equalTo: c.centerXAnchor),
                indicator.widthAnchor.constraint(equalToConstant: len),
                indicator.heightAnchor.constraint(equalToConstant: t),
            ]
        case .bottom:
            indicatorConstraints = [
                indicator.bottomAnchor.constraint(equalTo: c.bottomAnchor, constant: -p),
                indicator.centerXAnchor.constraint(equalTo: c.centerXAnchor),
                indicator.widthAnchor.constraint(equalToConstant: len),
                indicator.heightAnchor.constraint(equalToConstant: t),
            ]
        }
        NSLayoutConstraint.activate(indicatorConstraints)
        indicator.image = makeStripImage(edge: edge)
    }

    /// 展开时贴边的完整 frame
    private func expandedFrameAt(edge: SnapEdge) -> NSRect {
        guard let screen = currentScreen() else { return expandedFrame }
        let vf = screen.visibleFrame
        var f = expandedFrame
        switch edge {
        case .left:
            f.origin.x = vf.minX
            f.origin.y = min(max(f.minY, vf.minY), vf.maxY - f.height)
        case .right:
            f.origin.x = vf.maxX - f.width
            f.origin.y = min(max(f.minY, vf.minY), vf.maxY - f.height)
        case .top:
            f.origin.y = vf.maxY - f.height
            f.origin.x = min(max(f.minX, vf.minX), vf.maxX - f.width)
        case .bottom:
            f.origin.y = vf.minY
            f.origin.x = min(max(f.minX, vf.minX), vf.maxX - f.width)
        }
        return f
    }

    // MARK: - 内容约束停泊/恢复

    /// 收起态：内容视图改为固定尺寸居中（与 hosting 固有尺寸无冲突）
    private func parkContent() {
        NSLayoutConstraint.deactivate(contentConstraints)
        NSLayoutConstraint.deactivate(parkedConstraints)
        let size = expandedFrame.size
        parkedConstraints = [
            glass.centerXAnchor.constraint(equalTo: shadowContainer.centerXAnchor),
            glass.centerYAnchor.constraint(equalTo: shadowContainer.centerYAnchor),
            glass.widthAnchor.constraint(equalToConstant: size.width),
            glass.heightAnchor.constraint(equalToConstant: size.height),
            hosting.centerXAnchor.constraint(equalTo: shadowContainer.centerXAnchor),
            hosting.centerYAnchor.constraint(equalTo: shadowContainer.centerYAnchor),
            hosting.widthAnchor.constraint(equalToConstant: size.width),
            hosting.heightAnchor.constraint(equalToConstant: size.height),
        ]
        NSLayoutConstraint.activate(parkedConstraints)
    }

    /// 展开/浮动态：内容视图恢复四边撑满
    private func unparkContent() {
        NSLayoutConstraint.deactivate(parkedConstraints)
        NSLayoutConstraint.activate(contentConstraints)
    }

    /// 收起为标识条
    private func collapse(to edge: SnapEdge) {
        if case .floating = snapState {
            expandedFrame = frame
        }
        guard snapState != .collapsed(edge) else { return }
        snapState = .collapsed(edge)
        // 收起动画期间屏蔽悬停展开（0.24 收缩 + 0.18 淡入 + 余量）
        suppressHoverUntil = Date().addingTimeInterval(0.55)
        let target = stripFrame(for: edge)

        // 先把标识条约束重建为「细条」形态（固定厚度，锚定对应边），
        // 而不是撑满整个窗口 —— 否则收缩动画过程中会出现一大块橙色。
        pinIndicator(to: edge)
        indicator.isHidden = false
        // 内容停泊为固定尺寸，避免收缩过程中与 hosting 固有尺寸冲突打坏标识条约束
        parkContent()

        // 阶段一：内容淡出 + 窗口收缩（标识条保持透明，避免闪烁）
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.24
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            ctx.allowsImplicitAnimation = true
            self.animator().setFrame(target, display: true)
            self.glass.animator().alphaValue = 0
            self.hosting.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self, case .collapsed = self.snapState else { return }
            self.glass.isHidden = true
            self.hosting.isHidden = true
            // 细条状态下关掉面板的外阴影，只留标识条自己的橙色光晕
            self.shadowContainer.layer?.shadowOpacity = 0
            // 阶段二：窗口到位后标识条淡入
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.18
                ctx.allowsImplicitAnimation = true
                self.indicator.animator().alphaValue = 1
            }
        })
    }

    /// 点击标识条展开（临时，鼠标移开自动收回）
    private func peek(from edge: SnapEdge) {
        guard snapState == .collapsed(edge) else { return }
        snapState = .peeking(edge)
        let target = expandedFrameAt(edge: edge)

        shadowContainer.layer?.shadowOpacity = 1
        // 阶段一：窗口先扩到完整尺寸（内容仍停泊隐藏，避免小窗约束冲突），标识条快速淡出
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.2
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            ctx.allowsImplicitAnimation = true
            self.animator().setFrame(target, display: true)
            self.indicator.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self, case .peeking = self.snapState else { return }
            self.indicator.isHidden = true
            // 阶段二：恢复内容约束并淡入
            self.unparkContent()
            self.glass.isHidden = false
            self.hosting.isHidden = false
            self.shadowContainer.layoutSubtreeIfNeeded()
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.15
                ctx.allowsImplicitAnimation = true
                self.glass.animator().alphaValue = CGFloat(self.settings.opacity)
                self.hosting.animator().alphaValue = 1
            }
        })
    }

    // MARK: - 悬停跟踪

    private func handleMouseEntered() {
        recollapseWork?.cancel()
        // 屏蔽收起动画期间因 tracking area 重建而补发的假 entered
        guard Date() >= suppressHoverUntil else { return }
        // 二次确认光标确实在窗口内
        guard frame.contains(NSEvent.mouseLocation) else { return }
        // 悬停橙色标识条 → 自动展开
        if case .collapsed(let edge) = snapState {
            peek(from: edge)
        }
    }

    private func handleMouseExited() {
        guard case .peeking(let edge) = snapState, !isDragging else { return }
        // 轻微延迟 + 二次确认鼠标确实离开窗口，避免跟踪抖动
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.snapState == .peeking(edge), !self.isDragging else { return }
            let m = NSEvent.mouseLocation
            if !self.frame.insetBy(dx: -2, dy: -2).contains(m) {
                self.collapse(to: edge)
            }
        }
        recollapseWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    // MARK: - 右键菜单

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

    // MARK: - 缩放

    private func resizeKeepingTopRight() {
        hosting.layoutSubtreeIfNeeded()
        let newSize = hosting.fittingSize
        guard newSize.width > 0, newSize.height > 0 else { return }

        switch snapState {
        case .floating:
            let f = frame
            let maxX = f.maxX
            let maxY = f.maxY
            setContentSize(newSize)
            setFrameOrigin(NSPoint(x: maxX - newSize.width, y: maxY - newSize.height))
        case .collapsed(let edge), .peeking(let edge):
            // 保持展开中心不变，按新尺寸重算展开 frame 与标识条
            let center = NSPoint(x: expandedFrame.midX, y: expandedFrame.midY)
            expandedFrame = NSRect(x: center.x - newSize.width / 2,
                                   y: center.y - newSize.height / 2,
                                   width: newSize.width, height: newSize.height)
            switch snapState {
            case .peeking:
                setFrame(expandedFrameAt(edge: edge), display: true)
            case .collapsed:
                parkContent()
                pinIndicator(to: edge)
                setFrame(stripFrame(for: edge), display: true)
            default:
                break
            }
        }

        let radius = 48 * CGFloat(settings.scale)
        shadowContainer.layer?.shadowPath = CGPath(
            roundedRect: shadowContainer.bounds,
            cornerWidth: radius,
            cornerHeight: radius,
            transform: nil
        )
    }
}

// MARK: - 拖动转发视图

/// 普通 NSView：把鼠标拖动转发给面板（替代 isMovableByWindowBackground，以便拖动结束时吸附）
private class DragForwardingView: NSView {
    override var mouseDownCanMoveWindow: Bool { false }
    override func mouseDown(with event: NSEvent) { (window as? WidgetPanel)?.beginDrag() }
    override func mouseDragged(with event: NSEvent) { (window as? WidgetPanel)?.continueDrag() }
    override func mouseUp(with event: NSEvent) { (window as? WidgetPanel)?.endDrag() }
}

private final class DragForwardingVisualEffectView: NSVisualEffectView {
    override var mouseDownCanMoveWindow: Bool { false }
    override func mouseDown(with event: NSEvent) { (window as? WidgetPanel)?.beginDrag() }
    override func mouseDragged(with event: NSEvent) { (window as? WidgetPanel)?.continueDrag() }
    override func mouseUp(with event: NSEvent) { (window as? WidgetPanel)?.endDrag() }
}

/// 阴影容器：拖动转发 + 悬停进出跟踪（收起态悬停展开 / 展开态移出收回）
private final class TrackingContainerView: DragForwardingView {
    var onMouseEntered: (() -> Void)?
    var onMouseExited: (() -> Void)?
    /// 进出事件去重：窗口 resize 时 tracking area 重建，AppKit 会对光标已在区域内的情况
    /// 补发 mouseEntered，不去重会造成重复触发。
    private var mouseIsInside = false

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseEnteredAndExited],
            owner: self,
            userInfo: nil
        ))
    }

    override func mouseEntered(with event: NSEvent) {
        guard !mouseIsInside else { return }
        mouseIsInside = true
        onMouseEntered?()
    }

    override func mouseExited(with event: NSEvent) {
        guard mouseIsInside else { return }
        mouseIsInside = false
        onMouseExited?()
    }
}

final class WidgetHostView: NSHostingView<AnyView> {
    required init(rootView: AnyView) {
        super.init(rootView: rootView)
    }
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented)")
    }

    override var mouseDownCanMoveWindow: Bool { false }
    override func mouseDown(with event: NSEvent) { (window as? WidgetPanel)?.beginDrag() }
    override func mouseDragged(with event: NSEvent) { (window as? WidgetPanel)?.continueDrag() }
    override func mouseUp(with event: NSEvent) { (window as? WidgetPanel)?.endDrag() }

    override func rightMouseDown(with event: NSEvent) {
        if let panel = self.window as? WidgetPanel {
            panel.showContextMenu(with: event)
        } else {
            super.rightMouseDown(with: event)
        }
    }
}
