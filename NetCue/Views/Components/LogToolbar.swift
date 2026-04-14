//
//  LogToolbar.swift
//  NetCue
//
//  Created by SlippinDylan on 2025/12/31.
//

import SwiftUI

/// 日志工具栏（搜索/筛选卡片）
///
/// 提供以下功能：
/// - 按级别过滤（纯文字）
/// - 内容搜索
/// - 时间范围筛选（预设 + 自定义）
/// - 清空/导出操作
struct LogToolbar: View {
    // MARK: - Bindings

    @Binding var searchText: String
    @Binding var selectedLevel: LogLevel?

    // MARK: - Callbacks

    let onClear: () -> Void
    let onExport: () -> Void

    // MARK: - Body

    var body: some View {
        GroupBox {
            HStack(spacing: 12) {
                // 级别筛选（平铺显示所有选项）
                Picker("", selection: $selectedLevel) {
                    Text("全部").tag(nil as LogLevel?)
                    ForEach(LogLevel.allCases, id: \.self) { level in
                        Text(level.displayName).tag(level as LogLevel?)
                    }
                }
                .pickerStyle(.segmented)
                .help("按日志级别过滤")

                // 内容搜索
                HStack(spacing: 4) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                        .imageScale(DesignSystem.IconScale.small)

                    TextField("搜索内容...", text: $searchText)
                        .textFieldStyle(.plain)
                        .frame(width: 200)

                    if !searchText.isEmpty {
                        Button(action: {
                            searchText = ""
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                                .imageScale(DesignSystem.IconScale.small)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
                .overlay(
                    RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium)
                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                )

                Spacer()

                // 操作按钮（最右侧）
                HStack(spacing: 8) {
                    Button("清空") {
                        onClear()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .controlSize(.small)
                    .help("清空所有日志")

                    Button("导出") {
                        onExport()
                    }
                    .adaptiveGlassProminentButtonStyle()
                    .controlSize(.small)
                    .help("导出日志到文件")
                }
            }
            .padding(12)
        }
    }
}
