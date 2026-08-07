import SwiftUI

/// 3D 立体感环形指标：轨道深凹 + 渐变弧面 + 凸盘投影 + 端点镜面高光。
/// 性能原则：动画仅作用于 stroke 本身的 .trim，所有渐变/高光均为静态层，
/// 不在动画元素上加 .blur() / .shadow()，避免每秒触发离屏渲染。
struct RingView: View {
    let progress: Double        // 0..1
    let color: Color
    let centerLabel: String
    var size: CGFloat = 52
    var lineWidth: CGFloat = 7

    private let startRotation: Double = -90

    @State private var displayed: Double = 0

    private var pctFont: CGFloat { (size - discInset * 2) * 0.38 }
    private var pctSignFont: CGFloat { pctFont * 0.55 }
    private var labelFont: CGFloat { max(8, (size - discInset * 2) * 0.20) }
    private var discInset: CGFloat { lineWidth * 1.4 }

    var body: some View {
        let p = max(0.0001, min(1, progress))
        let animate = abs(p - displayed) > 0.02

        ZStack {
            // 1. 环境外光晕（静态，氛围用）
            Circle()
                .fill(
                    RadialGradient(
                        gradient: Gradient(stops: [
                            .init(color: color.opacity(0.16), location: 0.30),
                            .init(color: color.opacity(0.06), location: 0.65),
                            .init(color: .clear, location: 1.0)
                        ]),
                        center: .center,
                        startRadius: size * 0.04,
                        endRadius: size * 0.60
                    )
                )
                .frame(width: size, height: size)
                .blur(radius: lineWidth * 1.8)

            // 2. 轨道环 —— 深凹效果
            // 外层暗边（凹槽上沿投影）
            Circle()
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.black.opacity(0.40),
                            Color.black.opacity(0.18),
                            Color.white.opacity(0.06),
                            Color.white.opacity(0.22)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    style: StrokeStyle(lineWidth: lineWidth + 1.5, lineCap: .round)
                )
                .frame(width: size - lineWidth, height: size - lineWidth)

            // 内层：同色底（透出颜色基调，上暗下亮呼应凹槽光影）
            Circle()
                .stroke(
                    LinearGradient(
                        colors: [
                            color.opacity(0.10),
                            color.opacity(0.16),
                            color.opacity(0.20)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    style: StrokeStyle(lineWidth: lineWidth * 0.65, lineCap: .round)
                )
                .frame(width: size - lineWidth, height: size - lineWidth)

            // 3. 内盘 —— 凸起立体感
            ZStack {
                // 盘底深色接触阴影（最实，模拟盘压在面板上）
                Ellipse()
                    .fill(Color.black.opacity(0.20))
                    .frame(width: (size - discInset * 2) * 0.75,
                           height: (size - discInset * 2) * 0.12)
                    .offset(y: (size - discInset * 2) * 0.48)
                    .blur(radius: 1.5)

                // 同色径向底色（中心稍亮、边缘稍深）
                Circle()
                    .fill(
                        RadialGradient(
                            gradient: Gradient(stops: [
                                .init(color: color.opacity(0.34), location: 0.0),
                                .init(color: color.opacity(0.20), location: 0.55),
                                .init(color: color.opacity(0.10), location: 1.0)
                            ]),
                            center: .center,
                            startRadius: 0,
                            endRadius: (size - discInset * 2) * 0.55
                        )
                    )

                // 毛玻璃层
                Circle()
                    .fill(.ultraThinMaterial)
                    .opacity(0.68)

                // 上亮下暗的立体光影（顶光）
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.50),
                                Color.white.opacity(0.18),
                                Color.white.opacity(0.02),
                                Color.black.opacity(0.07),
                                Color.black.opacity(0.15)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                // 顶部高光弧（锐利，模拟凸面顶部反光带）
                Circle()
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.95),
                                Color.white.opacity(0.65),
                                .clear
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1.5
                    )
                    .mask(
                        VStack(spacing: 0) { Rectangle() }
                            .frame(maxHeight: (size - discInset * 2) * 0.36)
                            .frame(maxHeight: .infinity, alignment: .top)
                    )

                // 底部暗边（盘底压重）
                Circle()
                    .strokeBorder(Color.black.opacity(0.20), lineWidth: 0.8)
                    .offset(y: 0.8)
                    .blur(radius: 0.5)
                    .mask(
                        VStack(spacing: 0) { Spacer(); Rectangle() }
                            .frame(maxHeight: (size - discInset * 2) * 0.33)
                            .frame(maxHeight: .infinity, alignment: .bottom)
                    )
            }
            .frame(width: size - discInset * 2, height: size - discInset * 2)

