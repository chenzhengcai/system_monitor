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
                         color: Color.green,
                         centerLabel: "CPU",
                         size: 72 * scale,
                         lineWidth: 9 * scale)
                RingView(progress: stats.memPercent,
                         color: Color(red: 1.0, green: 0.80, blue: 0.08),
                         centerLabel: "内存",
                         size: 72 * scale,
                         lineWidth: 9 * scale)
                RingView(progress: stats.diskPercent,
                         color: Color.green,
                         centerLabel: "磁盘",
                         size: 72 * scale,
                         lineWidth: 9 * scale)
            }
            NetworkView(up: stats.netUp, down: stats.netDown, scale: scale)
        }
    }
}
