//
//  NetworkMonitorView.swift
//  NetCue
//
//  Created by SlippinDylan on 2025/12/25.
//

import SwiftUI

/// 网络控制视图（重构版）
///
/// ## 架构说明
/// - GroupBox 1: 当前网络 - 展示网络基本信息（网络名称、网关IP、网关MAC）
/// - GroupBox 2: 应用控制 - 展示应用控制的当前状态（匹配场景、控制应用）
/// - GroupBox 3: DNS控制 - 展示DNS控制的当前状态（匹配场景、DNS）
/// - Picker + 添加场景按钮（不在GroupBox内）
/// - GroupBox 4: 场景列表 - 根据Picker选择显示应用控制或DNS控制场景列表
///
/// ## 数据流
/// - 应用控制场景：NetworkScene -> SceneStorage -> NetworkMonitor.updateScenes()
/// - DNS控制场景：DNSScene -> DNSSceneStorage -> NetworkMonitor.updateDNSScenes()
struct NetworkMonitorView: View {
    // MARK: - Environment

    @Environment(NetworkMonitor.self) private var networkMonitor
    @Environment(WindowCoordinator.self) private var windowCoordinator

    // MARK: - State

    /// 场景类型枚举
    enum SceneType {
        case appControl   // 应用控制
        case dnsControl   // DNS控制
    }

    // 应用控制场景
    @State private var appScenes: [NetworkScene] = []
    @State private var showingAppSceneSheet = false
    @State private var editingAppScene: NetworkScene?

    // DNS控制场景
    @State private var dnsScenes: [DNSScene] = []
    @State private var dnsManager = DNSManager.shared
    @State private var showingDNSSceneSheet = false
    @State private var editingDNSScene: DNSScene?
    @State private var showHelperNotInstalledAlert = false

    // 场景类型选择
    @State private var selectedSceneType: SceneType = .appControl

    // MARK: - Body

