import SwiftUI

/// 网络实时速率：↑上传 / ↓下载，单位自适应
/// 设计要点：
/// 1. 不显示「上传/下载」中文，仅靠箭头方向区分；
/// 2. 数字区域使用固定宽度 + monospacedDigit + 左对齐，数字变化时不再左右抖动；
/// 3. 箭头固定在数字左侧，不会随数值长度变化而位移；
/// 4. 上传/下载两部分紧挨排列；整行宽度与上方三个圆环行（188×scale）一致并居中，
///    因此网络标志与圆环左右对齐。
struct NetworkView: View {
    let up: UInt64     // bytes/s
    let down: UInt64   // bytes/s
    var scale: CGFloat = 1.0

    /// 圆环行宽度：3 个 52 + 2 个 16 间距 = 188
    private var ringRowWidth: CGFloat { 188 * scale }
    /// 两部分之间的间隔
    private var gap: CGFloat { 10 * scale }
    /// 数值区宽度：使两段+间隔恰好等于圆环行宽，左对齐避免数值跳动
    private var valueWidth: CGFloat {
        (ringRowWidth - gap) / 2 - 16 * scale   // 16 = 箭头宽(12) + 箭头与数字间距(4)
    }

    var body: some View {
        HStack(spacing: gap) {
            part(symbol: "arrow.up", value: up, color: .green)
            part(symbol: "arrow.down", value: down, color: .blue)
        }
        .frame(width: ringRowWidth)
    }

    @ViewBuilder
    private func part(symbol: String, value: UInt64, color: Color) -> some View {
        HStack(spacing: 4 * scale) {
            Image(systemName: symbol)
                .foregroundStyle(color)
                .font(.system(size: 11 * scale, weight: .semibold))
                .frame(width: 12 * scale)
            Text(format(Double(value)))
                .font(.system(size: 12 * scale, weight: .medium, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .frame(width: valueWidth, alignment: .leading)
        }
    }

    private func format(_ bytes: Double) -> String {
        if bytes < 1024 { return "\(Int(bytes)) B/s" }
        let k = bytes / 1024
        if k < 1024 { return String(format: "%.1f KB/s", k) }
        let m = k / 1024
        if m < 1024 { return String(format: "%.1f MB/s", m) }
        return String(format: "%.2f GB/s", m / 1024)
    }
}