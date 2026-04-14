//
//  IPQualityNetworkToolCard.swift
//  NetCue
//
//  Created by SlippinDylan on 2026/01/07.
//  网络工具 - IP质量卡片主容器
//

import SwiftUI

/// 网络工具 - IP质量卡片（完整版）
///
/// ## 架构说明
/// - 业务层：复用IPQualityViewModel.shared（与原IP质量tab共享状态）
/// - UI层：全新实现，适配GroupBox卡片环境
/// - 三态切换：idle（检测前）→ detecting（检测中）→ completed（检测后）
///
/// ## 设计差异
/// - 原IP质量tab（IPQualityView）：
///   - 全屏展示，独立ScrollView
///   - idle/detecting状态垂直居中（Spacer包裹）
///   - completed状态直接VStack堆叠所有卡片
///
/// - 网络工具卡片（本组件）：
///   - 嵌套在NetworkToolsView的ScrollView中
///   - 外层有GroupBox包裹
///   - 不使用ScrollView（避免嵌套死锁）
///   - completed状态完整展示（与原tab一致）
///
/// ## 状态同步
/// - 两套UI共用IPQualityViewModel.shared
/// - 在IP质量tab检测完成后，网络工具卡片自动显示结果
struct IPQualityNetworkToolCard: View {
    // MARK: - State

    @State private var viewModel = IPQualityViewModel.shared

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            switch viewModel.detectionState {
            case .idle:
                IPQualityCardIdleView(onStart: startDetection)

            case .detecting:
                IPQualityCardDetectingView(
                    progress: viewModel.currentProgress,
                    currentTask: viewModel.currentTaskDescription
                )

            case .completed:
                if let result = viewModel.result {
                    IPQualityCardCompletedView(
                        result: result,
                        onRetest: resetDetection
                    )
                }
            }
        }
        .frame(maxWidth: .infinity)
        .animation(.easeInOut(duration: 0.3), value: viewModel.detectionState)
        .onDisappear {
            viewModel.cancelDetection()
        }
        .onChange(of: viewModel.isLoading) { oldValue, newValue in
            if newValue {
                // 检测开始：切换到detecting状态
                viewModel.detectionState = .detecting
            } else if viewModel.result != nil {
                // 检测完成：切换到completed状态
                Task { @MainActor in
                    withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                        viewModel.detectionState = .completed
                    }
                }
            }
        }
    }

    // MARK: - Private Methods

    /// 开始检测
    private func startDetection() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
            viewModel.detectionState = .detecting
        }
        viewModel.startDetection()
    }

    /// 重置检测状态
    private func resetDetection() {
        // 异步调度动画，避免阻塞主线程
        Task { @MainActor in
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                viewModel.detectionState = .idle
                viewModel.result = nil
                viewModel.errorMessage = nil
            }
        }
    }
}

// MARK: - Preview

#Preview {
    GroupBox {
        IPQualityNetworkToolCard()
            .padding()
    } label: {
        Text("IP 质量")
    }
    .frame(width: 800)
}
