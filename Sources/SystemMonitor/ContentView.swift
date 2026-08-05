import SwiftUI

/// 面板主内容：三个小环形图 + 网络条，背景全透明。
struct ContentView: View {
    @EnvironmentObject var settings: WidgetSettings

    var body: some View {
        let s = settings.scale
        return VStack {
            StatsContent(scale: s)
        }
        .padding(18 * s)
        .frame(width: 310 * s)
    }
}

/// 真正读取每秒 stats 的子视图。
struct StatsContent: View {
    @EnvironmentObject var stats: StatsCollector
    let scale: CGFloat

    var body: some View {
        VStack(spacing: 18 * scale) {
            HStack(spacing: 20 * scale) {
                RingView(progress: stats.cpuPercent,
                         color: cpuColor(stats.cpuPercent),
                         centerLabel: "CPU",
                         size: 72 * scale,
                         lineWidth: 9 * scale)
                RingView(progress: stats.memPercent,
                         color: memColor(stats.memPercent),
                         centerLabel: "内存",
                         size: 72 * scale,
                         lineWidth: 9 * scale)
                RingView(progress: stats.diskPercent,
                         color: diskColor(stats.diskPercent),
                         centerLabel: "磁盘",
                         size: 72 * scale,
                         lineWidth: 9 * scale)
            }
            NetworkView(up: stats.netUp, down: stats.netDown, scale: scale)
        }
    }

    // MARK: - 动态颜色

    /// 正常色（< 50%）
    private let cpuLow  = Color(red: 0.243, green: 0.761, blue: 0.337)   // #3EC256
    private let diskLow = Color(red: 0.102, green: 0.800, blue: 0.761)   // #1ACCC2
    private let memLow  = Color(red: 0.949, green: 0.769, blue: 0.310)   // #F2C44F

    /// 中警告色（50% ~ 85%）— 橙色
    private let midColor = Color(red: 1.0, green: 0.60, blue: 0.15)       // 橙
    /// 高警告色（> 85%）— 红色
    private let highColor = Color(red: 0.95, green: 0.25, blue: 0.20)     // 红

    private func cpuColor(_ p: Double) -> Color { dynamicColor(p, low: cpuLow) }
    private func memColor(_ p: Double) -> Color { dynamicColor(p, low: memLow) }
    private func diskColor(_ p: Double) -> Color { dynamicColor(p, low: diskLow) }

    /// 根据进度返回颜色：<50% 低色 / 50-80% 橙 / >80% 红，区间内平滑过渡
    private func dynamicColor(_ p: Double, low: Color) -> Color {
        if p <= 0.5 {
            return low
        } else if p <= 0.80 {
            // 50% → 85%：从低色平滑过渡到橙色
            let t = (p - 0.5) / 0.30
            return mix(low, midColor, t: t)
        } else {
            // 85% → 100%：从橙色平滑过渡到红色
            let t = min(1.0, (p - 0.80) / 0.20)
            return mix(midColor, highColor, t: t)
        }
    }

    /// 两个颜色线性插值
    private func mix(_ a: Color, _ b: Color, t: Double) -> Color {
        // 用 NSColor 来取 RGB 分量
        let na = NSColor(a)
        let nb = NSColor(b)
        let r = na.redComponent   + (nb.redComponent   - na.redComponent)   * CGFloat(t)
        let g = na.greenComponent + (nb.greenComponent - na.greenComponent) * CGFloat(t)
        let bl = na.blueComponent + (nb.blueComponent  - na.blueComponent)  * CGFloat(t)
        return Color(red: Double(r), green: Double(g), blue: Double(bl))
    }
}
