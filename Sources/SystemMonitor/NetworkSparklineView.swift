import SwiftUI

/// 网络历史曲线：上/下行双线平滑曲线 + 渐变面积填充，y 轴按窗口内峰值自适应
/// （floor 1KB/s，留 15% 顶部余量）。
///
/// 网络速率无上限，不能像 CPU/内存那样用固定 [0,1] 量程；
/// 这里取缓冲内最大值 ×1.15 作为满量程，空闲时以 1KB/s 兜底，
/// 使微小波动也可见、单点尖刺不会长期压扁整条曲线（60s 后自然老化）。
struct NetworkSparklineView: View {
    let up: [Double]
    let down: [Double]
    let upColor: Color
    let downColor: Color
    var height: CGFloat = 14

    var body: some View {
        Canvas { context, size in
            let n = max(up.count, down.count)
            guard n >= 2 else { return }
            let w = size.width
            let h = size.height

            let rawMax = max(up.max() ?? 0, down.max() ?? 0)
            let mx = max(1024, rawMax) * 1.15
            let stepX = w / CGFloat(n - 1)

            func points(for arr: [Double]) -> [CGPoint]? {
                guard arr.count >= 2 else { return nil }
                return (0..<arr.count).map {
                    CGPoint(x: CGFloat($0) * stepX, y: h - CGFloat(arr[$0] / mx) * h)
                }
            }

            // 先画下载（下层），再画上传（上层覆盖）：渐变面积 + 平滑曲线
            for (arr, color) in [(down, downColor), (up, upColor)] {
                guard let pts = points(for: arr) else { continue }
                let line = SparklineView.smoothPath(pts)

                var fill = line
                fill.addLine(to: CGPoint(x: w, y: h))
                fill.addLine(to: CGPoint(x: 0, y: h))
                fill.closeSubpath()
                context.fill(fill, with: .linearGradient(
                    Gradient(colors: [color.opacity(0.18), color.opacity(0.01)]),
                    startPoint: CGPoint(x: 0, y: 0),
                    endPoint: CGPoint(x: 0, y: h)))

                context.stroke(line, with: .color(color.opacity(0.9)),
                               style: StrokeStyle(lineWidth: 1.1, lineCap: .round, lineJoin: .round))
            }
        }
        .frame(height: height)
    }
}
