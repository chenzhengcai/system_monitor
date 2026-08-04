import SwiftUI

/// 环形图：Circle.trim 自绘 donut，中心显示百分比与小标题。
/// 尺寸由 `size` 控制（受组件缩放驱动），背景透明，开销极低。
struct RingView: View {
    let progress: Double        // 0..1
    let color: Color
    let centerLabel: String
    var size: CGFloat = 52
    var lineWidth: CGFloat = 7

    private var pctFont: CGFloat { size * 0.23 }
    private var labelFont: CGFloat { max(7, size * 0.154) }

    /// 记录上一次展示的进度，用于判断本次变化是否值得播放动画。
    @State private var displayed: Double = 0

    var body: some View {
        // trim 的 0 会触发渲染异常，用极小正数值兜底（非 bug，刻意处理）。
        let p = max(0.0001, min(1, progress))
        // 变化小于 3% 时跳过动画，避免每秒抖动都重绘整圈（常驻后台省电）。
        let animate = abs(p - displayed) > 0.03
        return ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.2), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: p)
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(animate ? .easeInOut(duration: 0.25) : nil, value: progress)
            VStack(spacing: 0) {
                Text("\(Int(max(0, min(1, progress)) * 100))%")
                    .font(.system(size: pctFont, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text(centerLabel)
                    .font(.system(size: labelFont))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .onChange(of: p) { _, newP in displayed = newP }
    }
}
