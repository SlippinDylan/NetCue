//
//  AdaptiveButtonStyle.swift
//  NetCue
//
//  Created for macOS 15+ / macOS 26+ dual-version support.
//

import SwiftUI

// MARK: - View Extensions for Adaptive Button Styles

extension View {
    /// 应用自适应玻璃按钮样式
    ///
    /// ## 设计说明
    /// 根据系统版本自动选择合适的按钮样式：
    /// - macOS 26+: 使用原生 `.glass` 样式（Liquid Glass 设计语言）
    /// - macOS 15-25: 使用 `.bordered` 样式作为优雅降级
    ///
    /// ## 使用示例
    /// ```swift
    /// Button("操作") { action() }
    ///     .adaptiveGlassButtonStyle()
    /// ```
    @ViewBuilder
    func adaptiveGlassButtonStyle() -> some View {
        if #available(macOS 26, *) {
            self.buttonStyle(.glass)
        } else {
            self.buttonStyle(.bordered)
        }
    }

    /// 应用自适应强调玻璃按钮样式
    ///
    /// ## 设计说明
    /// 根据系统版本自动选择合适的强调按钮样式：
    /// - macOS 26+: 使用原生 `.glassProminent` 样式
    /// - macOS 15-25: 使用 `.borderedProminent` 样式作为优雅降级
    ///
    /// ## 使用示例
    /// ```swift
    /// Button("确认") { confirm() }
    ///     .adaptiveGlassProminentButtonStyle()
    /// ```
    @ViewBuilder
    func adaptiveGlassProminentButtonStyle() -> some View {
        if #available(macOS 26, *) {
            self.buttonStyle(.glassProminent)
        } else {
            self.buttonStyle(.borderedProminent)
        }
    }
}
