import SwiftUI

/// 面板主内容：三个小环形图 + 网络条，背景全透明。
/// 外层只依赖 settings，不读取每秒变化的 stats，
/// 避免 stats 每秒更新时重建子视图树。
/// 右键菜单由窗口层（WidgetPanel）接管，可覆盖面板任意区域。
struct ContentView: View {
    @EnvironmentObject var settings: WidgetSettings

    var body: some View {
        let s = settings.scale
        return VStack {
            StatsContent(scale: s)
        }
        .padding(10 * s)
        .frame(width: 224 * s)
    }
}

/// 真正读取每秒 stats 的子视图：仅它在每次数据更新时重渲染。
struct StatsContent: View {
    @EnvironmentObject var stats: StatsCollector
    let scale: CGFloat

    var body: some View {
        VStack(spacing: 8 * scale) {
            HStack(spacing: 16 * scale) {
                RingView(progress: stats.cpuPercent,
                         color: ringColor(stats.cpuPercent),
                         centerLabel: "CPU",
                         size: 52 * scale,
                         lineWidth: 7 * scale)
                RingView(progress: stats.memPercent,
                         color: .orange,
                         centerLabel: "内存",
                         size: 52 * scale,
                         lineWidth: 7 * scale)
                RingView(progress: stats.diskPercent,
                         color: .purple,
                         centerLabel: "磁盘",
                         size: 52 * scale,
                         lineWidth: 7 * scale)
            }
            NetworkView(up: stats.netUp, down: stats.netDown, scale: scale)
        }
    }

    private func ringColor(_ p: Double) -> Color {
        if p < 0.5 { return .green }
        if p < 0.8 { return .yellow }
        return .red
    }
}