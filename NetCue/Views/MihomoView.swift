//
//  MihomoView.swift
//  NetCue
//
//  Created by SlippinDylan on 2025/12/30.
//

import SwiftUI

struct MihomoView: View {
    /// 从 NetCueApp 注入的视图模型（确保切换 Tab 时状态不丢失）
    @Environment(MihomoViewModel.self) private var viewModel

    var body: some View {
        NetCueScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // 内核状态卡片
                StatusCard()

                // 内核替换卡片
                KernelManagementCard()

                // 配置卡片
                ConfigurationCard()
            }
            .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - 状态卡片

struct StatusCard: View {
    @Environment(MihomoViewModel.self) private var viewModel

    private var hostAppTitle: String {
        viewModel.config.appDisplayName.isEmpty ? "关联应用" : viewModel.config.appDisplayName
    }

    private var hostAppStatusText: String {
        switch viewModel.hostAppInstallStatus {
        case .notConfigured:
            return "未设置，请前往设置页面关联"
        case .notInstalled:
            return "未检测到该应用"
        case .installed:
            return "已安装"
        case .unknown:
            return "检测中"
        }
    }

    private var isRunningStatusText: String {
        switch viewModel.hostAppInstallStatus {
        case .notConfigured:
            return "未关联"
        case .unknown:
            return "检测中"
        case .notInstalled, .installed:
            return viewModel.isHostAppRunning ? "运行中" : "未运行"
        }
    }

    /// 未关联应用、或状态尚未刷新完成时都无法判断运行状态，
    /// 不应显示为"正常"的绿色对勾（否则会在首次加载的 0.3 秒窗口内误导用户）
    private var isRunningStatusPositive: Bool {
        switch viewModel.hostAppInstallStatus {
        case .notConfigured, .unknown:
            return false
        case .notInstalled, .installed:
            return !viewModel.isHostAppRunning
        }
    }

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                // 关联应用安装状态
                StatusRow(
                    title: hostAppTitle,
                    status: hostAppStatusText,
                    isPositive: viewModel.hostAppInstallStatus == .installed
                )

                Divider()

                // 关联应用运行状态
                StatusRow(
                    title: "运行状态",
                    status: isRunningStatusText,
                    isPositive: isRunningStatusPositive
                )

                Divider()

                // 内核状态
                if let kernelStatus = viewModel.kernelStatus {
                    StatusRow(
                        title: "内核文件",
                        status: kernelStatus.statusDescription,
                        isPositive: kernelStatus.kernelExists
                    )
                }
            }
            .padding()
        } label: {
            SectionHeader(title: "内核状态", icon: "info.circle.fill", iconColor: .blue)
        }
    }
}

struct StatusRow: View {
    let title: String
    let status: String
    let isPositive: Bool

    var body: some View {
        HStack {
            Text(title)
                .font(.callout)
                .foregroundStyle(.secondary)

            Spacer()

            HStack(spacing: 4) {
                Image(systemName: isPositive ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(isPositive ? .green : .orange)
                    .imageScale(DesignSystem.IconScale.small)

                Text(status)
                    .font(.callout)
                    .foregroundStyle(isPositive ? .green : .orange)
            }
        }
    }
}

// MARK: - 内核管理卡片

struct KernelManagementCard: View {
    @Environment(MihomoViewModel.self) private var viewModel

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 16) {
                // 操作按钮（始终显示）
                HStack(spacing: 12) {
                    Button("备份内核") {
                        viewModel.backupKernel()
                    }
                    .adaptiveGlassButtonStyle()
                    .disabled(
                        viewModel.isLoading ||
                        viewModel.isDownloading ||
                        viewModel.config.kernelPath.isEmpty ||
                        viewModel.kernelStatus?.backupExists == true
                    )

                    Button("替换内核") {
                        viewModel.replaceKernel()
                    }
                    .adaptiveGlassProminentButtonStyle()
                    .disabled(
                        viewModel.isLoading ||
                        viewModel.isDownloading ||
                        viewModel.config.kernelPath.isEmpty
                    )

                    Button("恢复内核") {
                        viewModel.restoreKernel()
                    }
                    .adaptiveGlassButtonStyle()
                    .disabled(
                        viewModel.isLoading ||
                        viewModel.isDownloading ||
                        viewModel.kernelStatus?.backupExists != true
                    )

                    Spacer()
                }

                // 下载进度区域（仅在下载时显示）
                if viewModel.isDownloading {
                    Divider()

                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("下载内核")
                                    .font(.callout)
                                    .fontWeight(.medium)
                                Text("从 GitHub 自动下载最新预发布内核")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            HStack(spacing: 6) {
                                ProgressView()
                                    .controlSize(.small)
                                Text(viewModel.downloadStatusText)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        // 下载进度条
                        if viewModel.downloadProgress > 0 {
                            ProgressView(value: viewModel.downloadProgress)
                                .progressViewStyle(.linear)
                        }
                    }
                }
            }
            .padding()
        } label: {
            SectionHeader(
                title: "内核替换",
                icon: "cube.fill",
                iconColor: .purple,
                description: "备份并替换 Mihomo 内核，替换后可能需要重启关联应用"
            )
        }
    }
}

