import SwiftUI

/// 整圆环形指标：360° 背景轨道 + 进度弧 + 毛玻璃内盘 + 柔光晕染。
struct RingView: View {
    let progress: Double        // 0..1
    let color: Color
    let centerLabel: String
    var size: CGFloat = 52
    var lineWidth: CGFloat = 7

    /// 进度起点：从正上方（12 点钟方向）开始顺时针
    private let startRotation: Double = -90

    @State private var displayed: Double = 0

    private var pctFont: CGFloat { (size - discInset * 2) * 0.38 }
    private var pctSignFont: CGFloat { pctFont * 0.55 }
    private var labelFont: CGFloat { max(8, (size - discInset * 2) * 0.20) }
    private var discInset: CGFloat { lineWidth * 1.4 }

    var body: some View {
        let p = max(0.0001, min(1, progress))
        let animate = abs(p - displayed) > 0.02

        ZStack {
            // 1. 最外层环境光晕（大扩散、低浓度）
            Circle()
                .fill(
                    RadialGradient(
                        gradient: Gradient(stops: [
                            .init(color: color.opacity(0.28), location: 0.15),
                            .init(color: color.opacity(0.16), location: 0.45),
                            .init(color: color.opacity(0.06), location: 0.75),
                            .init(color: .clear, location: 1.0)
                        ]),
                        center: .center,
                        startRadius: size * 0.08,
                        endRadius: size * 0.52
                    )
                )
                .frame(width: size, height: size)
                .blur(radius: lineWidth * 1.8)

            // 2. 背景轨道环（整圆，半透明同色）
            Circle()
                .stroke(
                    color.opacity(0.20),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .frame(width: size - lineWidth, height: size - lineWidth)
                .blur(radius: lineWidth * 0.2)

            // 3. 毛玻璃内盘
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            gradient: Gradient(stops: [
                                .init(color: color.opacity(0.42), location: 0.0),
                                .init(color: color.opacity(0.26), location: 0.5),
                                .init(color: color.opacity(0.14), location: 1.0)
                            ]),
                            center: .center,
                            startRadius: 0,
                            endRadius: (size - discInset * 2) * 0.52
                        )
                    )

                Circle()
                    .fill(.ultraThinMaterial)
                    .opacity(0.68)

                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.34),
                                Color.white.opacity(0.08),
                                Color.black.opacity(0.07)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                // 顶部高光边
                Circle()
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.75),
                                Color.white.opacity(0.30),
                                .clear
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
                    .mask(
                        VStack(spacing: 0) { Rectangle() }
                            .frame(maxHeight: (size - discInset * 2) * 0.42)
                            .frame(maxHeight: .infinity, alignment: .top)
                    )
            }
            .frame(width: size - discInset * 2, height: size - discInset * 2)

            // 4. 进度弧（整圆，从顶部顺时针）
            Circle()
                .trim(from: 0, to: p)
                .stroke(
                    color,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(startRotation))
                .shadow(color: color.opacity(0.50), radius: lineWidth * 0.7, x: 0, y: 0)
                .animation(animate ? .easeInOut(duration: 0.3) : nil, value: progress)
                .frame(width: size - lineWidth, height: size - lineWidth)

            // 5. 中心内容：数字 + % + 标签
            VStack(spacing: 1) {
                HStack(alignment: .lastTextBaseline, spacing: 1) {
                    Text("\(Int(p * 100))")
                        .font(.system(size: pctFont, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                    Text("%")
                        .font(.system(size: pctSignFont, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                        .padding(.bottom, pctFont * 0.06)
                }
                Text(centerLabel)
                    .font(.system(size: labelFont, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .offset(y: 1)
        }
        .frame(width: size, height: size)
        .onChange(of: p) { _, newP in displayed = newP }
    }
}
