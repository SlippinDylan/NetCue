//
//  SettingsExportService.swift
//  NetCue
//
//  Created by Claude on 2026/01/09.
//
//  ## 设计说明
//  - 100% 原生 API 实现（NSSavePanel / NSOpenPanel / JSONEncoder）
//  - 无 Shell 调用
//  - 完整的错误处理
//

import Foundation
import AppKit
import UniformTypeIdentifiers

/// 设置导出/导入服务
///
/// ## 功能
/// - 导出当前所有配置到 .netcue 文件
/// - 从 .netcue 文件导入配置
///
/// ## 技术实现
/// - 文件格式：JSON（内部） + .netcue（扩展名）
/// - 对话框：NSSavePanel / NSOpenPanel（100% 原生）
/// - 编解码：JSONEncoder / JSONDecoder
@MainActor
final class SettingsExportService {

    // MARK: - Singleton

    static let shared = SettingsExportService()

    private init() {}

    // MARK: - Constants

    /// 文件扩展名
    private static let fileExtension = "netcue"

    /// 文件名前缀
    private static let fileNamePrefix = "NetCue_Settings"

    // MARK: - Export

    /// 导出设置到用户选择的位置
    ///
    /// ## 流程
    /// 1. 收集当前所有配置
    /// 2. 显示 NSSavePanel 让用户选择保存位置
    /// 3. 序列化为 JSON 并写入文件
    ///
    /// - Returns: 导出结果
    func exportSettings() async -> ExportResult {
        AppLogger.info("📤 开始导出设置")

        // 1. 收集当前配置
        let exportData = collectCurrentSettings()

        // 2. 显示保存对话框
        guard let saveURL = await showSavePanel() else {
            AppLogger.info("用户取消导出")
            return .cancelled
        }

        // 3. 序列化并写入文件
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601

            let jsonData = try encoder.encode(exportData)
            try jsonData.write(to: saveURL, options: .atomic)

            AppLogger.info("✅ 设置导出成功: \(saveURL.lastPathComponent)")
            return .success(url: saveURL)

        } catch {
            AppLogger.error("❌ 设置导出失败: \(error.localizedDescription)")
            return .failure(error: error)
        }
    }

    // MARK: - Import

    /// 从用户选择的文件导入设置
    ///
    /// ## 流程
    /// 1. 显示 NSOpenPanel 让用户选择文件
    /// 2. 读取并反序列化 JSON
    /// 3. 应用配置到各个存储
    ///
    /// - Returns: 导入结果
    func importSettings() async -> ImportResult {
        AppLogger.info("📥 开始导入设置")

        // 1. 显示打开对话框
        guard let openURL = await showOpenPanel() else {
            AppLogger.info("用户取消导入")
            return .cancelled
        }

        // 2. 读取并解析文件
        do {
            let jsonData = try Data(contentsOf: openURL)

            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601

            let importData = try decoder.decode(NetCueExportData.self, from: jsonData)

            // 3. 版本兼容性检查
            if importData.version > NetCueExportData.currentVersion {
                AppLogger.warning("⚠️ 导入文件版本较新: \(importData.version) > \(NetCueExportData.currentVersion)")
            }

            // 4. 应用配置
            applyImportedSettings(importData)

            AppLogger.info("✅ 设置导入成功: \(importData.appControlScenes.count) 个应用场景, \(importData.dnsControlScenes.count) 个 DNS 场景")
            return .success(data: importData)

        } catch {
            AppLogger.error("❌ 设置导入失败: \(error.localizedDescription)")
            return .failure(error: error)
        }
    }

    // MARK: - Private Methods - Data Collection

    /// 收集当前所有配置
    private func collectCurrentSettings() -> NetCueExportData {
        let appScenes = SceneStorage.loadScenes()
        let dnsScenes = DNSSceneStorage.shared.loadScenes()
        let apiKeys = APIKeyExportData(from: APIKeyManager.shared)

        AppLogger.debug("收集配置: \(appScenes.count) 个应用场景, \(dnsScenes.count) 个 DNS 场景")

        return NetCueExportData(
            appControlScenes: appScenes,
            dnsControlScenes: dnsScenes,
            apiKeys: apiKeys
        )
    }

    /// 应用导入的配置
    private func applyImportedSettings(_ data: NetCueExportData) {
        // 应用应用控制场景
        SceneStorage.saveScenes(data.appControlScenes)

        // 应用 DNS 控制场景
        DNSSceneStorage.shared.saveScenes(data.dnsControlScenes)

        // 应用 API Keys
        data.apiKeys.apply(to: APIKeyManager.shared)

        AppLogger.info("配置已应用")
    }

    // MARK: - Private Methods - Panels

    /// 显示保存对话框
    ///
    /// - Returns: 用户选择的保存 URL，取消则返回 nil
    private func showSavePanel() async -> URL? {
        let panel = NSSavePanel()

        // 配置对话框
        panel.title = "导出 NetCue 设置"
        panel.message = "选择保存位置"
        panel.nameFieldLabel = "文件名:"
        panel.nameFieldStringValue = generateFileName()
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.allowsOtherFileTypes = false

        // 设置允许的文件类型
        if let utType = UTType(filenameExtension: Self.fileExtension) {
            panel.allowedContentTypes = [utType]
        }

        // 显示对话框
        let response = await panel.begin()

        guard response == .OK else {
            return nil
        }

        return panel.url
    }

    /// 显示打开对话框
    ///
    /// - Returns: 用户选择的文件 URL，取消则返回 nil
    private func showOpenPanel() async -> URL? {
        let panel = NSOpenPanel()

        // 配置对话框
        panel.title = "导入 NetCue 设置"
        panel.message = "选择要导入的配置文件"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false

        // 设置允许的文件类型
        if let utType = UTType(filenameExtension: Self.fileExtension) {
            panel.allowedContentTypes = [utType]
        }

        // 显示对话框
        let response = await panel.begin()

        guard response == .OK else {
            return nil
        }

        return panel.url
    }

    // MARK: - Private Methods - Utilities

    /// 生成导出文件名
    ///
    /// 格式：NetCue_Settings_20260109_094532.netcue
    private func generateFileName() -> String {
        let timestamp = Date().formatted(
            Date.FormatStyle()
                .year(.defaultDigits)
                .month(.twoDigits)
                .day(.twoDigits)
                .hour(.twoDigits(amPM: .omitted))
                .minute(.twoDigits)
                .second(.twoDigits)
                .locale(Locale(identifier: "en_US_POSIX"))
        ).replacingOccurrences(of: "/", with: "")
         .replacingOccurrences(of: ":", with: "")
         .replacingOccurrences(of: ", ", with: "_")
         .replacingOccurrences(of: " ", with: "")
        return "\(Self.fileNamePrefix)_\(timestamp).\(Self.fileExtension)"
    }
}

// MARK: - Result Types

extension SettingsExportService {
    /// 导出结果
    enum ExportResult {
        case success(url: URL)
        case cancelled
        case failure(error: Error)

        var isSuccess: Bool {
            if case .success = self { return true }
            return false
        }
    }

    /// 导入结果
    enum ImportResult {
        case success(data: NetCueExportData)
        case cancelled
        case failure(error: Error)

        var isSuccess: Bool {
            if case .success = self { return true }
            return false
        }

        /// 获取导入的数据（仅成功时有值）
        var importedData: NetCueExportData? {
            if case .success(let data) = self { return data }
            return nil
        }
    }
}