// MARK: - 配置卡片

struct ConfigurationCard: View {
    @Environment(MihomoViewModel.self) private var viewModel

    var body: some View {
        @Bindable var viewModel = viewModel
        GroupBox {
            VStack(alignment: .leading, spacing: 16) {
                // 顶部：说明文字 + 按钮
                HStack(alignment: .top, spacing: 16) {
                    // 左侧说明
                    VStack(alignment: .leading, spacing: 8) {
                        Text("自定义内核路径和下载源，配置将保存在本地。")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        // 配置状态
                        HStack(spacing: 12) {
                            HStack(spacing: 4) {
                                Image(systemName: viewModel.config.isKernelConfigDefault ? "arrow.counterclockwise.circle" : "pencil.circle.fill")
                                    .foregroundStyle(viewModel.config.isKernelConfigDefault ? Color.secondary : Color.blue)
                                    .font(.system(size: 12))
                                Text(viewModel.config.isKernelConfigDefault ? "使用默认配置" : "已自定义配置")
                                    .font(.caption)
                                    .foregroundStyle(viewModel.config.isKernelConfigDefault ? Color.secondary : Color.blue)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    // 右侧按钮
                    HStack(spacing: 8) {
                        Button("重置配置") {
                            viewModel.resetConfig()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                        .disabled(viewModel.isLoading || viewModel.isDownloading)

                        Button("保存配置") {
                            viewModel.saveConfig()
                        }
                        .adaptiveGlassProminentButtonStyle()
                        .disabled(viewModel.isLoading || viewModel.isDownloading)
                    }
                }

                Divider()

                // 内核路径（点击拉起访达选择文件）
                VStack(alignment: .leading, spacing: 8) {
                    Text("内核文件路径")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Button {
                        viewModel.selectKernelFile()
                    } label: {
                        HStack {
                            Text(viewModel.config.kernelPath.isEmpty ? "点击选择内核文件..." : viewModel.config.kernelPath)
                                .foregroundStyle(viewModel.config.kernelPath.isEmpty ? Color.secondary : Color.primary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color(nsColor: .textBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
                        .overlay(
                            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium)
                                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.isLoading || viewModel.isDownloading || viewModel.isSelectingKernelFile)
                }

                // GitHub Releases URL
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Text("GitHub Releases URL")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Button(action: {
                            viewModel.openGitHubReleases()
                        }) {
                            HStack(spacing: 4) {
                                Text("访问")
                                    .font(.caption2)
                                Image(systemName: "arrow.up.forward.square")
                                    .imageScale(.small)
                            }
                        }
                        .buttonStyle(.link)
                        .foregroundStyle(.blue)
                    }

                    TextField("输入 GitHub Releases URL", text: $viewModel.config.githubReleasesURL)
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color(nsColor: .textBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
                        .overlay(
                            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium)
                                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                        )
                        .disabled(viewModel.isLoading || viewModel.isDownloading)
                }

                // 内核文件名模板
                VStack(alignment: .leading, spacing: 8) {
                    Text("内核文件名模板")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    TextField("例如：mihomo-darwin-arm64-alpha-smart", text: $viewModel.config.kernelFilenameTemplate)
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color(nsColor: .textBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
                        .overlay(
                            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium)
                                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                        )
                        .disabled(viewModel.isLoading || viewModel.isDownloading)
                }
            }
            .padding(DesignSystem.Spacing.standard)
        } label: {
            SectionHeader(title: "配置", icon: "gear.circle.fill", iconColor: .gray)
        }
    }
}

#Preview {
    MihomoView()
        .environment(MihomoViewModel())
}
