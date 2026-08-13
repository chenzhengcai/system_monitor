import SwiftUI

/// 迷你历史曲线（sparkline）：固定量程 [0,1]，Catmull-Rom 平滑折线 + 渐变填充 + 末端光点。
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

            let pts = (0..<n).map(point)
            let line = Self.smoothPath(pts)

            // 线下渐变填充（同色 0.26 → 0.02），呼应 DSFSparkline 的经典观感
            var fill = line
            fill.addLine(to: CGPoint(x: w, y: h))
            fill.addLine(to: CGPoint(x: 0, y: h))
            fill.closeSubpath()
            context.fill(fill, with: .linearGradient(
                Gradient(colors: [color.opacity(0.26), color.opacity(0.02)]),
                startPoint: CGPoint(x: 0, y: 0),
                endPoint: CGPoint(x: 0, y: h)))

            // 平滑曲线（圆角端点，1.4px，小尺寸下仍清晰）
            context.stroke(line, with: .color(color),
                           style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))

            // 末端光点：外圈同色光晕 + 内圈亮核，标记"最新值"
            if let last = pts.last {
                let glowR: CGFloat = 2.6
                let coreR: CGFloat = 1.3
                context.fill(Path(ellipseIn: CGRect(x: last.x - glowR, y: last.y - glowR,
                                                    width: glowR * 2, height: glowR * 2)),
                             with: .color(color.opacity(0.35)))
                context.fill(Path(ellipseIn: CGRect(x: last.x - coreR, y: last.y - coreR,
                                                    width: coreR * 2, height: coreR * 2)),
                             with: .color(color))
            }
        }
        .frame(height: height)
    }

    /// Catmull-Rom 转三次贝塞尔，让历史曲线平滑不扎眼
    static func smoothPath(_ pts: [CGPoint]) -> Path {
        var p = Path()
        guard pts.count > 1 else { return p }
        p.move(to: pts[0])
        for i in 0..<(pts.count - 1) {
            let p0 = pts[max(i - 1, 0)]
            let p1 = pts[i]
            let p2 = pts[i + 1]
            let p3 = pts[min(i + 2, pts.count - 1)]
            let c1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6)
            let c2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
            p.addCurve(to: p2, control1: c1, control2: c2)
        }
        return p
    }
}
