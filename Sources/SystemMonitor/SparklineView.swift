import SwiftUI

/// 迷你历史曲线（sparkline）：固定量程 [0,1]，单条折线 + 渐变填充。
///
/// 用 `Canvas` 单次绘制，每秒随 snapshot 重绘一次，开销可忽略
/// （与环形图 60Hz 动画完全不同量级）。线条颜色与对应环形图绑定，
/// 视觉上「环 = 当前值，曲线 = 近 60s 趋势」一体。
struct SparklineView: View {
    let values: [Double]          // 期望 0..1
    let color: Color
    var height: CGFloat = 10

    var body: some View {
        Canvas { context, size in
            let n = values.count
            guard n >= 2 else { return }
            let w = size.width
            let h = size.height
            let stepX = w / CGFloat(n - 1)

            func point(_ i: Int) -> CGPoint {
                let v = max(0, min(1, values[i]))
                return CGPoint(x: CGFloat(i) * stepX, y: h - CGFloat(v) * h)
            }

            var line = Path()
            line.move(to: point(0))
            for i in 1..<n { line.addLine(to: point(i)) }

            // 线下渐变填充（同色 0.22 → 0.02），呼应 DSFSparkline 的经典观感
            var fill = line
            fill.addLine(to: CGPoint(x: w, y: h))
            fill.addLine(to: CGPoint(x: 0, y: h))
            fill.closeSubpath()
            context.fill(fill, with: .linearGradient(
                Gradient(colors: [color.opacity(0.22), color.opacity(0.02)]),
                startPoint: CGPoint(x: 0, y: 0),
                endPoint: CGPoint(x: 0, y: h)))

            // 折线（圆角端点，1.2px，小尺寸下仍清晰）
            context.stroke(line, with: .color(color),
                           style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round))
        }
        .frame(height: height)
    }
}
