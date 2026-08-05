import SwiftUI
import Combine

/// 组件设置：三档缩放 + 四档背景透明度，持久化到 UserDefaults。
final class WidgetSettings: ObservableObject {
    // 缩放档位
    static let small: Double = 0.5
    static let medium: Double = 0.75
    static let large: Double = 1.0

    // 透明度档位（不透明度，越大越不透明）
    static let opacity25: Double = 0.25
    static let opacity50: Double = 0.50
    static let opacity75: Double = 0.75
    static let opacity100: Double = 1.00

    private let defaults = UserDefaults.standard
    private let scaleKey = "WidgetScale"
    private let opacityKey = "WidgetOpacity"

    @Published var scale: Double {
        didSet { defaults.set(scale, forKey: scaleKey) }
    }

    @Published var opacity: Double {
        didSet { defaults.set(opacity, forKey: opacityKey) }
    }

    init() {
        // 缩放
        if defaults.object(forKey: scaleKey) != nil {
            self.scale = defaults.double(forKey: scaleKey)
        } else {
            self.scale = Self.large
        }
        // 透明度
        if defaults.object(forKey: opacityKey) != nil {
            self.opacity = defaults.double(forKey: opacityKey)
        } else {
            self.opacity = Self.opacity75
        }
    }
}
