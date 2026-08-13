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
        .overlay(PanelRimOverlay(scale: s))
    }
}

/// 面板边缘立体叠加层：顶部镜面高光 + 底部内阴影 + 侧边渐变。
private struct PanelRimOverlay: View {
    let scale: CGFloat
    var body: some View {
        let radius = 48 * scale
        ZStack {
            // 顶部镜面高光带
            VStack(spacing: 0) {
                RoundedRectangle(cornerRadius: radius * 0.6, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.65),
                                Color.white.opacity(0.25),
                                .clear
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(height: radius * 0.55)
                    .padding(.top, 1.5)
                    .padding(.horizontal, radius * 0.25)
                Spacer(minLength: 0)
            }

            // 顶部边缘高光线
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.85),
                            Color.white.opacity(0.45),
                            .clear
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1.2
                )
                .mask(
                    VStack(spacing: 0) { Rectangle() }
                        .frame(maxHeight: radius * 0.65)
                        .frame(maxHeight: .infinity, alignment: .top)
                )
                .padding(0.5)

            // 左右侧轻微暗化
            HStack(spacing: 0) {
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [Color.black.opacity(0.08), .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: 3)
                Spacer()
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [.clear, Color.black.opacity(0.08)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: 3)
            }

            // 底部内阴影
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(Color.black.opacity(0.20), lineWidth: 1)
                .offset(y: 0.8)
                .blur(radius: 0.6)
                .mask(
                    VStack(spacing: 0) { Spacer(); Rectangle() }
                        .frame(maxHeight: radius * 0.5)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                )
                .padding(0.5)
        }
    }
}

struct StatsContent: View {
    @EnvironmentObject var stats: StatsCollector
    let scale: CGFloat

    var body: some View {
        VStack(spacing: 14 * scale) {
            HStack(spacing: 0) {
                metricColumn(
                    ringProgress: stats.cpuPercent,
                    ringColor: cpuColor(stats.cpuPercent),
                    ringLabel: "CPU",
                    history: stats.cpuHistory,
                    historyColor: cpuColor(stats.cpuPercent)
                )

                columnDivider

                metricColumn(
                    ringProgress: stats.memPercent,
                    ringColor: memColor(stats.memPercent),
                    ringLabel: "内存",
                    history: stats.memHistory,
                    historyColor: memColor(stats.memPercent)
                )

                columnDivider

                metricColumn(
                    ringProgress: stats.diskPercent,
                    ringColor: diskColor(stats.diskPercent),
                    ringLabel: "磁盘",
                    history: stats.diskHistory,
                    historyColor: diskColor(stats.diskPercent)
                )
            }

            VStack(spacing: 4 * scale) {
                NetworkView(up: stats.netUp, down: stats.netDown, scale: scale)
                NetworkSparklineView(up: stats.netUpHistory,
                                     down: stats.netDownHistory,
                                     upColor: .green,
                                     downColor: Color(red: 0.35, green: 0.55, blue: 1.0),
                                     height: 12 * scale)
                    .padding(.horizontal, 6 * scale)
                    .padding(.bottom, 2 * scale)
            }
        }
    }

    /// 指标列之间的发丝级分隔线（上下渐隐，避免生硬）
    private var columnDivider: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [
                        .clear,
                        Color.primary.opacity(0.10),
                        Color.primary.opacity(0.10),
                        .clear
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(width: 1, height: 78 * scale)
            .padding(.horizontal, 9.5 * scale)
    }

    private func metricColumn(
        ringProgress: Double,
        ringColor: Color,
        ringLabel: String,
        history: [Double],
        historyColor: Color
    ) -> some View {
        VStack(spacing: 6 * scale) {
            ZStack {
                // 底部柔和阴影（让环形图"坐"在面板上）
                Ellipse()
                    .fill(Color.black.opacity(0.15))
                    .frame(width: 72 * scale * 0.60, height: 72 * scale * 0.12)
                    .blur(radius: 2.5)
                    .offset(y: 72 * scale * 0.48)

                RingView(progress: ringProgress,
                         color: ringColor,
                         centerLabel: ringLabel,
                         size: 72 * scale,
                         lineWidth: 9 * scale)
            }

            SparklineView(values: history, color: historyColor, height: 10 * scale)
                .padding(.horizontal, 2 * scale)
        }
    }

    // MARK: - 动态颜色

    private let cpuLow  = Color(red: 0.243, green: 0.761, blue: 0.337)
    private let diskLow = Color(red: 0.102, green: 0.800, blue: 0.761)
    private let memLow  = Color(red: 0.949, green: 0.769, blue: 0.310)

    private let midColor = Color(red: 1.0, green: 0.60, blue: 0.15)
    private let highColor = Color(red: 0.95, green: 0.25, blue: 0.20)

    private func cpuColor(_ p: Double) -> Color { dynamicColor(p, low: cpuLow) }
    private func memColor(_ p: Double) -> Color { dynamicColor(p, low: memLow) }
    private func diskColor(_ p: Double) -> Color { dynamicColor(p, low: diskLow) }

    private func dynamicColor(_ p: Double, low: Color) -> Color {
        if p <= 0.5 {
            return low
        } else if p <= 0.80 {
            let t = (p - 0.5) / 0.30
            return mix(low, midColor, t: t)
        } else {
            let t = min(1.0, (p - 0.80) / 0.20)
            return mix(midColor, highColor, t: t)
        }
    }

    private func mix(_ a: Color, _ b: Color, t: Double) -> Color {
        let na = NSColor(a)
        let nb = NSColor(b)
        let r = na.redComponent   + (nb.redComponent   - na.redComponent)   * CGFloat(t)
        let g = na.greenComponent + (nb.greenComponent - na.greenComponent) * CGFloat(t)
        let bl = na.blueComponent + (nb.blueComponent  - na.blueComponent)  * CGFloat(t)
        return Color(red: Double(r), green: Double(g), blue: Double(bl))
    }
}
