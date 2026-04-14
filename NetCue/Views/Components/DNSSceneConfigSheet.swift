//
//  DNSSceneConfigSheet.swift
//  NetCue
//
//  Created by SlippinDylan on 2025/12/25.
//  Updated by SlippinDylan on 2026/01/08 - 修复滚动问题，Form 改为 VStack
//

import SwiftUI

struct DNSSceneConfigSheet: View {
    @Environment(\.dismiss) var dismiss

    @State private var sceneName = ""
    @State private var routerIP = ""
    @State private var routerMAC = ""
    @State private var primaryDNS = ""
    @State private var secondaryDNS = ""
    @State private var showRouterIPError = false
    @State private var showRouterMACError = false
    @State private var showPrimaryDNSError = false
    @State private var showSecondaryDNSError = false

    let scene: DNSScene?
    let onSave: (DNSScene) -> Void

    private var isEditing: Bool {
        scene != nil
    }

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
                    DNSFormSection(title: "场景名称") {
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
                    DNSFormSection(title: "路由器配置") {
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
                                            .stroke(showRouterIPError ? Color.red : Color.gray.opacity(0.3), lineWidth: 1)
                                    )
                                    .onChange(of: routerIP) { _, _ in
                                        showRouterIPError = false
                                    }

                                if showRouterIPError {
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
                                            .stroke(showRouterMACError ? Color.red : Color.gray.opacity(0.3), lineWidth: 1)
                                    )
                                    .onChange(of: routerMAC) { _, _ in
                                        showRouterMACError = false
                                    }

                                if showRouterMACError {
                                    Text("MAC 地址格式不正确")
                                        .font(.caption)
                                        .foregroundStyle(.red)
                                }
                            }
                        }
                    }

                    // Section 3: DNS 配置
                    DNSFormSection(title: "DNS 配置") {
                        VStack(alignment: .leading, spacing: 12) {
                            // 主 DNS
                            VStack(alignment: .leading, spacing: 4) {
                                TextField("主 DNS", text: $primaryDNS)
                                    .textFieldStyle(.plain)
                                    .padding(10)
                                    .background(Color(nsColor: .textBackgroundColor))
                                    .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small)
                                            .stroke(showPrimaryDNSError ? Color.red : Color.gray.opacity(0.3), lineWidth: 1)
                                    )
                                    .onChange(of: primaryDNS) { _, _ in
                                        showPrimaryDNSError = false
                                    }

                                if showPrimaryDNSError {
                                    Text("DNS 地址格式不正确")
                                        .font(.caption)
                                        .foregroundStyle(.red)
                                }
                            }

                            // 备用 DNS
                            VStack(alignment: .leading, spacing: 4) {
                                TextField("备用 DNS（可选）", text: $secondaryDNS)
                                    .textFieldStyle(.plain)
                                    .padding(10)
                                    .background(Color(nsColor: .textBackgroundColor))
                                    .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small)
                                            .stroke(showSecondaryDNSError ? Color.red : Color.gray.opacity(0.3), lineWidth: 1)
                                    )
                                    .onChange(of: secondaryDNS) { _, _ in
                                        showSecondaryDNSError = false
                                    }

                                if showSecondaryDNSError {
                                    Text("DNS 地址格式不正确")
                                        .font(.caption)
                                        .foregroundStyle(.red)
                                }
                            }
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
                primaryDNS = scene.primaryDNS
                secondaryDNS = scene.secondaryDNS
            }
        }
    }

    // MARK: - Validation

    private var isFormValid: Bool {
        let isSecondaryDNSValid = secondaryDNS.isEmpty || NetworkValidator.isValidIP(secondaryDNS)

        return !sceneName.isEmpty &&
               !routerIP.isEmpty &&
               !routerMAC.isEmpty &&
               !primaryDNS.isEmpty &&
               NetworkValidator.isValidIP(routerIP) &&
               NetworkValidator.isValidMAC(routerMAC) &&
               NetworkValidator.isValidIP(primaryDNS) &&
               isSecondaryDNSValid
    }

    // MARK: - Actions

    private func saveScene() {
        // 验证路由器 IP 地址格式
        if !NetworkValidator.isValidIP(routerIP) {
            showRouterIPError = true
            return
        }

        // 验证路由器 MAC 地址格式
        if !NetworkValidator.isValidMAC(routerMAC) {
            showRouterMACError = true
            return
        }

        // 验证主 DNS 地址格式
        if !NetworkValidator.isValidIP(primaryDNS) {
            showPrimaryDNSError = true
            return
        }

        // 验证备用 DNS 地址格式（如果填写了）
        if !secondaryDNS.isEmpty && !NetworkValidator.isValidIP(secondaryDNS) {
            showSecondaryDNSError = true
            return
        }

        // 规范化 MAC 地址（确保存储格式统一）
        let normalizedMAC = NetworkValidator.normalizeMAC(routerMAC) ?? routerMAC

        let newScene = DNSScene(
            id: scene?.id ?? UUID(),
            name: sceneName,
            routerIP: routerIP,
            routerMAC: normalizedMAC,
            primaryDNS: primaryDNS,
            secondaryDNS: secondaryDNS,
            isEnabled: scene?.isEnabled ?? true
        )
        onSave(newScene)
        dismiss()
    }
}

// MARK: - Form Section Component

/// 表单分组组件（模拟 Form Section 样式）
private struct DNSFormSection<Content: View>: View {
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
