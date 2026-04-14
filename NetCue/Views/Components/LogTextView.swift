//
//  LogTextView.swift
//  NetCue
//
//  Created by SlippinDylan on 2025/12/31.
//

import SwiftUI
import AppKit

/// NSTextView 包装器（用于高性能日志显示）
///
/// 特性：
/// - 虚拟化渲染（只渲染可见行）
/// - 文本选择和复制
/// - 自动滚动到底部
/// - 只读模式
/// - 支持深色模式
struct LogTextView: NSViewRepresentable {
    // MARK: - Properties

    /// 日志条目数组
    let entries: [LogEntry]

    /// 是否自动滚动到底部
    let autoScroll: Bool

    // MARK: - NSViewRepresentable

    func makeNSView(context: Context) -> NSScrollView {
        // 创建 NSTextView
        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.allowsUndo = false
        textView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.textColor = .labelColor
        textView.backgroundColor = .textBackgroundColor
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true

        // 创建 NSScrollView
        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true

        // 强制 Overlay 模式（与 NetCueScrollView 一致）
        scrollView.scrollerStyle = .overlay
        scrollView.autohidesScrollers = true

        // 添加圆角
        scrollView.wantsLayer = true
        scrollView.layer?.cornerRadius = 8
        scrollView.layer?.masksToBounds = true

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else {
            return
        }

        // 构建富文本内容
        let attributedString = NSMutableAttributedString()

        for (index, entry) in entries.enumerated() {
            attributedString.append(entry.attributedString)

            // 添加换行符（最后一行除外）
            if index < entries.count - 1 {
                attributedString.append(NSAttributedString(string: "\n"))
            }
        }

        // 更新文本
        textView.textStorage?.setAttributedString(attributedString)

        // 自动滚动到底部
        if autoScroll {
            textView.scrollToEndOfDocument(nil)
        }
    }
}

// MARK: - Coordinator

extension LogTextView {
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator: NSObject {
        // 可以在这里添加事件处理（如点击、右键菜单等）
    }
}
