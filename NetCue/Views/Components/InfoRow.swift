//
//  InfoRow.swift
//  NetCue
//
//  Created by SlippinDylan on 2026/01/06.
//  Extracted from NetworkMonitorView.swift - P1-8 修复
//

import SwiftUI

/// 信息行组件 - 用于展示键值对信息
///
/// ## 功能特性
/// - 支持自定义值颜色（用于状态显示）
/// - 默认启用文本选择（支持复制）
/// - 响应式布局（自动适配宽度）
///
/// ## 使用示例
/// ```swift
/// // 基础用法
/// InfoRow(label: "IP 地址", value: "8.8.8.8")
///
/// // 状态显示（带颜色）
/// InfoRow(label: "端口 25", value: "开放", valueColor: .green)
/// InfoRow(label: "端口 465", value: "关闭", valueColor: .red)
///
/// // 组合使用
/// VStack(spacing: 12) {
///     InfoRow(label: "ASN", value: "AS15169")
///     InfoRow(label: "组织", value: "Google LLC")
///     InfoRow(label: "城市", value: "Mountain View")
/// }
/// ```
///
/// ## 设计规范
/// - 标签：`.secondary` 颜色，左对齐
/// - 值：`.medium` 字重，右对齐，可自定义颜色
/// - 间距：使用 `Spacer()` 自动填充
/// - 文本选择：默认启用（`.textSelection(.enabled)`）
struct InfoRow: View {
    // MARK: - Properties

    /// 标签文本（左侧）
    let label: String

    /// 值文本（右侧）
    let value: String

    /// 值的颜色（默认为 primary）
    ///
    /// ## 使用场景
    /// - `.green`：正常状态（如端口开放、服务可用）
    /// - `.red`：异常状态（如端口关闭、服务不可用）
    /// - `.orange`：警告状态（如性能下降、部分可用）
    /// - `.primary`：中性信息（如 IP 地址、城市名称）
    var valueColor: Color = .primary

    // MARK: - Body

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)

            Spacer()

            Text(value)
                .fontWeight(.medium)
                .foregroundStyle(valueColor)
                .textSelection(.enabled)
        }
    }
}

// MARK: - Previews

#Preview("基础用法") {
    VStack(spacing: 12) {
        InfoRow(label: "IP 地址", value: "8.8.8.8")
        InfoRow(label: "ASN", value: "AS15169")
        InfoRow(label: "组织", value: "Google LLC")
        InfoRow(label: "城市", value: "Mountain View")
        InfoRow(label: "时区", value: "UTC-8")
    }
    .padding()
    .frame(width: 400)
}

#Preview("状态显示") {
    GroupBox {
        VStack(spacing: 12) {
            InfoRow(label: "端口 25", value: "开放", valueColor: .green)
            Divider()
            InfoRow(label: "端口 465", value: "关闭", valueColor: .red)
            Divider()
            InfoRow(label: "SMTP 连通性", value: "部分可用", valueColor: .orange)
        }
        .padding()
    } label: {
        Text("服务状态")
            .font(.headline)
    }
    .padding()
    .frame(width: 400)
}

#Preview("混合场景") {
    GroupBox {
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
        .padding()
    } label: {
        Text("IP 质量检测")
            .font(.headline)
    }
    .padding()
    .frame(width: 450)
}
