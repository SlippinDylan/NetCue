//
//  LogView.swift
//  NetCue
//
//  Created by SlippinDylan on 2025/12/31.
//

import SwiftUI
import UniformTypeIdentifiers

/// 日志查看器主界面
///
/// 集成了：
/// - LogToolbar：搜索/筛选卡片（无标题）
/// - LogTextView：日志文本显示（NSTextView，卡片包裹）
/// - 底部统计信息
/// - LogStore：日志数据源
struct LogView: View {
    // MARK: - State Objects

    @State private var logStore = LogStore.shared

    // MARK: - State

    @State private var searchText = ""
    @State private var selectedLevel: LogLevel?
    @State private var showingExportPanel = false

    // MARK: - Computed Properties

    /// 应用所有筛选条件后的日志
    private var filteredLogs: [LogEntry] {
        var result = logStore.entries

        // 按级别过滤
        if let selectedLevel = selectedLevel {
            result = result.filter { $0.level >= selectedLevel }
        }

        // 按关键词搜索
        if !searchText.isEmpty {
            let keyword = searchText.lowercased()
            result = result.filter { entry in
                entry.message.lowercased().contains(keyword) ||
                entry.file.lowercased().contains(keyword) ||
                entry.function.lowercased().contains(keyword)
            }
        }

        return result
    }

    /// 统计信息
    private var statistics: String {
        let counts = Dictionary(grouping: filteredLogs, by: { $0.level })
            .mapValues { $0.count }

        var parts: [String] = ["共 \(filteredLogs.count) 条"]

        // 只显示有数据的级别
        for level in LogLevel.allCases {
            if let count = counts[level], count > 0 {
                parts.append("\(level.displayName):\(count)")
            }
        }

        return parts.joined(separator: " | ")
    }

    // MARK: - Body

    var body: some View {
        NetCueScrollView {
            VStack(spacing: 0) {
                // 搜索/筛选工具栏（卡片，无标题）
                LogToolbar(
                    searchText: $searchText,
                    selectedLevel: $selectedLevel,
                    onClear: clearLogs,
                    onExport: exportLogs
                )
                .padding(.horizontal, DesignSystem.Spacing.standard)
                .padding(.top, DesignSystem.Spacing.standard)

                // 日志内容卡片（无标题）
                GroupBox {
                    VStack(spacing: 0) {
                        // 日志内容区域
                        if filteredLogs.isEmpty {
                            emptyStateView
                        } else {
                            LogTextView(
                                entries: filteredLogs,
                                autoScroll: false // 移除自动滚动
                            )
                            .frame(minHeight: 500, maxHeight: .infinity)
                        }

                        // 底部统计信息
                        if !filteredLogs.isEmpty {
                            Divider()

                            HStack {
                                Text(statistics)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                Spacer()
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                        }
                    }
                }
                .padding(.horizontal, DesignSystem.Spacing.standard)
                .padding(.top, DesignSystem.Spacing.standard)
            }
        }
        .fileExporter(
            isPresented: $showingExportPanel,
            document: LogDocument(logs: logStore.entries),
            contentType: .plainText,
            defaultFilename: defaultExportFilename
        ) { result in
            switch result {
            case .success(let url):
                AppLogger.info("日志已导出到: \(url.path)")
            case .failure(let error):
                AppLogger.error("导出日志失败", error: error)
            }
        }
    }

    // MARK: - Empty State View

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                Text("暂无日志")
                    .font(.title3)
                    .fontWeight(.medium)

                if !searchText.isEmpty || selectedLevel != nil {
                    Text("未找到匹配的日志，请尝试其他筛选条件")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Button("清除筛选条件") {
                        searchText = ""
                        selectedLevel = nil
                    }
                    .adaptiveGlassProminentButtonStyle()
                    .controlSize(.small)
                } else {
                    Text("应用运行时产生的日志将在此显示")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .frame(minHeight: 400)
    }

    // MARK: - Actions

    private func clearLogs() {
        logStore.clear()
        AppLogger.info("日志已清空")
    }

    private func exportLogs() {
        showingExportPanel = true
    }

    private var defaultExportFilename: String {
        let timestamp = Date().formatted(
            .dateTime
            .year().month().day()
            .hour().minute().second()
            .locale(Locale(identifier: "en_US_POSIX"))
        ).replacingOccurrences(of: "/", with: "-")
         .replacingOccurrences(of: ":", with: "-")
         .replacingOccurrences(of: ", ", with: "_")
         .replacingOccurrences(of: " ", with: "_")
        return "NetCue_Logs_\(timestamp).txt"
    }
}

// MARK: - Log Document (for FileExporter)

struct LogDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.plainText] }

    let logs: [LogEntry]

    init(logs: [LogEntry]) {
        self.logs = logs
    }

    init(configuration: ReadConfiguration) throws {
        self.logs = []
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let content = logs.map { $0.plainTextString }.joined(separator: "\n")
        let data = content.data(using: .utf8) ?? Data()
        return FileWrapper(regularFileWithContents: data)
    }
}

// MARK: - Preview

#Preview {
    LogView()
}
