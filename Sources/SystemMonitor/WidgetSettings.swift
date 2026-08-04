import SwiftUI
import Combine

/// 组件缩放设置：三档预设 —— 小(50%) / 中(75%) / 大(100%)，默认 100%。
/// 由右键菜单「组件大小」下拉切换。
final class WidgetSettings: ObservableObject {
    static let small: Double = 0.5
    static let medium: Double = 0.75
    static let large: Double = 1.0

    @Published var scale: Double = large
}