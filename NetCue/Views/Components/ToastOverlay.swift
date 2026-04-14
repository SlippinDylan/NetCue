//
//  ToastOverlay.swift
//  NetCue
//
//  Created by Claude on 2026/01/09.
//
//  ## 设计说明
//  - 全局 Toast 覆盖层视图
//  - 符合 macOS 26 Liquid Glass 设计语言
//  - 水平居中，顶部对齐显示
//  - 优雅的进入/退出动画
//
//  ## 架构参考
//  - 复用 QuitConfirmationOverlay 的设计模式
//  - 使用 .ultraThinMaterial 毛玻璃效果
//

import SwiftUI

/// 全局 Toast 覆盖层
///
/// ## 设计规范
/// - 符合 macOS 26 Liquid Glass 设计语言
/// - 使用 `.ultraThinMaterial` 毛玻璃效果
/// - 水平居中，顶部对齐显示（在 Toolbar 下方）
/// - 优雅的进入/退出动画
///
/// ## 使用方式
/// ```swift
/// ContentView()
///     .overlay(alignment: .top) {
///         ToastOverlay()
///             .padding(.top, 8)
///     }
/// ```
struct ToastOverlay: View {

    // MARK: - State

    /// Toast 管理器
    @State private var toastManager = ToastManager.shared

    // MARK: - Body

    var body: some View {
        ZStack {
            if let toast = toastManager.currentToast {
                toastCard(for: toast)
                    .transition(.toastTransition)
                    .id(toast.id) // 确保每个 Toast 都是独立的视图
            }
        }
        .animation(.spring(duration: 0.35, bounce: 0.2), value: toastManager.currentToast?.id)
    }

    // MARK: - Toast Card

    /// Toast 卡片视图
    ///
    /// - Parameter toast: Toast 数据
    /// - Returns: 卡片视图
    private func toastCard(for toast: ToastItem) -> some View {
        HStack(spacing: 10) {
            // 图标
            Image(systemName: toast.type.icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(toast.type.color)

            // 消息文本
            Text(toast.message)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background {
            toastBackground
        }
        .overlay {
            toastBorder
        }
        .onTapGesture {
            // 点击可提前关闭
            toastManager.dismiss()
        }
    }

    // MARK: - Background & Border

    /// 毛玻璃背景
    private var toastBackground: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(.ultraThinMaterial)
            .shadow(color: .black.opacity(0.12), radius: 16, x: 0, y: 6)
            .shadow(color: .black.opacity(0.04), radius: 1, x: 0, y: 1)
    }

    /// 边框
    private var toastBorder: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(.white.opacity(0.15), lineWidth: 0.5)
    }
}

// MARK: - Custom Transition

private extension AnyTransition {
    /// Toast 专用过渡动画
    ///
    /// 组合效果：
    /// - 进入：从上方滑入 + 淡入 + 轻微缩放
    /// - 退出：向上滑出 + 淡出
    static var toastTransition: AnyTransition {
        .asymmetric(
            insertion: .move(edge: .top)
                .combined(with: .opacity)
                .combined(with: .scale(scale: 0.95, anchor: .top)),
            removal: .move(edge: .top)
                .combined(with: .opacity)
        )
    }
}

// MARK: - Preview

#Preview("Success Toast") {
    ZStack {
        Color.gray.opacity(0.2)
            .ignoresSafeArea()

        VStack {
            ToastOverlay()
                .padding(.top, 20)

            Spacer()
        }
    }
    .frame(width: 500, height: 300)
    .onAppear {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.5))
            Toast.success("内核替换成功")
        }
    }
}

#Preview("Error Toast") {
    ZStack {
        Color.gray.opacity(0.2)
            .ignoresSafeArea()

        VStack {
            ToastOverlay()
                .padding(.top, 20)

            Spacer()
        }
    }
    .frame(width: 500, height: 300)
    .onAppear {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.5))
            Toast.error("操作失败：权限不足")
        }
    }
}

#Preview("Multiple Toasts") {
    ZStack {
        Color.gray.opacity(0.2)
            .ignoresSafeArea()

        VStack {
            ToastOverlay()
                .padding(.top, 20)

            Spacer()

            Button("添加 Toast") {
                let messages = ["配置已保存", "内核替换成功", "图标备份完成"]
                let types: [ToastType] = [.success, .info, .success]
                let index = Int.random(in: 0..<messages.count)
                ToastManager.shared.show(messages[index], type: types[index], duration: 2.0)
            }
            .padding(.bottom, 20)
        }
    }
    .frame(width: 500, height: 300)
}
