//
//  IPQualityCardCompletedView.swift
//  NetCue
//
//  Created by SlippinDylan on 2026/01/07.
//  网络工具 - IP质量卡片 - 完成状态
//
//  ## 2026/01/08 重构
//  - 恢复表格布局（风险因子、流媒体、评分对比）
//  - 新增通用 DataTable 组件，支持泛型数据和声明式列定义
//  - 新增 BoolIndicator 组件，替代原 BoolIconView
//

import SwiftUI

// MARK: - IP Quality Card Completed View

/// 网络工具卡片 - 完成状态视图
///
/// ## 设计说明
/// - 使用表格布局展示多数据源对比信息
/// - 通用 DataTable 组件实现表格复用
/// - 布局适配 GroupBox 环境（不使用 ScrollView，避免嵌套）
struct IPQualityCardCompletedView: View {
    // MARK: - Properties

    let result: IPQualityResult
    let onRetest: () -> Void

    // MARK: - Body

    var body: some View {
        VStack(spacing: DesignSystem.Spacing.standard) {
            // 顶部按钮 + 检测时间
            headerSection

            // 风险评分大卡片
            riskScoreBigCard

            // 基础信息卡片
            basicInfoCard

            // IP类型属性卡片（表格）
            if let multiSource = result.multiSourceData, !multiSource.ipTypes.isEmpty {
                ipTypeTableCard(ipTypes: multiSource.ipTypes)
            }

            // 风险评分对比卡片（表格）
            if let multiSource = result.multiSourceData, !multiSource.riskScores.isEmpty {
                riskScoreTableCard(riskScores: multiSource.riskScores)
            }

            // 风险因子对比卡片（表格）
            if let multiSource = result.multiSourceData, !multiSource.riskFactors.isEmpty {
                riskFactorsTableCard(riskFactors: multiSource.riskFactors)
            }

            // 流媒体解锁卡片（表格）
            streamingServicesTableCard

            // 邮件服务卡片
            if let emailStatus = result.emailStatus {
                emailServiceCard(emailStatus: emailStatus)
            }

            Spacer(minLength: 20)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Header Section

    private var headerSection: some View {
        HStack {
            Spacer()
            Button(action: onRetest) {
                Label("重新检测", systemImage: "arrow.clockwise")
            }
            .adaptiveGlassProminentButtonStyle()
            Text(formattedDate(result.detectedAt))
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    // MARK: - Risk Score Big Card

    /// 风险评分大卡片（保持原有设计）
    private var riskScoreBigCard: some View {
        GroupBox {
            VStack(spacing: 12) {
                Text("风险评分")
                    .font(.headline)
                    .foregroundStyle(.secondary)

                Text("\(result.riskScore)")
                    .font(.system(size: 72, weight: .bold))
                    .foregroundStyle(riskLevelColor)

                Text(result.riskLevel.displayName)
                    .font(.title3)
                    .fontWeight(.medium)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .background(riskLevelColor.opacity(0.2))
                    .foregroundStyle(riskLevelColor)
                    .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
        }
    }

    private var riskLevelColor: Color {
        switch result.riskLevel {
        case .veryLow, .low:
            return .green
        case .medium:
            return .orange
        case .high, .veryHigh:
            return .red
        }
    }

    // MARK: - Basic Info Card

    /// 基础信息卡片（键值对布局）
    private var basicInfoCard: some View {
        GroupBox {
            VStack(spacing: 12) {
                InfoRow(label: "IP 地址", value: result.ip)
                InfoRow(label: "IP 版本", value: "IPv\(result.ipVersion)")
                if let asn = result.asn {
                    InfoRow(label: "ASN", value: asn)
                }
                if let org = result.organization {
                    InfoRow(label: "组织", value: org)
                }
                InfoRow(label: "IP 类型", value: result.ipType.displayName)
                if let country = result.country {
                    InfoRow(label: "国家", value: country)
                }
                if let city = result.city {
                    InfoRow(label: "城市", value: city)
                }
                if let timezone = result.timezone {
                    InfoRow(label: "时区", value: timezone)
                }
            }
            .padding()
        } label: {
            Label("基础信息", systemImage: "info.circle.fill")
                .foregroundStyle(.blue)
        }
    }

    // MARK: - IP Type Table Card

    /// IP 类型对比卡片（表格布局）
    private func ipTypeTableCard(ipTypes: [DataSourceIPType]) -> some View {
        GroupBox {
            DataTable(
                data: ipTypes,
                columns: [
                    TableColumn(title: "数据源", width: .flexible) { item in
                        AnyView(
                            Text(item.source)
                                .font(.system(size: 13))
                        )
                    },
                    TableColumn(title: "使用类型", width: .flexible) { item in
                        AnyView(
                            Text(item.usageType ?? "-")
                                .font(.system(size: 13))
                        )
                    },
                    TableColumn(title: "公司类型", width: .flexible) { item in
                        AnyView(
                            Text(item.companyType ?? "-")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                        )
                    }
                ]
            )
            .padding()
        } label: {
            Label("IP 类型对比", systemImage: "network")
                .foregroundStyle(.purple)
        }
    }

    // MARK: - Risk Score Table Card

    /// 风险评分对比卡片（表格布局）
    private func riskScoreTableCard(riskScores: [DataSourceRiskScore]) -> some View {
        GroupBox {
            DataTable(
                data: riskScores,
                columns: [
                    TableColumn(title: "数据源", width: .fixed(120)) { item in
                        AnyView(
                            Text(item.source)
                                .font(.system(size: 13))
                        )
                    },
                    TableColumn(title: "评分", width: .fixed(60)) { item in
                        AnyView(
                            Text("\(item.score)")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(scoreColor(item.score))
                        )
                    },
                    TableColumn(title: "等级", width: .flexible) { item in
                        AnyView(RiskLevelTag(level: item.level))
                    }
                ]
            )
            .padding()
        } label: {
            Label("风险评分对比", systemImage: "exclamationmark.shield.fill")
                .foregroundStyle(.orange)
        }
    }

    private func scoreColor(_ score: Int) -> Color {
        if score < 30 {
            return .green
        } else if score < 70 {
            return .orange
        } else {
            return .red
        }
    }

    // MARK: - Risk Factors Table Card

    /// 风险因子对比卡片（表格布局）
    private func riskFactorsTableCard(riskFactors: [DataSourceRiskFactors]) -> some View {
        GroupBox {
            DataTable(
                data: riskFactors,
                columns: [
                    TableColumn(title: "数据源", width: .flexible) { item in
                        AnyView(
                            Text(item.source)
                                .font(.system(size: 13))
                        )
                    },
                    TableColumn(title: "地区", width: .fixed(50)) { item in
                        AnyView(
                            Text(item.region.map { GeoUtils.countryFlag(countryCode: $0) } ?? "-")
                                .font(.system(size: 16))
                        )
                    },
                    TableColumn(title: "代理", width: .fixed(40)) { item in
                        AnyView(BoolIndicator(value: item.isProxy))
                    },
                    TableColumn(title: "Tor", width: .fixed(40)) { item in
                        AnyView(BoolIndicator(value: item.isTor))
                    },
                    TableColumn(title: "VPN", width: .fixed(40)) { item in
                        AnyView(BoolIndicator(value: item.isVPN))
                    },
                    TableColumn(title: "机房", width: .fixed(40)) { item in
                        AnyView(BoolIndicator(value: item.isDatacenter))
                    },
                    TableColumn(title: "滥用", width: .fixed(40)) { item in
                        AnyView(BoolIndicator(value: item.isAbuser))
                    },
                    TableColumn(title: "机器人", width: .fixed(50)) { item in
                        AnyView(BoolIndicator(value: item.isBot))
                    }
                ]
            )
            .padding()
        } label: {
            Label("风险因子对比", systemImage: "shield.checkered")
                .foregroundStyle(.red)
        }
    }

    // MARK: - Streaming Services Table Card

    /// 流媒体解锁卡片（表格布局）
    private var streamingServicesTableCard: some View {
        GroupBox {
            DataTable(
                data: streamingServices,
                columns: [
                    TableColumn(title: "服务商", width: .flexible) { item in
                        AnyView(
                            Text(item.name)
                                .font(.system(size: 13))
                        )
                    },
                    TableColumn(title: "状态", width: .flexible) { item in
                        AnyView(
                            Text(item.status)
                                .font(.system(size: 13))
                                .foregroundStyle(item.isAvailable ? .green : .red)
                        )
                    },
                    TableColumn(title: "地区", width: .fixed(50)) { item in
                        AnyView(
                            Text(item.regionFlag)
                                .font(.system(size: 16))
                        )
                    },
                    TableColumn(title: "方式", width: .flexible) { item in
                        AnyView(
                            Text(item.unlockType)
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                        )
                    }
                ]
            )
            .padding()
        } label: {
            Label("流媒体及 AI 服务解锁检测", systemImage: "play.circle.fill")
                .foregroundStyle(.purple)
        }
    }

    /// 流媒体服务数据
    private var streamingServices: [StreamingServiceRow] {
        var services: [StreamingServiceRow] = []

        if let tiktok = result.tiktok {
            services.append(StreamingServiceRow(
                name: "TikTok",
                status: tiktok.displayStatus,
                isAvailable: tiktok.available,
                regionFlag: tiktok.region.map { GeoUtils.countryFlag(countryCode: $0) } ?? "-",
                unlockType: tiktok.unlockType ?? "-"
            ))
        }
        if let disney = result.disney {
            services.append(StreamingServiceRow(
                name: "Disney+",
                status: disney.displayStatus,
                isAvailable: disney.available,
                regionFlag: disney.region.map { GeoUtils.countryFlag(countryCode: $0) } ?? "-",
                unlockType: disney.unlockType ?? "-"
            ))
        }
        if let netflix = result.netflix {
            services.append(StreamingServiceRow(
                name: "Netflix",
                status: netflix.displayStatus,
                isAvailable: netflix.available,
                regionFlag: netflix.region.map { GeoUtils.countryFlag(countryCode: $0) } ?? "-",
                unlockType: netflix.unlockType ?? "-"
            ))
        }
        if let youtube = result.youtube {
            services.append(StreamingServiceRow(
                name: "YouTube Premium",
                status: youtube.displayStatus,
                isAvailable: youtube.available,
                regionFlag: youtube.region.map { GeoUtils.countryFlag(countryCode: $0) } ?? "-",
                unlockType: youtube.unlockType ?? "-"
            ))
        }
        if let amazon = result.amazonPrime {
            services.append(StreamingServiceRow(
                name: "Amazon Prime",
                status: amazon.displayStatus,
                isAvailable: amazon.available,
                regionFlag: amazon.region.map { GeoUtils.countryFlag(countryCode: $0) } ?? "-",
                unlockType: amazon.unlockType ?? "-"
            ))
        }
        if let spotify = result.spotify {
            services.append(StreamingServiceRow(
                name: "Spotify",
                status: spotify.displayStatus,
                isAvailable: spotify.available,
                regionFlag: spotify.region.map { GeoUtils.countryFlag(countryCode: $0) } ?? "-",
                unlockType: spotify.unlockType ?? "-"
            ))
        }
        if let chatGPT = result.chatGPT {
            services.append(StreamingServiceRow(
                name: "ChatGPT",
                status: chatGPT.displayStatus,
                isAvailable: chatGPT.available,
                regionFlag: chatGPT.region.map { GeoUtils.countryFlag(countryCode: $0) } ?? "-",
                unlockType: chatGPT.unlockType ?? "-"
            ))
        }

        return services
    }

    // MARK: - Email Service Card

    /// 邮件服务卡片（简单布局，不需要表格）
    private func emailServiceCard(emailStatus: EmailStatus) -> some View {
        GroupBox {
            VStack(spacing: 12) {
                HStack {
                    Text("端口 25")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    HStack(spacing: 6) {
                        Image(systemName: emailStatus.port25Open ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(emailStatus.port25Open ? .green : .red)
                        Text(emailStatus.port25Open ? "开放" : "关闭")
                            .fontWeight(.medium)
                            .foregroundStyle(emailStatus.port25Open ? .green : .red)
                    }
                }

                Divider()

                HStack {
                    Text("SMTP 连接")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    HStack(spacing: 6) {
                        Image(systemName: emailStatus.smtpConnectable ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(emailStatus.smtpConnectable ? .green : .red)
                        Text(emailStatus.smtpConnectable ? "正常" : "无法连接")
                            .fontWeight(.medium)
                            .foregroundStyle(emailStatus.smtpConnectable ? .green : .red)
                    }
                }
            }
            .padding()
        } label: {
            Label("邮件服务", systemImage: "envelope.fill")
                .foregroundStyle(.blue)
        }
    }

    // MARK: - Helper Methods

    private func formattedDate(_ date: Date) -> String {
        return date.formatted(
            .dateTime
            .year()
            .month(.twoDigits)
            .day(.twoDigits)
            .hour(.twoDigits(amPM: .omitted))
            .minute(.twoDigits)
        )
    }
}

// MARK: - Streaming Service Row

/// 流媒体服务行数据模型
private struct StreamingServiceRow {
    let name: String
    let status: String
    let isAvailable: Bool
    let regionFlag: String
    let unlockType: String
}

// MARK: - Data Table Component

/// 通用数据表格组件
///
/// ## 设计说明
/// - 泛型设计，支持任意数据类型
/// - 声明式列定义（标题 + 宽度 + 内容渲染）
/// - 自动处理表头样式、斑马纹、分隔线
private struct DataTable<T>: View {
    let data: [T]
    let columns: [TableColumn<T>]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 表头
            headerRow

            Divider()

            // 数据行
            ForEach(Array(data.enumerated()), id: \.offset) { index, item in
                dataRow(item: item, index: index)

                if index < data.count - 1 {
                    Divider()
                }
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium)
                .stroke(Color(NSColor.separatorColor), lineWidth: 1)
        )
    }

    // MARK: - Header Row

    private var headerRow: some View {
        HStack(spacing: 0) {
            ForEach(Array(columns.enumerated()), id: \.offset) { index, column in
                Text(column.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: column.width.maxWidth, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)

                if index < columns.count - 1 {
                    Divider().frame(height: 20)
                }
            }
        }
        .background(Color(NSColor.controlBackgroundColor))
    }

    // MARK: - Data Row

    private func dataRow(item: T, index: Int) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(columns.enumerated()), id: \.offset) { colIndex, column in
                column.content(item)
                    .frame(maxWidth: column.width.maxWidth, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)

                if colIndex < columns.count - 1 {
                    Divider().frame(height: 20)
                }
            }
        }
        .background(index % 2 == 0 ? Color.clear : Color(NSColor.controlBackgroundColor).opacity(0.3))
    }
}

// MARK: - Table Column

/// 表格列定义
private struct TableColumn<T> {
    let title: String
    let width: ColumnWidth
    let content: (T) -> AnyView

    init(title: String, width: ColumnWidth = .flexible, content: @escaping (T) -> AnyView) {
        self.title = title
        self.width = width
        self.content = content
    }
}

/// 列宽度类型
private enum ColumnWidth {
    case fixed(CGFloat)
    case flexible

    var maxWidth: CGFloat? {
        switch self {
        case .fixed(let width):
            return width
        case .flexible:
            return .infinity
        }
    }
}

// MARK: - Bool Indicator

/// 布尔值指示器
///
/// ## 显示逻辑
/// - `true`（有风险）：红色 ✗
/// - `false`（无风险）：绿色 ✓
/// - `nil`（未知）：灰色 -
private struct BoolIndicator: View {
    let value: Bool?

    var body: some View {
        Group {
            if let value = value {
                Image(systemName: value ? "xmark.circle.fill" : "checkmark.circle.fill")
                    .foregroundStyle(value ? .red : .green)
            } else {
                Image(systemName: "minus.circle")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.system(size: 13))
    }
}

// MARK: - Risk Level Tag

/// 风险等级标签
private struct RiskLevelTag: View {
    let level: String

    var body: some View {
        Text(level)
            .font(.system(size: 11))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(tagColor.opacity(0.2))
            .foregroundStyle(tagColor)
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small))
    }

    private var tagColor: Color {
        let lowercased = level.lowercased()
        if lowercased.contains("low") || lowercased.contains("低") {
            return .green
        } else if lowercased.contains("medium") || lowercased.contains("中") {
            return .orange
        } else if lowercased.contains("high") || lowercased.contains("高") {
            return .red
        } else {
            return .secondary
        }
    }
}

// MARK: - Preview

#Preview {
    ScrollView {
        IPQualityCardCompletedView(
            result: IPQualityResult(),
            onRetest: {}
        )
        .padding()
    }
    .frame(width: 800, height: 600)
}
