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

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.2), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.0001, min(1, progress)))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.6), value: progress)

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
    }
}