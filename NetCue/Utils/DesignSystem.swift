//
//  DesignSystem.swift
//  NetCue
//
//  Created by SlippinDylan on 2025/12/31.
//  统一的设计规范，符合 macOS HIG
//

import SwiftUI

/// 设计系统：统一的视觉规范
enum DesignSystem {

    // MARK: - 圆角半径

    /// 圆角半径规范
    enum CornerRadius {
        /// 小圆角 - 用于按钮、标签等小元素
        static let small: CGFloat = 4

        /// 中等圆角 - 用于卡片、输入框等
        static let medium: CGFloat = 6

        /// 大圆角 - 用于模态框、大卡片等
        static let large: CGFloat = 12
    }

    // MARK: - 间距

    /// 间距规范（基于 8pt 网格系统）
    enum Spacing {
        /// 极小间距 - 4pt
        static let extraSmall: CGFloat = 4

        /// 小间距 - 8pt
        static let small: CGFloat = 8

        /// 中等间距 - 12pt
        static let medium: CGFloat = 12

        /// 标准间距 - 16pt
        static let standard: CGFloat = 16

        /// 大间距 - 24pt
        static let large: CGFloat = 24

        /// 超大间距 - 32pt
        static let extraLarge: CGFloat = 32
    }

    // MARK: - 图标尺寸

    /// 图标尺寸规范
    enum IconScale {
        /// 小图标 - 用于内联文本中
        static let small = Image.Scale.small

        /// 中等图标 - 标准UI元素（推荐）
        static let medium = Image.Scale.medium

        /// 大图标 - 用于重要操作
        static let large = Image.Scale.large
    }

    // MARK: - 字体大小

    /// 字体大小规范
    enum FontSize {
        /// 标题 - 16pt
        static let title: CGFloat = 16

        /// 正文 - 13pt（macOS 标准）
        static let body: CGFloat = 13

        /// 辅助文本 - 11pt
        static let caption: CGFloat = 11
    }

    // MARK: - Padding

    /// 内边距规范
    enum Padding {
        /// 卡片内边距 - 16pt
        static let card: CGFloat = 16

        /// 容器内边距 - 20pt
        static let container: CGFloat = 20
    }
}

// MARK: - View Extension

extension View {
    /// 应用标准卡片圆角
    func cardCornerRadius() -> some View {
        self.clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
    }

    /// 应用标准卡片内边距
    func cardPadding() -> some View {
        self.padding(DesignSystem.Padding.card)
    }
}
