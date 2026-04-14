//
//  SceneCard.swift
//  NetCue
//
//  Created by SlippinDylan on 2025/12/25.
//

import SwiftUI

struct SceneCard: View {
    @Binding var scene: NetworkScene
    let onEdit: () -> Void
    let onDelete: () -> Void

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

                    // 第二行：控制应用
                    if !scene.controlApps.isEmpty {
                        HStack(spacing: 6) {
                            ForEach(scene.controlApps, id: \.self) { app in
                                HStack(spacing: 3) {
                                    // 显示应用图标
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

                Spacer()

                // 右侧操作按钮（垂直居中）
                HStack(spacing: 12) {
                    Toggle("", isOn: $scene.isEnabled)
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

    // 获取应用图标
    private func getAppIcon(appName: String) -> NSImage? {
        let workspace = NSWorkspace.shared
        let appPath = workspace.urlForApplication(withBundleIdentifier: "com.apple.\(appName)") ??
                      workspace.urlForApplication(withBundleIdentifier: appName) ??
                      URL(fileURLWithPath: "/Applications/\(appName).app")

        return workspace.icon(forFile: appPath.path)
    }
}
