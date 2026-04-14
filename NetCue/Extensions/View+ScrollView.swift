//
//  View+ScrollView.swift
//  NetCue
//
//  Created by SlippinDylan on 2026/01/07.
//  原生 AppKit 滚动视图 - 强制 Overlay 模式
//

import SwiftUI
import AppKit

/// 原生 AppKit 滚动视图，强制使用 Overlay 模式滚动条
///
/// ## 设计说明
/// - **纯原生 AppKit 实现**：直接使用 NSScrollView，无第三方依赖
/// - **强制 Overlay 模式**：通过 `scrollerStyle = .overlay` 确保滚动条浮在内容上方
/// - **零布局跳动**：滚动条永不挤压内容，无论系统偏好设置如何
///
/// ## 技术原理
/// SwiftUI 的 ScrollView 在 macOS 上无法可靠地控制底层 NSScrollView 的 scrollerStyle。
/// 系统偏好设置中的"始终显示滚动条"会覆盖 SwiftUI 的设置，导致 Legacy 模式挤压内容。
///
/// 本方案通过 NSViewRepresentable 直接创建 NSScrollView，设置：
/// - `scrollerStyle = .overlay`：强制 Overlay 模式
/// - `autohidesScrollers = true`：自动隐藏滚动条
/// - `drawsBackground = false`：透明背景，融入 SwiftUI 视图层级
///
/// ## 参考实现
/// - GitHub CopilotForXcode: OverlayScrollView.swift
/// - Ghostty Terminal: SurfaceScrollView.swift (Mitchell Hashimoto)
///
/// ## 使用方式
/// ```swift
/// NetCueScrollView {
///     VStack(alignment: .leading, spacing: 24) {
///         // 内容
///     }
///     .padding()
/// }
/// ```
struct NetCueScrollView<Content: View>: NSViewRepresentable {
    private let showsVerticalScroller: Bool
    private let showsHorizontalScroller: Bool
    private let content: Content

    init(
        showsVerticalScroller: Bool = true,
        showsHorizontalScroller: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.showsVerticalScroller = showsVerticalScroller
        self.showsHorizontalScroller = showsHorizontalScroller
        self.content = content()
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()

        // 核心设置：强制 Overlay 模式
        scrollView.scrollerStyle = .overlay
        scrollView.autohidesScrollers = true

        // 滚动条配置
        scrollView.hasVerticalScroller = showsVerticalScroller
        scrollView.hasHorizontalScroller = showsHorizontalScroller

        // 视觉配置
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder

        // 滚动行为
        scrollView.verticalScrollElasticity = .automatic
        scrollView.horizontalScrollElasticity = .automatic
        scrollView.usesPredominantAxisScrolling = false

        // 创建 SwiftUI 内容的 hosting view
        let hostingView = NSHostingView(rootView: content)
        hostingView.translatesAutoresizingMaskIntoConstraints = false

        // 设置为 documentView
        scrollView.documentView = hostingView

        // 约束：让内容填充滚动区域
        if let documentView = scrollView.documentView {
            NSLayoutConstraint.activate([
                documentView.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
                documentView.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor),
                documentView.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor)
            ])
        }

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        // 更新 SwiftUI 内容
        if let hostingView = nsView.documentView as? NSHostingView<Content> {
            hostingView.rootView = content
        }
    }
}