            // 4. 进度弧 —— 3D 圆柱弧面渐变
            //    顶部高光带 → 上半本色 → 下半本色 → 底部压暗
            Circle()
                .trim(from: 0, to: p)
                .stroke(
                    LinearGradient(
                        colors: [
                            color.brightened(by: 0.55),
                            color.brightened(by: 0.30),
                            color,
                            color,
                            color.darkened(by: 0.20)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(startRotation))
                .animation(animate ? .easeInOut(duration: 0.3) : nil, value: progress)
                .frame(width: size - lineWidth, height: size - lineWidth)

            // 5. 进度端点高光帽
            ProgressEndpointCap(
                progress: p,
                radius: (size - lineWidth) * 0.5,
                lineWidth: lineWidth,
                color: color
            )
            .animation(animate ? .easeInOut(duration: 0.3) : nil, value: progress)
            .frame(width: size, height: size)

            // 6. 中心文字
            VStack(spacing: 1) {
                HStack(alignment: .lastTextBaseline, spacing: 1) {
                    Text("\(Int(p * 100))")
                        .font(.system(size: pctFont, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                    Text("%")
                        .font(.system(size: pctSignFont, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                        .padding(.bottom, pctFont * 0.06)
                }
                Text(centerLabel)
                    .font(.system(size: labelFont, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .shadow(color: Color.white.opacity(0.6), radius: 0.5, x: 0, y: 0.5)
            .offset(y: 1)
        }
        .frame(width: size, height: size)
        .onChange(of: p) { _, newP in displayed = newP }
    }
}

// MARK: - 进度端点高光帽

private struct ProgressEndpointCap: View {
    let progress: Double
    let radius: CGFloat
    let lineWidth: CGFloat
    let color: Color

    var body: some View {
        let angle = -90.0 + progress * 360.0
        let rad = CGFloat(angle * .pi / 180.0)
        let x = cos(rad) * radius
        let y = sin(rad) * radius
        let capSize = lineWidth * 0.78

        return ZStack {
            // 外层：加亮的同色圆
            Circle()
                .fill(color.brightened(by: 0.50))
                .frame(width: capSize, height: capSize)
                .offset(x: x, y: y)

            // 内层：白色镜面高光（偏移模拟光源方向）
            Circle()
                .fill(Color.white.opacity(0.90))
                .frame(width: capSize * 0.46, height: capSize * 0.46)
                .offset(x: x - capSize * 0.10, y: y - capSize * 0.10)
        }
    }
}

// MARK: - Color 亮度调整

private extension Color {
    /// 提亮：向白色插值，amount 0...1（基于 sRGB，兼容所有颜色空间）
    func brightened(by amount: Double) -> Color {
        let ns = NSColor(self).usingColorSpace(.sRGB) ?? NSColor(self)
        let r = ns.redComponent
        let g = ns.greenComponent
        let b = ns.blueComponent
        let a = ns.alphaComponent
        return Color(red: Double(r + (1 - r) * CGFloat(amount)),
                     green: Double(g + (1 - g) * CGFloat(amount)),
                     blue: Double(b + (1 - b) * CGFloat(amount)),
                     opacity: Double(a))
    }

    /// 压暗：向黑色插值，amount 0...1
    func darkened(by amount: Double) -> Color {
        let ns = NSColor(self).usingColorSpace(.sRGB) ?? NSColor(self)
        let r = ns.redComponent
        let g = ns.greenComponent
        let b = ns.blueComponent
        let a = ns.alphaComponent
        return Color(red: Double(r * (1 - CGFloat(amount))),
                     green: Double(g * (1 - CGFloat(amount))),
                     blue: Double(b * (1 - CGFloat(amount))),
                     opacity: Double(a))
    }
}
