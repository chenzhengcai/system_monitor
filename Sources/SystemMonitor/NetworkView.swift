import SwiftUI

/// 网络实时速率：上传 / 下载，封装在胶囊毛玻璃条内。
struct NetworkView: View {
    let up: UInt64     // bytes/s
    let down: UInt64   // bytes/s
    var scale: CGFloat = 1.0

    private var barHeight: CGFloat { 54 * scale }
    private var barRadius: CGFloat { barHeight * 0.5 }
    private var arrowCircleSize: CGFloat { 30 * scale }
    private var arrowFont: CGFloat { 14 * scale }
    private var valueFont: CGFloat { 17 * scale }
    private var unitFont: CGFloat { 12 * scale }
    private var hPadding: CGFloat { 16 * scale }
    private var innerGap: CGFloat { 9 * scale }

    var body: some View {
        HStack(spacing: 0) {
            part(symbol: "arrow.up", value: up, color: Color.green)
            Rectangle()
                .fill(Color.primary.opacity(0.12))
                .frame(width: 1, height: barHeight * 0.34)
                .padding(.horizontal, 10 * scale)
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
                                Color.white.opacity(0.45),
                                Color.white.opacity(0.10),
                                Color.black.opacity(0.03)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                RoundedRectangle(cornerRadius: barRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.75),
                                Color.white.opacity(0.28),
                                .clear
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
                    .mask(
                        VStack(spacing: 0) { Rectangle() }
                            .frame(maxHeight: barRadius * 0.62)
                            .frame(maxHeight: .infinity, alignment: .top)
                    )
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: barRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.20), lineWidth: 0.8)
        )
        .shadow(color: Color.black.opacity(0.14), radius: 10, x: 0, y: 5)
        .shadow(color: Color.black.opacity(0.05), radius: 3, x: 0, y: 1)
    }

    @ViewBuilder
    private func part(symbol: String, value: UInt64, color: Color) -> some View {
        HStack(spacing: innerGap) {
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            gradient: Gradient(colors: [
                                color.opacity(0.34),
                                color.opacity(0.18)
                            ]),
                            center: .center,
                            startRadius: 0,
                            endRadius: arrowCircleSize * 0.5
                        )
                    )
                Circle()
                    .fill(.ultraThinMaterial)
                    .opacity(0.55)
                Circle()
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.6),
                                .clear
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 0.8
                    )
                    .mask(
                        VStack(spacing: 0) { Rectangle() }
                            .frame(maxHeight: arrowCircleSize * 0.35)
                            .frame(maxHeight: .infinity, alignment: .top)
                    )
                Image(systemName: symbol)
                    .foregroundStyle(color)
                    .font(.system(size: arrowFont, weight: .bold))
            }
            .frame(width: arrowCircleSize, height: arrowCircleSize)

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
