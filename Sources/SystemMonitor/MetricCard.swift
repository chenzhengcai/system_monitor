import SwiftUI

/// 毛玻璃立体感指标卡 —— 严格对齐参考设计。
struct MetricCard: View {
    let progress: Double
    let color: Color
    let title: String
    let valueText: String
    let unitText: String?

    var cardSize: CGFloat = 64
    var lineWidth: CGFloat = 6

    private let arcSpan: Double = 0.75
    private let arcStart: Double = 0.125

    @State private var displayed: Double = 0

    private var cardRadius: CGFloat { cardSize * 0.30 }
    private var discSize: CGFloat { cardSize * 0.72 }
    private var ringSize: CGFloat { discSize * 0.80 }
    private var pctFont: CGFloat { cardSize * 0.32 }
    private var titleFont: CGFloat { max(9, cardSize * 0.14) }
    private var unitFont: CGFloat { max(7, cardSize * 0.10) }

    var body: some View {
        let p = max(0, min(1, progress))
        let animate = abs(p - displayed) > 0.03

        ZStack {
            // 0. 外光晕
            RoundedRectangle(cornerRadius: cardRadius, style: .continuous)
                .fill(
                    RadialGradient(
                        gradient: Gradient(colors: [
                            color.opacity(0.28),
                            color.opacity(0.10),
                            .clear
                        ]),
                        center: .center,
                        startRadius: cardSize * 0.22,
                        endRadius: cardSize * 0.85
                    )
                )
                .blur(radius: cardSize * 0.08)
                .frame(width: cardSize * 1.25, height: cardSize * 1.25)

            // MARK: 方玻璃卡
            RoundedRectangle(cornerRadius: cardRadius, style: .continuous)
                .fill(Color.white.opacity(0.56))

            RoundedRectangle(cornerRadius: cardRadius, style: .continuous)
                .fill(.thinMaterial)

            // 上亮下暗
            RoundedRectangle(cornerRadius: cardRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.24),
                            Color.white.opacity(0.05),
                            Color.black.opacity(0.07)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            // 顶部柔光反射
            VStack(spacing: 0) {
                RoundedRectangle(cornerRadius: cardRadius * 0.35, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.40),
                                Color.white.opacity(0.08),
                                .clear
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(height: cardRadius * 0.6)
                    .padding(.top, 1)
                    .padding(.horizontal, cardRadius * 0.2)
                Spacer(minLength: 0)
            }

            TopRimHighlight(radius: cardRadius, lineWidth: 1.8, maskHeight: 0.6)
                .allowsHitTesting(false)

            BottomInnerShadow(radius: cardRadius, opacity: 0.10, blur: 0.7)
                .allowsHitTesting(false)

            // MARK: 内部玻璃圆盘（凸起立体感）
            ZStack {
                // 同色径向渐变
                Circle()
                    .fill(
                        RadialGradient(
                            gradient: Gradient(colors: [
                                color.opacity(0.40),
                                color.opacity(0.22),
                                color.opacity(0.10),
                                .clear
                            ]),
                            center: .center,
                            startRadius: 0,
                            endRadius: discSize * 0.55
                        )
                    )

                // 玻璃层
                Circle()
                    .fill(.thinMaterial)
                    .opacity(0.68)

                // 上亮下暗
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.22),
                                Color.white.opacity(0.03),
                                Color.black.opacity(0.06)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                // 圆盘顶部高光（锐利描边）
                Circle()
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.90),
                                Color.white.opacity(0.40),
                                Color.white.opacity(0.05)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1.2
                    )
                    .mask(
                        VStack(spacing: 0) { Rectangle(); Spacer() }
                            .frame(maxHeight: .infinity, alignment: .top)
                            .frame(maxHeight: discSize * 0.45)
                    )

                // 圆盘底部暗边
                Circle()
                    .strokeBorder(Color.black.opacity(0.08), lineWidth: 0.8)
                    .offset(y: 0.4)
                    .blur(radius: 0.4)
                    .mask(
                        VStack(spacing: 0) { Spacer(); Rectangle() }
                            .frame(maxHeight: .infinity, alignment: .bottom)
                            .frame(maxHeight: discSize * 0.4)
                    )

                // 背景轨道弧
                Circle()
                    .trim(from: arcStart, to: arcStart + arcSpan)
                    .stroke(
                        color.opacity(0.22),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                    )
                    .frame(width: ringSize, height: ringSize)

                // 进度弧
                Circle()
                    .trim(from: arcStart, to: arcStart + max(0.0001, p) * arcSpan)
                    .stroke(
                        color,
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                    )
                    .shadow(color: color.opacity(0.60), radius: 5, x: 0, y: 0)
                    .animation(animate ? .easeInOut(duration: 0.25) : nil, value: progress)
                    .frame(width: ringSize, height: ringSize)

                // 中心数字 + 标签
                VStack(spacing: 0) {
                    HStack(alignment: .lastTextBaseline, spacing: 1) {
                        Text(valueText)
                            .font(.system(size: pctFont, weight: .heavy, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.primary)
                        if let unitText {
                            Text(unitText)
                                .font(.system(size: unitFont, weight: .semibold, design: .rounded))
                                .foregroundStyle(.secondary)
                                .offset(y: -0.5)
                        }
                    }
                    Text(title)
                        .font(.system(size: titleFont, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)
                }
            }
            .frame(width: discSize, height: discSize)
            .shadow(color: Color.black.opacity(0.12), radius: 6, x: 0, y: 3)
            .shadow(color: color.opacity(0.18), radius: 7, x: 0, y: 0)
        }
        .frame(width: cardSize, height: cardSize)
        .shadow(color: Color.black.opacity(0.14), radius: 11, x: 0, y: 7)
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
        .onChange(of: p) { _, newP in displayed = newP }
    }
}

private struct TopRimHighlight: View {
    let radius: CGFloat
    var lineWidth: CGFloat = 1.8
    var maskHeight: CGFloat = 0.6

    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .strokeBorder(
                LinearGradient(
                    colors: [
                        Color.white.opacity(1.0),
                        Color.white.opacity(0.85),
                        Color.white.opacity(0.22),
                        Color.white.opacity(0.04)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                lineWidth: lineWidth
            )
            .mask(
                VStack(spacing: 0) {
                    Rectangle().frame(maxHeight: .infinity)
                    Spacer(minLength: 0)
                }
                .frame(maxHeight: radius * maskHeight)
                .frame(maxHeight: .infinity, alignment: .top)
            )
    }
}

private struct BottomInnerShadow: View {
    let radius: CGFloat
    var opacity: Double = 0.10
    var blur: CGFloat = 0.7

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            RoundedRectangle(cornerRadius: radius * 0.3, style: .continuous)
                .fill(Color.black.opacity(opacity))
                .frame(height: 1.6)
                .padding(.bottom, 1)
                .padding(.horizontal, radius * 0.22)
                .blur(radius: blur)
        }
        .mask(
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                Rectangle()
            }
            .frame(maxHeight: radius * 0.55)
            .frame(maxHeight: .infinity, alignment: .bottom)
        )
    }
}
