//
//  SceneConfigSheet.swift
//  NetCue
//
//  Created by SlippinDylan on 2025/12/25.
//  Updated by SlippinDylan on 2026/01/06 - P2-6 修复
//  Updated by SlippinDylan on 2026/01/08 - 修复滚动问题，Form 改为 VStack
//

import SwiftUI
import UniformTypeIdentifiers

struct SceneConfigSheet: View {
    @Environment(\.dismiss) var dismiss
    @Binding var scene: NetworkScene?

    @State private var sceneName = ""
    @State private var routerIP = ""
    @State private var routerMAC = ""
    @State private var selectedApps: [String] = []
    @State private var showIPError = false
    @State private var showMACError = false

    let isEditing: Bool
    let onSave: (NetworkScene) -> Void

    var body: some View {
        VStack(spacing: 0) {
            // 标题栏
            HStack {
                Text(isEditing ? "编辑场景" : "添加场景")
                    .font(.headline)
                Spacer()
            }
            .padding()

            Divider()

            // 配置表单（使用 VStack 替代 Form，避免嵌套滚动冲突）
            NetCueScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Section 1: 场景名称
                    FormSection(title: "场景名称") {
                        TextField("输入场景名称", text: $sceneName)
                            .textFieldStyle(.plain)
                            .padding(10)
                            .background(Color(nsColor: .textBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small))
                            .overlay(
                                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small)
                                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                            )
                    }

                    // Section 2: 路由器配置
                    FormSection(title: "路由器配置") {
                        VStack(alignment: .leading, spacing: 12) {
                            // 路由器 IP
                            VStack(alignment: .leading, spacing: 4) {
                                TextField("路由器 IP", text: $routerIP)
                                    .textFieldStyle(.plain)
                                    .padding(10)
                                    .background(Color(nsColor: .textBackgroundColor))
                                    .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small)
                                            .stroke(showIPError ? Color.red : Color.gray.opacity(0.3), lineWidth: 1)
                                    )
                                    .onChange(of: routerIP) { _, _ in
                                        showIPError = false
                                    }

                                if showIPError {
                                    Text("IP 地址格式不正确")
                                        .font(.caption)
                                        .foregroundStyle(.red)
                                }
                            }

                            // MAC 地址
                            VStack(alignment: .leading, spacing: 4) {
                                TextField("MAC 地址", text: $routerMAC)
                                    .textFieldStyle(.plain)
                                    .padding(10)
                                    .background(Color(nsColor: .textBackgroundColor))
                                    .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small)
                                            .stroke(showMACError ? Color.red : Color.gray.opacity(0.3), lineWidth: 1)
                                    )
                                    .onChange(of: routerMAC) { _, _ in
                                        showMACError = false
                                    }

                                if showMACError {
                                    Text("MAC 地址格式不正确")
                                        .font(.caption)
                                        .foregroundStyle(.red)
                                }
                            }
                        }
                    }

                    // Section 3: 控制应用
                    FormSection(title: "控制应用") {
                        VStack(alignment: .leading, spacing: 8) {
                            if selectedApps.isEmpty {
                                Text("暂未添加应用")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .center)
                                    .padding(.vertical, 12)
                            } else {
                                ForEach(selectedApps, id: \.self) { app in
                                    HStack {
                                        // 显示应用图标
                                        if let icon = getAppIcon(appName: app) {
                                            Image(nsImage: icon)
                                                .resizable()
                                                .frame(width: 24, height: 24)
                                        } else {
                                            Image(systemName: "app.fill")
                                                .font(.system(size: 20))
                                                .foregroundStyle(.blue)
                                        }

                                        Text(app)
                                            .font(.callout)

                                        Spacer()

                                        Button {
                                            selectedApps.removeAll { $0 == app }
                                        } label: {
                                            Image(systemName: "xmark.circle.fill")
                                                .foregroundStyle(.secondary)
                                                .font(.system(size: 16))
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    .padding(.vertical, 6)
                                    .padding(.horizontal, 10)
                                    .background(Color(nsColor: .controlBackgroundColor))
                                    .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small))
                                }
                            }

                            // 添加应用按钮
                            Button("添加应用") {
                                Task {
                                    await selectApplication()
                                }
                            }
                            .adaptiveGlassProminentButtonStyle()
                            .frame(maxWidth: .infinity)
                            .padding(.top, 8)
                        }
                    }
                }
                .padding()
            }

            Divider()

            // 底部按钮
            HStack(spacing: 12) {
                Button("取消") {
                    dismiss()
                }
                .adaptiveGlassButtonStyle()
                .frame(minWidth: 80)

                Spacer()

                Button("保存") {
                    saveScene()
                }
                .adaptiveGlassProminentButtonStyle()
                .frame(minWidth: 80)
                .disabled(!isFormValid)
            }
            .padding()
        }
        .frame(width: 500, height: 500)
        .onAppear {
            if let scene = scene {
                sceneName = scene.name
                routerIP = scene.routerIP
                routerMAC = scene.routerMAC
                selectedApps = scene.controlApps
            }
        }
    }

    // MARK: - Validation

    private var isFormValid: Bool {
        return !sceneName.isEmpty &&
               !routerIP.isEmpty &&
               !routerMAC.isEmpty &&
               !selectedApps.isEmpty &&
               NetworkValidator.isValidIP(routerIP) &&
               NetworkValidator.isValidMAC(routerMAC)
    }

    // MARK: - Actions

    /// 选择应用（P2-6 修复：使用 FilePanelHelper 替代阻塞式 NSOpenPanel.runModal()）
    private func selectApplication() async {
        let urls = await FilePanelHelper.selectApplications(
            allowMultiple: true,
            message: "选择要控制的应用"
        )

        for url in urls {
            let appName = url.deletingPathExtension().lastPathComponent
            if !selectedApps.contains(appName) {
                selectedApps.append(appName)
            }
        }
    }

    private func saveScene() {
        // 验证 IP 地址格式
        if !NetworkValidator.isValidIP(routerIP) {
            showIPError = true
            return
        }

        // 验证 MAC 地址格式
        if !NetworkValidator.isValidMAC(routerMAC) {
            showMACError = true
            return
        }

        // 规范化 MAC 地址（确保存储格式统一）
        let normalizedMAC = NetworkValidator.normalizeMAC(routerMAC) ?? routerMAC

        let newScene = NetworkScene(
            id: scene?.id ?? UUID(),
            name: sceneName,
            routerIP: routerIP,
            routerMAC: normalizedMAC,
            controlApps: selectedApps,
            isEnabled: scene?.isEnabled ?? false
        )
        onSave(newScene)
        dismiss()
    }

    // MARK: - Helpers

    private func getAppIcon(appName: String) -> NSImage? {
        let workspace = NSWorkspace.shared
        let appPath = workspace.urlForApplication(withBundleIdentifier: "com.apple.\(appName)") ??
                      workspace.urlForApplication(withBundleIdentifier: appName) ??
                      URL(fileURLWithPath: "/Applications/\(appName).app")

        return workspace.icon(forFile: appPath.path)
    }
}

// MARK: - Form Section Component

/// 表单分组组件（模拟 Form Section 样式）
private struct FormSection<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)

            content
        }
    }
}