    var body: some View {
        NetCueScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // GroupBox 1: 当前网络
                currentNetworkGroupBox

                // GroupBox 2 & 3: 应用控制 + DNS控制（左右分布，等高）
                HStack(alignment: .top, spacing: 16) {
                    appControlGroupBox
                        .frame(maxHeight: .infinity, alignment: .top)
                    dnsControlGroupBox
                        .frame(maxHeight: .infinity, alignment: .top)
                }
                .fixedSize(horizontal: false, vertical: true)

                // Picker + 添加场景按钮（不在GroupBox内）
                sceneTypeSelector

                // GroupBox 4: 场景列表
                sceneListGroupBox
            }
            .padding(DesignSystem.Spacing.standard)
        }
        .sheet(isPresented: $showingAppSceneSheet) {
            SceneConfigSheet(
                scene: $editingAppScene,
                isEditing: editingAppScene != nil,
                onSave: { newScene in
                    if let index = appScenes.firstIndex(where: { $0.id == newScene.id }) {
                        appScenes[index] = newScene
                    } else {
                        appScenes.append(newScene)
                    }
                    networkMonitor.updateScenes(appScenes)
                }
            )
        }
        .sheet(isPresented: $showingDNSSceneSheet) {
            DNSSceneConfigSheet(
                scene: editingDNSScene,
                onSave: { newScene in
                    if let index = dnsScenes.firstIndex(where: { $0.id == newScene.id }) {
                        dnsScenes[index] = newScene
                    } else {
                        dnsScenes.append(newScene)
                    }
                    saveDNSScenes()
                }
            )
        }
        .onAppear {
            loadScenes()
            refreshCurrentDNS()
        }
        .onChange(of: appScenes) { _, _ in
            SceneStorage.saveScenes(appScenes)
            networkMonitor.updateScenes(appScenes)
        }
        .onChange(of: dnsScenes) { _, _ in
            saveDNSScenes()
        }
        .alert("Helper 未安装", isPresented: $showHelperNotInstalledAlert) {
            Button("前往设置") {
                windowCoordinator.selectedTab = 4
            }
            Button("取消", role: .cancel) { }
        } message: {
            Text("DNS 管理功能需要安装 Helper Tool，请前往设置页面安装。")
        }
    }

    // MARK: - GroupBox 1: 当前网络

    /// 当前网络信息卡片
    private var currentNetworkGroupBox: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                // 网络名称
                HStack {
                    Text("网络名称")
                        .foregroundStyle(.secondary)
                    Spacer()
                    if networkMonitor.activeNetworks.isEmpty {
                        Text("-")
                            .fontWeight(.medium)
                    } else {
                        HStack(spacing: 6) {
                            ForEach(networkMonitor.activeNetworks) { network in
                                Text(network.displayName)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(.blue.opacity(0.1))
                                    .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small))
                            }
                        }
                    }
                }

                // 网关 IP
                InfoRow(label: "网关 IP", value: networkMonitor.currentRouterIP)

                // 网关 MAC
                InfoRow(label: "网关 MAC", value: networkMonitor.currentRouterMAC)

                // 当前 DNS
                HStack {
                    Text("DNS")
                        .foregroundStyle(.secondary)
                    Spacer()
                    if dnsManager.currentPrimaryDNS == "-" && dnsManager.currentSecondaryDNS == "-" {
                        Text("-")
                            .fontWeight(.medium)
                    } else {
                        HStack(spacing: 6) {
                            // 主 DNS
                            if dnsManager.currentPrimaryDNS != "-" {
                                HStack(spacing: 4) {
                                    Image(systemName: "circle.fill")
                                        .font(.system(size: 6))
                                        .foregroundStyle(.green)
                                    Text(dnsManager.currentPrimaryDNS)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(.green.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small))
                            }

                            // 备用 DNS
                            if dnsManager.currentSecondaryDNS != "-" {
                                Text(dnsManager.currentSecondaryDNS)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(.green.opacity(0.1))
                                    .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small))
                            }
                        }
                    }
                }
            }
            .padding()
        } label: {
            SectionHeader(title: "当前网络", icon: "wifi", iconColor: .blue)
        }
    }

    // MARK: - GroupBox 2: 应用控制

    /// 应用控制状态卡片
    private var appControlGroupBox: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                // 匹配场景
                HStack {
                    Text("匹配场景")
                        .foregroundStyle(.secondary)
                    Spacer()
                    if networkMonitor.matchedScenes.isEmpty {
                        Text("-")
                            .fontWeight(.medium)
                    } else {
                        HStack(spacing: 6) {
                            ForEach(networkMonitor.matchedScenes) { scene in
                                Text(scene.name)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(.purple.opacity(0.1))
                                    .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small))
                            }
                        }
                    }
                }
                .frame(minHeight: 20)

                // 控制应用
                HStack(alignment: .top) {
                    Text("控制应用")
                        .foregroundStyle(.secondary)
                    Spacer()
                    if allControlApps.isEmpty {
                        Text("-")
                            .fontWeight(.medium)
                    } else {
                        HStack(spacing: 6) {
                            ForEach(allControlApps, id: \.self) { app in
                                HStack(spacing: 3) {
                                    if let icon = getAppIcon(appName: app) {
                                        Image(nsImage: icon)
                                            .resizable()
                                            .frame(width: 16, height: 16)
                                    } else {
                                        Image(systemName: "app.fill")
                                            .foregroundStyle(.blue)
                                    }
                                    Text(app)
                                }
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(.blue.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small))
                            }
                        }
                    }
                }
                .frame(minHeight: 20)
            }
            .padding()
        } label: {
            SectionHeader(title: "应用控制", icon: "app.fill", iconColor: .blue)
        }
    }

    // MARK: - GroupBox 3: DNS控制

    /// DNS控制状态卡片
    private var dnsControlGroupBox: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                // 匹配场景（移到上面）
                HStack {
                    Text("匹配场景")
                        .foregroundStyle(.secondary)
                    Spacer()
                    if let matchedScene = currentMatchedDNSScene {
                        Text(matchedScene.name)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.purple.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small))
                    } else {
                        Text("-")
                            .fontWeight(.medium)
                    }
                }
                .frame(minHeight: 20)

                // DNS（显示匹配场景配置的 DNS，而非系统当前 DNS）
                HStack {
                    Text("DNS")
                        .foregroundStyle(.secondary)
                    Spacer()
                    if let matchedScene = currentMatchedDNSScene {
                        HStack(spacing: 6) {
                            // 主 DNS
                            HStack(spacing: 4) {
                                Image(systemName: "circle.fill")
                                    .font(.system(size: 6))
                                    .foregroundStyle(.green)
                                Text(matchedScene.primaryDNS)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.green.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small))

                            // 备用 DNS
                            if !matchedScene.secondaryDNS.isEmpty {
                                Text(matchedScene.secondaryDNS)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(.green.opacity(0.1))
                                    .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small))
                            }
                        }
                    } else {
                        Text("-")
                            .fontWeight(.medium)
                    }
                }
                .frame(minHeight: 20)
            }
            .padding()
        } label: {
            SectionHeader(title: "DNS 控制", icon: "server.rack", iconColor: .green)
        }
    }

    // MARK: - Scene Type Selector (不在GroupBox内)

    /// 场景类型选择器（Picker + 添加场景按钮）
    private var sceneTypeSelector: some View {
        HStack {
            Picker("", selection: $selectedSceneType) {
                Text("应用控制").tag(SceneType.appControl)
                Text("DNS控制").tag(SceneType.dnsControl)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()

            Spacer()

            Button("添加场景") {
                if selectedSceneType == .appControl {
                    editingAppScene = nil
                    showingAppSceneSheet = true
                } else {
                    editingDNSScene = nil
                    showingDNSSceneSheet = true
                }
            }
            .adaptiveGlassProminentButtonStyle()
        }
    }

    // MARK: - GroupBox 4: 场景列表

    /// 场景列表（根据选择显示不同类型）
    private var sceneListGroupBox: some View {
        GroupBox {
            if selectedSceneType == .appControl {
                appSceneList
            } else {
                dnsSceneList
            }
        }
    }

    /// 应用控制场景列表
    private var appSceneList: some View {
        Group {
            if appScenes.isEmpty {
                Text("暂无配置的场景")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else {
                VStack(spacing: 12) {
                    ForEach($appScenes) { $scene in
                        SceneCard(
                            scene: $scene,
                            onEdit: {
                                editingAppScene = scene
                                showingAppSceneSheet = true
                            },
                            onDelete: {
                                appScenes.removeAll { $0.id == scene.id }
                            }
                        )
                    }
                }
            }
        }
    }

    /// DNS控制场景列表
    private var dnsSceneList: some View {
        Group {
            if dnsScenes.isEmpty {
                Text("暂无配置的场景")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else {
                VStack(spacing: 12) {
                    ForEach($dnsScenes) { $scene in
                        DNSSceneCard(
                            scene: $scene,
                            onEdit: {
                                editingDNSScene = scene
                                showingDNSSceneSheet = true
                            },
                            onDelete: {
                                dnsScenes.removeAll { $0.id == scene.id }
                                saveDNSScenes()
                            },
                            onHelperNotInstalled: {
                                showHelperNotInstalledAlert = true
                            }
                        )
                    }
                }
            }
        }
    }

    // MARK: - Helper Methods

    /// 计算所有匹配场景的控制应用（去重）
    private var allControlApps: [String] {
        var apps: [String] = []
        for scene in networkMonitor.matchedScenes {
            for app in scene.controlApps {
                if !apps.contains(app) {
                    apps.append(app)
                }
            }
        }
        return apps
    }

    /// 当前匹配的DNS场景
    private var currentMatchedDNSScene: DNSScene? {
        dnsScenes.first { scene in
            scene.isEnabled &&
            scene.routerIP == networkMonitor.currentRouterIP &&
            scene.routerMAC.lowercased() == networkMonitor.currentRouterMAC.lowercased()
        }
    }

    /// 获取应用图标
    private func getAppIcon(appName: String) -> NSImage? {
        let workspace = NSWorkspace.shared
        let appPath = workspace.urlForApplication(withBundleIdentifier: "com.apple.\(appName)") ??
                      workspace.urlForApplication(withBundleIdentifier: appName) ??
                      URL(fileURLWithPath: "/Applications/\(appName).app")

        return workspace.icon(forFile: appPath.path)
    }

    /// 加载所有场景
    private func loadScenes() {
        // 加载应用控制场景
        appScenes = SceneStorage.loadScenes()
        networkMonitor.updateScenes(appScenes)

        // 加载DNS控制场景
        dnsScenes = DNSSceneStorage.shared.loadScenes()
        networkMonitor.updateDNSScenes(dnsScenes)
    }

    /// 保存DNS场景
    private func saveDNSScenes() {
        DNSSceneStorage.shared.saveScenes(dnsScenes)
        networkMonitor.updateDNSScenes(dnsScenes)
    }

    /// 刷新当前DNS配置
    private func refreshCurrentDNS() {
        guard let firstNetwork = networkMonitor.activeNetworks.first else {
            return
        }
        dnsManager.getCurrentDNS(interface: firstNetwork.displayName) { _ in }
    }
}
