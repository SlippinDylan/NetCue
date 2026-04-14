//
//  NetworkToolsView.swift
//  NetCue
//
//  Created by SlippinDylan on 2026/01/04.
//

import SwiftUI

/// 网络工具视图
///
/// ## 功能
/// - DNS 深度清理：一键执行网络缓存清理、接口重置等维护操作
/// - IP 查询：查询 IP 地址的详细信息
struct NetworkToolsView: View {
    @State private var viewModel = NetworkToolsViewModel()
    @State private var ipQueryViewModel = IPQueryViewModel.shared
    @State private var ipAddress = ""

    var body: some View {
        NetCueScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // DNS 深度清理卡片
                GroupBox {
                    HStack(spacing: 16) {
                        // 左侧说明
                        VStack(alignment: .leading, spacing: 12) {
                            // 说明文本
                            Text("清理 DNS 缓存、重置网络接口、清除 ARP 缓存、重置 WiFi、清理浏览器缓存")
                                .font(.body)
                                .foregroundStyle(.secondary)

                            // 警告文本
                            HStack(spacing: 4) {
                                Image(systemName: "exclamationmark.circle.fill")
                                    .foregroundStyle(.orange)
                                Text("执行时将中断网络连接 2-5 秒")
                                    .font(.callout)
                                    .foregroundStyle(.orange)
                            }

                            // 上次执行时间
                            if let lastTime = viewModel.lastExecutionTime {
                                HStack {
                                    Image(systemName: "clock.fill")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text("上次执行：\(lastTime, style: .date) \(lastTime, style: .time)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        // 右侧按钮（垂直居中）
                        Button {
                            viewModel.showConfirmation = true
                        } label: {
                            if viewModel.isExecuting {
                                HStack(spacing: 6) {
                                    ProgressView()
                                        .controlSize(.small)
                                    Text("执行中...")
                                }
                            } else {
                                Text("执行深度清理")
                            }
                        }
                        .adaptiveGlassProminentButtonStyle()
                        .controlSize(.large)
                        .disabled(viewModel.isExecuting)
                    }
                    .padding()
                } label: {
                    SectionHeader(title: "DNS 深度清理", icon: "wrench.and.screwdriver.fill", iconColor: .blue)
                }

                // IP 查询卡片（包含输入框和结果）
                GroupBox {
                    VStack(spacing: 12) {
                        // 输入框和查询按钮
                        HStack {
                            // 输入框（带清空按钮）
                            ZStack(alignment: .trailing) {
                                TextField("输入 IP 地址", text: $ipAddress)
                                    .textFieldStyle(.plain)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .padding(.trailing, ipAddress.isEmpty ? 0 : 28)  // 为清空按钮留空间
                                    .background(Color(nsColor: .textBackgroundColor))
                                    .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium)
                                            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                                    )
                                    .disabled(ipQueryViewModel.isLoading)

                                // 清空按钮（仅在有内容时显示）
                                if !ipAddress.isEmpty {
                                    Button(action: {
                                        ipAddress = ""
                                        ipQueryViewModel.reset()
                                    }) {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundStyle(.secondary)
                                            .imageScale(.medium)
                                    }
                                    .buttonStyle(.plain)
                                    .padding(.trailing, 8)
                                    .help("清空")
                                }
                            }

                            Button {
                                Task {
                                    await ipQueryViewModel.queryIP(ipAddress)
                                }
                            } label: {
                                if ipQueryViewModel.isLoading {
                                    HStack(spacing: 6) {
                                        ProgressView()
                                            .controlSize(.small)
                                        Text("查询中...")
                                    }
                                } else {
                                    Text("查询")
                                }
                            }
                            .adaptiveGlassProminentButtonStyle()
                            .disabled(ipQueryViewModel.isLoading || ipAddress.trimmingCharacters(in: .whitespaces).isEmpty)
                        }

                        // 查询结果（仅在有结果时显示）
                        if let result = ipQueryViewModel.result {
                            Divider()

                            VStack(alignment: .leading, spacing: 12) {
                                InfoRow(label: "自治系统号", value: result.asn)
                                InfoRow(label: "IP类型", value: result.ipType)
                                InfoRow(label: "组织", value: result.organization)
                                InfoRow(label: "时区", value: result.timezone)
                                InfoRow(label: "使用地", value: result.location.usageLocation)
                                InfoRow(label: "注册地", value: result.registrationCountry)
                                InfoRow(label: "城市", value: result.location.cityDisplay)
                                InfoRow(label: "坐标", value: result.coordinates.displayString)

                                Divider()

                                // 地图
                                MapView(latitude: result.latitude, longitude: result.longitude)
                                    .frame(height: 180)
                                    .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large))
                            }
                        }
                    }
                    .padding()
                } label: {
                    SectionHeader(title: "IP 查询", icon: "network", iconColor: .purple)
                }

                // DNS 测试卡片
                GroupBox {
                    DNSTestCardView()
                        .padding()
                } label: {
                    SectionHeader(title: "DNS 测试", icon: "network.badge.shield.half.filled", iconColor: .green)
                }

                // IP 质量卡片
                GroupBox {
                    IPQualityNetworkToolCard()
                        .padding()
                } label: {
                    SectionHeader(title: "IP 质量", icon: "shield.checkered", iconColor: .orange)
                }
            }
            .padding(.horizontal, DesignSystem.Spacing.standard)
            .padding(.top, DesignSystem.Spacing.standard)
        }
        // 确认弹窗（需要用户操作）
        .alert("确认执行深度清理？", isPresented: $viewModel.showConfirmation) {
            Button("取消", role: .cancel) { }
            Button("执行") {
                Task {
                    await viewModel.executeDeepClean()
                }
            }
        } message: {
            Text("""
            此操作将执行：
            • 清理 DNS 缓存
            • 重置网络接口
            • 清除 ARP 缓存
            • 重置 WiFi
            • 清理浏览器缓存（Chrome、Firefox）
            • 清理系统缓存

            ⚠️ 将中断网络连接 2-5 秒
            """)
        }
    }
}

// MARK: - ViewModel

/// 网络工具 ViewModel
@MainActor
@Observable
final class NetworkToolsViewModel {
    // MARK: - State

    /// 深度清理执行中
    var isExecuting = false

    /// 显示确认弹窗
    var showConfirmation = false

    /// 上次执行时间
    var lastExecutionTime: Date?

    // MARK: - Dependencies

    private let service = NetworkMaintenanceService()

    // MARK: - Public Methods

    /// 执行深度清理
    func executeDeepClean() async {
        isExecuting = true
        defer { isExecuting = false }

        do {
            try await service.deepClean()
            lastExecutionTime = Date()
            Toast.success("深度清理完成")
            AppLogger.info("✅ 深度清理成功")
        } catch {
            Toast.error(error.localizedDescription)
            AppLogger.error("深度清理失败", error: error)
        }
    }
}
