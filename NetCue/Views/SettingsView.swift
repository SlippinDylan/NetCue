//
//  SettingsView.swift
//  NetCue
//
//  Created by SlippinDylan on 2025/12/25.
//
//  ## 2026/01/07 重构
//  - 统一 API Key 管理
//  - 有免费 API 的数据源：未配置时用免费 API，配置后用付费 API
//  - 纯付费数据源：未配置时跳过
//  - 移除状态指示器图标
//

import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(NetworkMonitor.self) private var networkMonitor
    @State private var dnsManager = DNSManager.shared
    @State private var permissionManager = PermissionManager.shared
    @State private var apiKeyManager = APIKeyManager.shared
    @State private var loginItemManager = LoginItemManager.shared

    // 导出/导入状态
    @State private var isExporting = false
    @State private var isImporting = false
    @State private var showImportConfirmAlert = false
    @State private var importedData: NetCueExportData?

    var body: some View {
        NetCueScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // 通用设置
                generalSettingsSection

                // IP 质量检测 API 配置
                apiKeySettingsSection

                // 配置导出/导入
                exportImportSection

                // 权限状态
                permissionsSection
            }
            .padding()
        }
        .onAppear {
            permissionManager.refresh()
        }
        // 确认导入弹窗（需要用户操作）
        .alert("确认导入", isPresented: $showImportConfirmAlert) {
            Button("取消", role: .cancel) {
                importedData = nil
            }
            Button("导入") {
                if let data = importedData {
                    applyImportedData(data)
                }
            }
        } message: {
            if let data = importedData {
                Text("将导入 \(data.appControlScenes.count) 个应用控制场景、\(data.dnsControlScenes.count) 个 DNS 控制场景和 API Key 配置。\n\n此操作将覆盖现有配置，是否继续？")
            }
        }
    }

    // MARK: - Login Launch Settings Section

    private var generalSettingsSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("登录时自动启动")
                        .font(.body)

                    Spacer()

                    Toggle("", isOn: Binding(
                        get: { loginItemManager.isEnabled },
                        set: { newValue in
                            do {
                                if newValue {
                                    try loginItemManager.enable()
                                } else {
                                    try loginItemManager.disable()
                                }
                            } catch {
                                AppLogger.error("更改开机自启状态失败", error: error)
                                loginItemManager.refreshStatus()
                            }
                        }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(DesignSystem.Spacing.standard)
        } label: {
            SectionHeader(
                title: "登录启动设置",
                icon: "gearshape",
                iconColor: .gray,
                description: "应用基本行为"
            )
        }
    }

    // MARK: - Export/Import Section

    private var exportImportSection: some View {
        GroupBox {
            HStack(spacing: 16) {
                // 左侧说明
                VStack(alignment: .leading, spacing: 4) {
                    Text("导出配置后可在重新安装时快速恢复，包括应用控制场景、DNS 控制场景和 API Key 配置。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // 右侧按钮
                HStack(spacing: 8) {
                    Button {
                        performImport()
                    } label: {
                        if isImporting {
                            ProgressView()
                                .controlSize(.small)
                                .frame(width: 60)
                        } else {
                            Text("导入配置")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .disabled(isImporting || isExporting)

                    Button {
                        performExport()
                    } label: {
                        if isExporting {
                            ProgressView()
                                .controlSize(.small)
                                .frame(width: 60)
                        } else {
                            Text("导出配置")
                        }
                    }
                    .adaptiveGlassProminentButtonStyle()
                    .disabled(isImporting || isExporting)
                }
            }
            .padding(DesignSystem.Spacing.standard)
        } label: {
            SectionHeader(
                title: "配置管理",
                icon: "square.and.arrow.up.on.square",
                iconColor: .purple,
                description: "导出和导入应用配置"
            )
        }
    }

    // MARK: - Export/Import Actions

    private func performExport() {
        isExporting = true

        Task {
            let result = await SettingsExportService.shared.exportSettings()

            await MainActor.run {
                isExporting = false

                switch result {
                case .success(let url):
                    Toast.success("配置已导出到: \(url.lastPathComponent)")

                case .cancelled:
                    break

                case .failure(let error):
                    Toast.error(error.localizedDescription)
                }
            }
        }
    }

    private func performImport() {
        isImporting = true

        Task {
            let result = await SettingsExportService.shared.importSettings()

            await MainActor.run {
                isImporting = false

                switch result {
                case .success(let data):
                    // 先保存数据，显示确认弹窗
                    importedData = data
                    showImportConfirmAlert = true

                case .cancelled:
                    break

                case .failure(let error):
                    Toast.error(error.localizedDescription)
                }
            }
        }
    }

    private func applyImportedData(_ data: NetCueExportData) {
        // 应用应用控制场景
        SceneStorage.saveScenes(data.appControlScenes)

        // 应用 DNS 控制场景
        DNSSceneStorage.shared.saveScenes(data.dnsControlScenes)

        // 应用 API Keys
        data.apiKeys.apply(to: apiKeyManager)

        // 刷新 NetworkMonitor 中的场景
        networkMonitor.updateScenes(data.appControlScenes)
        networkMonitor.updateDNSScenes(data.dnsControlScenes)

        // 清理状态
        importedData = nil

        // 显示成功提示
        Toast.success("已导入 \(data.appControlScenes.count) 个场景和 \(data.dnsControlScenes.count) 个 DNS 场景")

        AppLogger.info("✅ 配置导入完成")
    }

    // MARK: - API Key Settings Section

    private var apiKeySettingsSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 16) {
                // 顶部：说明文字 + 按钮
                HStack(alignment: .top, spacing: 16) {
                    // 左侧说明文字
                    VStack(alignment: .leading, spacing: 8) {
                        Text("配置 API Key 可获取更完整的数据。有免费 API 的数据源未配置时使用免费版，纯付费数据源未配置时跳过。")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 12) {
                            // 数据源状态
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                    .font(.system(size: 12))
                                Text("\(apiKeyManager.totalEnabledSourceCount) 个数据源可用")
                                    .font(.caption)
                                    .foregroundStyle(.green)
                            }

                            // API Key 配置状态
                            HStack(spacing: 4) {
                                Image(systemName: apiKeyManager.hasAnyAPIKey ? "key.fill" : "key")
                                    .foregroundStyle(apiKeyManager.hasAnyAPIKey ? Color.blue : Color.secondary)
                                    .font(.system(size: 12))
                                Text("\(apiKeyManager.configuredKeyCount) 个 API Key 已配置")
                                    .font(.caption)
                                    .foregroundStyle(apiKeyManager.hasAnyAPIKey ? Color.blue : Color.secondary)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    // 右侧按钮
                    HStack(spacing: 8) {
                        Button("清除全部") {
                            apiKeyManager.clearAllAPIKeys()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)

                        Button("保存配置") {
                            apiKeyManager.saveAPIKeys()
                        }
                        .adaptiveGlassProminentButtonStyle()
                    }
                }

                Divider()

                // 有免费 API 的数据源（配置后使用付费版）
                VStack(alignment: .leading, spacing: 12) {
                    Text("有免费 API（配置 Key 后使用付费版，数据更全）")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)

                    // IPinfo
                    APIKeyInputRow(
                        label: "IPinfo",
                        placeholder: "Token",
                        value: $apiKeyManager.ipinfoToken,
                        helpURL: "https://ipinfo.io/signup"
                    )

                    // ipapi.is
                    APIKeyInputRow(
                        label: "ipapi.is",
                        placeholder: "API Key",
                        value: $apiKeyManager.ipapiKey,
                        helpURL: "https://ipapi.is/"
                    )

                    // DB-IP
                    APIKeyInputRow(
                        label: "DB-IP",
                        placeholder: "API Key",
                        value: $apiKeyManager.dbipKey,
                        helpURL: "https://db-ip.com/api/"
                    )

                    // IPWHOIS
                    APIKeyInputRow(
                        label: "IPWHOIS",
                        placeholder: "API Key",
                        value: $apiKeyManager.ipwhoisKey,
                        helpURL: "https://ipwhois.io/documentation"
                    )
                }

                Divider()

                // 纯付费数据源
                VStack(alignment: .leading, spacing: 12) {
                    Text("纯付费数据源（未配置时跳过）")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)

                    // AbuseIPDB
                    APIKeyInputRow(
                        label: "AbuseIPDB",
                        placeholder: "API Key",
                        value: $apiKeyManager.abuseipdbKey,
                        helpURL: "https://www.abuseipdb.com/api"
                    )

                    // IP2Location
                    APIKeyInputRow(
                        label: "IP2Location",
                        placeholder: "API Key",
                        value: $apiKeyManager.ip2locationKey,
                        helpURL: "https://www.ip2location.io/"
                    )

                    // ipregistry
                    APIKeyInputRow(
                        label: "ipregistry",
                        placeholder: "API Key",
                        value: $apiKeyManager.ipregistryKey,
                        helpURL: "https://ipregistry.co/"
                    )
                }
            }
            .padding(DesignSystem.Spacing.standard)
        } label: {
            SectionHeader(
                title: "IP 质量检测设置",
                icon: "network",
                iconColor: .blue,
                description: "数据源 API Key 配置"
            )
        }
    }

    // MARK: - Permissions Section

    private var permissionsSection: some View {
        GroupBox {
            VStack(spacing: 12) {
                ForEach(Array(permissionManager.permissions.enumerated()), id: \.element.type.displayName) { _, permission in
                    VStack(alignment: .leading, spacing: 8) {
                        // 第一行：图标 + 名称 + 状态 + 按钮
                        HStack {
                            Image(systemName: permission.isGranted ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundStyle(Color(permission.statusColor))
                                .font(.system(size: 14))

                            Text(permission.type.displayName)
                                .font(.system(size: 14, weight: .medium))

                            Spacer()

                            Text(permission.statusText)
                                .font(.caption)
                                .foregroundStyle(Color(permission.statusColor))

                            // 操作按钮
                            switch permission.type {
                            case .accessibility:
                                if !permission.isGranted && permission.isRequired {
                                    Button("打开设置") {
                                        permissionManager.openAccessibilitySettings()
                                    }
                                    .adaptiveGlassProminentButtonStyle()
                                    .controlSize(.small)
                                }
                            case .helperTool:
                                // Helper Tool 始终显示操作按钮（安装或卸载）
                                HelperActionButton(
                                    dnsManager: dnsManager,
                                    networkMonitor: networkMonitor,
                                    isInstalled: permission.isGranted
                                )
                            }
                        }

                        // 第二行：描述
                        Text(permission.type.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.leading, 20)

                        Divider()
                            .padding(.leading, 20)

                        // 第三行：提示文字
                        if permission.isGranted {
                            Text(successText(for: permission.type))
                                .font(.caption)
                                .foregroundStyle(.green)
                                .padding(.leading, 20)
                        } else {
                            Text(permission.type.guideText)
                                .font(.caption)
                                .foregroundStyle(.orange)
                                .padding(.leading, 20)
                        }
                    }
                    .padding()
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
                }
            }
        } label: {
            HStack {
                SectionHeader(
                    title: "权限状态",
                    icon: "lock.shield",
                    iconColor: permissionManager.allRequiredGranted ? .green : .orange,
                    description: "NetCue 所需的系统权限"
                )
                Spacer()
                HStack(spacing: 8) {
                    if permissionManager.allRequiredGranted {
                        Image(systemName: "checkmark.shield.fill")
                            .foregroundStyle(.green)
                            .font(.system(size: 12))
                        Text("所有必需权限已授权，功能正常")
                            .font(.caption)
                            .foregroundStyle(.green)
                    } else {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .font(.system(size: 12))
                        Text("部分必需权限未授权，某些功能可能无法正常使用")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }
        }
    }

    // MARK: - Private Methods

    private func successText(for type: PermissionType) -> String {
        switch type {
        case .accessibility:
            return "辅助功能权限已授权，网络控制功能可以正常使用"
        case .helperTool:
            return "DNS Helper 已安装，DNS 管理功能可以正常使用"
        }
    }
}

// MARK: - Helper Action Button

/// Helper 操作按钮组件
///
/// ## 功能
/// - 根据安装状态显示「安装 Helper」或「卸载 Helper」按钮
/// - 显示操作进度和结果反馈
/// - 操作成功后自动刷新权限状态
/// - 安装成功后触发 DNS 场景匹配
private struct HelperActionButton: View {
    let dnsManager: DNSManager
    let networkMonitor: NetworkMonitor
    let isInstalled: Bool

    @State private var isProcessing: Bool = false

    var body: some View {
        Group {
            if isInstalled {
                Button {
                    uninstallHelper()
                } label: {
                    buttonLabel
                }
                .adaptiveGlassProminentButtonStyle()
                .tint(.red)
            } else {
                Button {
                    installHelper()
                } label: {
                    buttonLabel
                }
                .adaptiveGlassProminentButtonStyle()
            }
        }
        .controlSize(.small)
        .disabled(isProcessing)
    }

    @ViewBuilder
    private var buttonLabel: some View {
        if isProcessing {
            ProgressView()
                .controlSize(.small)
                .padding(.horizontal, 8)
        } else {
            Text(isInstalled ? "卸载 Helper" : "安装 Helper")
        }
    }

    private func installHelper() {
        isProcessing = true
        dnsManager.installHelper { success, error in
            DispatchQueue.main.async {
                isProcessing = false

                if success {
                    Toast.success("DNS Helper 已成功安装")
                    // 触发 DNS 场景匹配，确保已开启的场景立即生效
                    networkMonitor.refreshDNSSceneMatching()
                } else {
                    let message = error?.localizedDescription ?? "安装失败，请重试"
                    Toast.error(message)
                }

                // 刷新权限状态
                PermissionManager.shared.refresh()
            }
        }
    }

    private func uninstallHelper() {
        isProcessing = true
        dnsManager.uninstallHelper { success, error in
            DispatchQueue.main.async {
                isProcessing = false

                if success {
                    Toast.success("DNS Helper 已成功卸载")
                } else {
                    let message = error?.localizedDescription ?? "卸载失败，请重试"
                    Toast.error(message)
                }

                // 刷新权限状态
                PermissionManager.shared.refresh()
            }
        }
    }
}

// MARK: - API Key Input Row

private struct APIKeyInputRow: View {
    let label: String
    let placeholder: String
    @Binding var value: String
    let helpURL: String
    @State private var isSecure: Bool = true

    var body: some View {
        HStack(spacing: 12) {
            // 标签
            Text(label)
                .font(.system(size: 13))
                .frame(width: 100, alignment: .leading)

            // 输入框容器
            HStack(spacing: 0) {
                // 输入框
                Group {
                    if isSecure {
                        SecureField(placeholder, text: $value)
                    } else {
                        TextField(placeholder, text: $value)
                    }
                }
                .textFieldStyle(.plain)
                .padding(.leading, 10)
                .padding(.vertical, 6)

                // 眼睛按钮
                Button {
                    isSecure.toggle()
                } label: {
                    Image(systemName: isSecure ? "eye.slash" : "eye")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .padding(.trailing, 8)
                .help(isSecure ? "显示" : "隐藏")
            }
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small))
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small)
                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
            )

            // 帮助链接
            Button {
                if let url = URL(string: helpURL) {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                Image(systemName: "questionmark.circle")
                    .foregroundStyle(.blue)
                    .font(.system(size: 14))
            }
            .buttonStyle(.plain)
            .help("获取 API Key")
        }
    }
}
