import SwiftUI

/// 网络实时速率条：窄款浮雕胶囊 + 精致玻璃箭头按钮。
struct NetworkView: View {
    let up: UInt64
    let down: UInt64
    var scale: CGFloat = 1.0

    private var barHeight: CGFloat { 40 * scale }
    private var barRadius: CGFloat { barHeight * 0.5 }
    private var arrowCircleSize: CGFloat { 24 * scale }
    private var arrowFont: CGFloat { 12 * scale }
    private var valueFont: CGFloat { 14 * scale }
    private var unitFont: CGFloat { 10 * scale }
    private var hPadding: CGFloat { 12 * scale }
    private var innerGap: CGFloat { 8 * scale }

    var body: some View {
        HStack(spacing: 0) {
            part(symbol: "arrow.up", value: up, color: Color.green)
            divider
            part(symbol: "arrow.down", value: down, color: Color(red: 0.35, green: 0.55, blue: 1.0))
        }
        .padding(.horizontal, hPadding)
        .frame(height: barHeight)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: barRadius, style: .continuous)
                    .fill(.thinMaterial)

                RoundedRectangle(cornerRadius: barRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.48),
                                Color.white.opacity(0.12),
                                Color.black.opacity(0.05),
                                Color.black.opacity(0.10)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                // 顶部内高光边
                RoundedRectangle(cornerRadius: barRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.80),
                                Color.white.opacity(0.50),
                                .clear
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1.0
                    )
                    .mask(
                        VStack(spacing: 0) { Rectangle() }
                            .frame(maxHeight: barRadius * 0.65)
                            .frame(maxHeight: .infinity, alignment: .top)
                    )

                // 底部内阴影
                RoundedRectangle(cornerRadius: barRadius, style: .continuous)
                    .strokeBorder(Color.black.opacity(0.18), lineWidth: 0.8)
                    .offset(y: 0.5)
                    .mask(
                        VStack(spacing: 0) { Spacer(); Rectangle() }
                            .frame(maxHeight: barRadius * 0.5)
                            .frame(maxHeight: .infinity, alignment: .bottom)
                    )
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: barRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.20), lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(0.16), radius: 8, x: 0, y: 4)
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }

    private var divider: some View {
        ZStack {
            Rectangle()
                .fill(Color.black.opacity(0.18))
                .frame(width: 1, height: barHeight * 0.40)
                .offset(x: -0.5)
            Rectangle()
                .fill(Color.white.opacity(0.22))
                .frame(width: 1, height: barHeight * 0.40)
                .offset(x: 0.5)
        }
        .padding(.horizontal, 9 * scale)
    }

    @ViewBuilder
    private func part(symbol: String, value: UInt64, color: Color) -> some View {
        HStack(spacing: innerGap) {
            // 玻璃凸起箭头按钮
            ZStack {
                // 1. 底部接触阴影（椭圆，短模糊，模拟按钮压在面板上）
                Ellipse()
                    .fill(Color.black.opacity(0.22))
                    .frame(width: arrowCircleSize * 0.75,
                           height: arrowCircleSize * 0.12)
                    .offset(y: arrowCircleSize * 0.48)
                    .blur(radius: 0.8)

                // 2. 主底色：同色径向渐变（中心浅边缘深，球面感）
                Circle()
                    .fill(
                        RadialGradient(
                            gradient: Gradient(stops: [
                                .init(color: color.opacity(0.60), location: 0.0),
                                .init(color: color.opacity(0.38), location: 0.55),
                                .init(color: color.opacity(0.22), location: 1.0)
                            ]),
                            center: UnitPoint(x: 0.5, y: 0.35),
                            startRadius: 0,
                            endRadius: arrowCircleSize * 0.5
                        )
                    )

                // 3. 毛玻璃层（透出底色的同时有材质感）
                Circle()
                    .fill(.ultraThinMaterial)
                    .opacity(0.45)

                // 4. 顶部高光：月牙形（左上方的一束高光，模拟球面受光）
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.55),
                                Color.white.opacity(0.15),
                                .clear
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: arrowCircleSize * 0.58,
                           height: arrowCircleSize * 0.32)
                    .offset(x: -arrowCircleSize * 0.06,
                            y: -arrowCircleSize * 0.22)
                    .blur(radius: 0.6)
                    .mask(Circle().padding(arrowCircleSize * 0.05))

                // 5. 上沿高光线（锐利的一条边，凸起的上边缘反光）
                Circle()
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.90),
                                Color.white.opacity(0.50),
                                .clear
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1.0
                    )
                    .mask(
                        VStack(spacing: 0) { Rectangle() }
                            .frame(maxHeight: arrowCircleSize * 0.38)
                            .frame(maxHeight: .infinity, alignment: .top)
                    )
                    .padding(0.3)

                // 6. 底部暗边（凸起下沿的投影）
                Circle()
                    .strokeBorder(Color.black.opacity(0.16), lineWidth: 0.6)
                    .offset(y: 0.4)
                    .mask(
                        VStack(spacing: 0) { Spacer(); Rectangle() }
                            .frame(maxHeight: arrowCircleSize * 0.30)
                            .frame(maxHeight: .infinity, alignment: .bottom)
                    )
                    .padding(0.3)

                // 7. 图标（纵向渐变 + 文字高光）
                Image(systemName: symbol)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                color.lighter(by: 0.25),
                                color,
                                color.darker(by: 0.12)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .font(.system(size: arrowFont, weight: .bold))
                    .shadow(color: Color.white.opacity(0.35), radius: 0.3, y: 0.3)
            }
            .frame(width: arrowCircleSize, height: arrowCircleSize)
            // 微弱外发光（贴近按钮，不扩散太远）
            .shadow(color: color.opacity(0.20), radius: 2.5, x: 0, y: 0)

            // 数值文字
            HStack(alignment: .lastTextBaseline, spacing: 1) {
                Text(valueNumber(Double(value)))
                    .font(.system(size: valueFont, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                Text(valueUnit(Double(value)))
                    .font(.system(size: unitFont, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity)
    }

    private func valueNumber(_ bytes: Double) -> String {
        if bytes < 1024 { return "\(Int(bytes))" }
        let k = bytes / 1024
        if k < 1024 { return String(format: "%.1f", k) }
        let m = k / 1024
        if m < 1024 { return String(format: "%.1f", m) }
        return String(format: "%.2f", m / 1024)
    }

    private func valueUnit(_ bytes: Double) -> String {
        if bytes < 1024 { return "B/s" }
        let k = bytes / 1024
        if k < 1024 { return "K/s" }
        let m = k / 1024
        if m < 1024 { return "M/s" }
        return "G/s"
    }
}

// MARK: - Color 亮度调整（基于 sRGB，兼容所有颜色空间）

private extension Color {
    func lighter(by amount: Double) -> Color {
        let ns = NSColor(self).usingColorSpace(.sRGB) ?? NSColor(self)
        let r = ns.redComponent
        let g = ns.greenComponent
        let b = ns.blueComponent
        let a = ns.alphaComponent
        return Color(red: Double(r + (1 - r) * CGFloat(amount)),
                     green: Double(g + (1 - g) * CGFloat(amount)),
                     blue: Double(b + (1 - b) * CGFloat(amount)),
                     opacity: Double(a))
    }

    func darker(by amount: Double) -> Color {
        let ns = NSColor(self).usingColorSpace(.sRGB) ?? NSColor(self)
        let r = ns.redComponent
        let g = ns.greenComponent
        let b = ns.blueComponent
        let a = ns.alphaComponent
        return Color(red: Double(r * (1 - CGFloat(amount))),
                     green: Double(g * (1 - CGFloat(amount))),
                     blue: Double(b * (1 - CGFloat(amount))),
                     opacity: Double(a))
    }
}
