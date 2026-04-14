//
//  DNSSceneCard.swift
//  NetCue
//
//  Created by SlippinDylan on 2025/12/25.
//

import SwiftUI

struct DNSSceneCard: View {
    @Binding var scene: DNSScene
    let onEdit: () -> Void
    let onDelete: () -> Void
    var onHelperNotInstalled: (() -> Void)? = nil

    @State private var dnsManager = DNSManager.shared

    var body: some View {
        GroupBox {
            HStack(alignment: .center, spacing: 16) {
                // 左侧内容区域
                VStack(alignment: .leading, spacing: 8) {
                    // 第一行：场景名称和路由器信息
                    HStack(spacing: 6) {
                        Text(scene.name)
                            .fontWeight(.bold)
                            .foregroundStyle(.primary)

                        HStack(spacing: 6) {
                            // IP 地址 tag（带图标）
                            HStack(spacing: 3) {
                                // 左侧正方形图标块
                                ZStack {
                                    RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small)
                                        .fill(Color.blue)
                                    Image(systemName: "point.3.connected.trianglepath.dotted")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.white)
                                }
                                .frame(width: 16, height: 16)

                                // IP 地址文本
                                Text(scene.routerIP)
                            }
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(.blue.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small))

                            // MAC 地址 tag（带图标）
                            HStack(spacing: 3) {
                                // 左侧正方形图标块
                                ZStack {
                                    RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small)
                                        .fill(Color.orange)
                                    Image(systemName: "externaldrive.connected.to.line.below.fill")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.white)
                                }
                                .frame(width: 16, height: 16)

                                // MAC 地址文本
                                Text(scene.routerMAC)
                            }
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(.orange.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small))
                        }
                    }

                    // 第二行：DNS 配置
                    HStack(spacing: 6) {
                        // 主 DNS 服务器 tag（带图标）
                        HStack(spacing: 3) {
                            // 左侧正方形图标块
                            ZStack {
                                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small)
                                    .fill(Color.green)
                                Image(systemName: "server.rack")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.white)
                            }
                            .frame(width: 16, height: 16)

                            // DNS 地址文本
                            Text(scene.primaryDNS)
                        }
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(.green.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small))

                        // 备用 DNS 服务器 tag（带图标）
                        if !scene.secondaryDNS.isEmpty {
                            HStack(spacing: 3) {
                                // 左侧正方形图标块
                                ZStack {
                                    RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small)
                                        .fill(Color.green)
                                    Image(systemName: "server.rack")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.white)
                                }
                                .frame(width: 16, height: 16)

                                // DNS 地址文本
                                Text(scene.secondaryDNS)
                            }
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(.green.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small))
                        }
                    }
                }

                Spacer()

                // 右侧操作按钮（垂直居中）
                HStack(spacing: 12) {
                    Toggle("", isOn: Binding(
                        get: { scene.isEnabled },
                        set: { newValue in
                            // 只在尝试开启时检查 Helper 状态
                            if newValue && !dnsManager.isHelperInstalled {
                                onHelperNotInstalled?()
                            } else {
                                scene.isEnabled = newValue
                            }
                        }
                    ))
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .controlSize(.mini)

                    Button {
                        onEdit()
                    } label: {
                        Image(systemName: "square.and.pencil")
                            .font(.system(size: 13))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.blue)

                    Button {
                        onDelete()
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 13))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.red)
                }
            }
            .padding()
        }
    }
}
