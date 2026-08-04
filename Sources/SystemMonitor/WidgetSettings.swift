import SwiftUI
import Combine

/// 组件缩放设置：三档预设 —— 小(50%) / 中(75%) / 大(100%)，默认 100%。
/// 由右键菜单「组件大小」下拉切换，并持久化到 UserDefaults（重启后保留）。
final class WidgetSettings: ObservableObject {
    static let small: Double = 0.5
    static let medium: Double = 0.75
    static let large: Double = 1.0

    private let defaults = UserDefaults.standard
    private let scaleKey = "WidgetScale"

    @Published var scale: Double {
        didSet { defaults.set(scale, forKey: scaleKey) }
    }

    init() {
        // 仅当键存在时才恢复，避免把「从未设置」与某个真实值混淆
        if defaults.object(forKey: scaleKey) != nil {
            self.scale = defaults.double(forKey: scaleKey)
        } else {
            self.scale = Self.large
        }
    }
}
