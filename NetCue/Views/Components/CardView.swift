//
//  CardView.swift
//  NetCue
//
//  Created by SlippinDylan on 2026/01/06.
//  P2-10 修复：统一 GroupBox 样式组件
//

import SwiftUI

/// 卡片容器组件
///
/// ## 功能特性
/// - 封装 `GroupBox` + `SectionHeader` 的常见模式
/// - 统一的内边距和样式
/// - 支持可选的标题/图标
/// - 消除 29 处重复代码
///
/// ## 设计说明
///
/// ### 问题背景（P2-10）
/// - 项目中存在 29 处重复的 `GroupBox` 样式配置
/// - 每处都手动配置 `VStack`、`padding()`、`SectionHeader`
/// - 维护成本高：修改样式需要同时修改 29 处
///
/// ### 解决方案
/// - 创建 `CardView` 组件封装常见模式
/// - 使用 `@ViewBuilder` 支持灵活的内容布局
/// - 保持向后兼容（可选标题参数）
///
/// ## 使用示例
///
/// ```swift
/// // 基础用法（带标题）
/// CardView(title: "当前网络状态", icon: "wifi", iconColor: .blue) {
///     VStack(spacing: 12) {
///         InfoRow(label: "网关 IP", value: "192.168.1.1")
///         InfoRow(label: "网关 MAC", value: "00:11:22:33:44:55")
///     }
/// }
///
/// // 无标题卡片
/// CardView {
///     Text("简单内容")
/// }
///
/// // 自定义图标颜色
/// CardView(title: "场景配置", icon: "network", iconColor: .purple) {
///     // 内容
/// }
/// ```
///
/// ## 迁移指南
///
/// ### 迁移前
/// ```swift
/// GroupBox {
///     VStack(alignment: .leading, spacing: 12) {
///         InfoRow(label: "网关 IP", value: networkMonitor.currentRouterIP)
///         InfoRow(label: "网关 MAC", value: networkMonitor.currentRouterMAC)
///     }
///     .padding()
/// } label: {
///     SectionHeader(title: "当前网络状态", icon: "wifi", iconColor: .blue)
/// }
/// ```
///
/// ### 迁移后
/// ```swift
/// CardView(title: "当前网络状态", icon: "wifi", iconColor: .blue) {
///     VStack(alignment: .leading, spacing: 12) {
///         InfoRow(label: "网关 IP", value: networkMonitor.currentRouterIP)
///         InfoRow(label: "网关 MAC", value: networkMonitor.currentRouterMAC)
///     }
/// }
/// ```
///
/// ## 最佳实践
///
/// 1. **内容布局**：内容已自动添加 `.padding()`，无需在 VStack 外部重复
/// 2. **对齐方式**：如需特定对齐，在 VStack 中指定 `alignment`
/// 3. **间距控制**：使用 VStack 的 `spacing` 参数控制元素间距
/// 4. **无标题场景**：标题参数可选，省略时显示纯卡片
struct CardView<Content: View>: View {

    // MARK: - Properties

    /// 卡片标题（可选）
    let title: String?

    /// 图标名称（可选，SF Symbol 名称）
    let icon: String?

    /// 图标颜色（可选，默认蓝色）
    let iconColor: Color?

    /// 卡片内容
    @ViewBuilder let content: () -> Content

    // MARK: - Initializers

    /// 完整初始化器（带标题和图标）
    ///
    /// - Parameters:
    ///   - title: 卡片标题
    ///   - icon: SF Symbol 图标名称
    ///   - iconColor: 图标颜色（默认蓝色）
    ///   - content: 卡片内容
    init(
        title: String,
        icon: String,
        iconColor: Color = .blue,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.icon = icon
        self.iconColor = iconColor
        self.content = content
    }

    /// 简化初始化器（无标题）
    ///
    /// - Parameter content: 卡片内容
    init(@ViewBuilder content: @escaping () -> Content) where Content: View {
        self.title = nil
        self.icon = nil
        self.iconColor = nil
        self.content = content
    }

    // MARK: - Body

    var body: some View {
        GroupBox {
            content()
                .padding()
        } label: {
            if let title = title {
                SectionHeader(
                    title: title,
                    icon: icon ?? "",
                    iconColor: iconColor ?? .blue
                )
            } else {
                EmptyView()
            }
        }
    }
}

// MARK: - Previews

#Preview("基础用法") {
    VStack(spacing: 16) {
        CardView(title: "当前网络状态", icon: "wifi", iconColor: .blue) {
            VStack(alignment: .leading, spacing: 12) {
                InfoRow(label: "网关 IP", value: "192.168.1.1")
                InfoRow(label: "网关 MAC", value: "00:11:22:33:44:55")
                InfoRow(label: "DNS 服务器", value: "8.8.8.8")
            }
        }

        CardView(title: "场景配置", icon: "network", iconColor: .purple) {
            VStack(alignment: .leading, spacing: 8) {
                Text("家庭网络")
                    .font(.headline)
                Text("路由器: 192.168.1.1")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
    .padding()
    .frame(width: 500)
}

#Preview("无标题卡片") {
    VStack(spacing: 16) {
        CardView {
            Text("简单内容，无标题")
                .font(.body)
        }

        CardView {
            VStack(spacing: 8) {
                Text("多行内容")
                    .font(.headline)
                Divider()
                Text("第二行")
                    .foregroundStyle(.secondary)
            }
        }
    }
    .padding()
    .frame(width: 400)
}

#Preview("混合场景") {
    ScrollView {
        VStack(spacing: 20) {
            CardView(title: "IP 质量检测", icon: "checkmark.shield", iconColor: .green) {
                VStack(alignment: .leading, spacing: 12) {
                    InfoRow(label: "IP 地址", value: "8.8.8.8")
                    InfoRow(label: "IP 类型", value: "数据中心", valueColor: .orange)
                    InfoRow(label: "地理位置", value: "北京, 中国")
                    InfoRow(label: "运营商", value: "中国电信")

                    Divider()

                    InfoRow(label: "端口 25", value: "开放", valueColor: .green)
                    InfoRow(label: "端口 80", value: "开放", valueColor: .green)
                    InfoRow(label: "端口 443", value: "关闭", valueColor: .red)
                }
            }

            CardView(title: "DNS 测试结果", icon: "timer", iconColor: .orange) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("223.5.5.5")
                            .font(.system(.body, design: .monospaced))
                        Spacer()
                        Text("12 ms")
                            .foregroundStyle(.green)
                    }

                    HStack {
                        Text("8.8.8.8")
                            .font(.system(.body, design: .monospaced))
                        Spacer()
                        Text("45 ms")
                            .foregroundStyle(.orange)
                    }
                }
            }

            CardView {
                VStack(spacing: 12) {
                    Text("无标题卡片示例")
                        .font(.headline)
                    Text("用于不需要明确分组标题的场景")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
    }
    .frame(width: 500, height: 700)
}
