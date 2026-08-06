import SwiftUI

/// 网络历史曲线：上/下行双线，y 轴按窗口内峰值自适应（floor 1KB/s，留 15% 顶部余量）。
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

            func path(for arr: [Double]) -> Path? {
                guard arr.count >= 2 else { return nil }
                var p = Path()
                p.move(to: CGPoint(x: 0, y: h - CGFloat(arr[0] / mx) * h))
                for i in 1..<arr.count {
                    p.addLine(to: CGPoint(x: CGFloat(i) * stepX, y: h - CGFloat(arr[i] / mx) * h))
                }
                return p
            }

            // 先画下载（下层），再画上传（上层覆盖）
            if let p = path(for: down) {
                context.stroke(p, with: .color(downColor.opacity(0.9)),
                               style: StrokeStyle(lineWidth: 1.0, lineCap: .round, lineJoin: .round))
            }
            if let p = path(for: up) {
                context.stroke(p, with: .color(upColor.opacity(0.9)),
                               style: StrokeStyle(lineWidth: 1.0, lineCap: .round, lineJoin: .round))
            }
        }
        .frame(height: height)
    }
}
