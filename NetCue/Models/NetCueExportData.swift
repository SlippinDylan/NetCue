//
//  NetCueExportData.swift
//  NetCue
//
//  Created by Claude on 2026/01/09.
//
//  ## 设计说明
//  - 统一的配置导出数据结构
//  - 包含版本号便于未来兼容性处理
//  - 所有字段均支持 Codable 序列化
//

import Foundation

/// NetCue 配置导出数据结构
///
/// ## 包含内容
/// - 应用控制场景 (NetworkScene)
/// - DNS 控制场景 (DNSScene)
/// - API Key 配置
///
/// ## 文件格式
/// - 内部格式：JSON
/// - 文件扩展名：.netcue
struct NetCueExportData: Codable {
    // MARK: - Metadata

    /// 导出格式版本（便于未来兼容性处理）
    let version: Int

    /// 导出时间
    let exportedAt: Date

    /// 应用标识
    let appName: String

    /// 应用版本
    let appVersion: String

    // MARK: - Scene Data

    /// 应用控制场景列表
    let appControlScenes: [NetworkScene]

    /// DNS 控制场景列表
    let dnsControlScenes: [DNSScene]

    // MARK: - API Keys

    /// API Key 配置
    let apiKeys: APIKeyExportData

    // MARK: - Initialization

    /// 创建导出数据（使用当前配置）
    ///
    /// - Parameters:
    ///   - appControlScenes: 应用控制场景列表
    ///   - dnsControlScenes: DNS 控制场景列表
    ///   - apiKeys: API Key 配置
    init(
        appControlScenes: [NetworkScene],
        dnsControlScenes: [DNSScene],
        apiKeys: APIKeyExportData
    ) {
        self.version = Self.currentVersion
        self.exportedAt = Date()
        self.appName = "NetCue"
        self.appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
        self.appControlScenes = appControlScenes
        self.dnsControlScenes = dnsControlScenes
        self.apiKeys = apiKeys
    }

    // MARK: - Version

    /// 当前导出格式版本
    static let currentVersion = 1
}

// MARK: - API Key Export Data

/// API Key 导出数据结构
struct APIKeyExportData: Codable {
    // MARK: - 有免费 API 的数据源

    /// IPinfo Token
    let ipinfoToken: String

    /// ipapi.is API Key
    let ipapiKey: String

    /// DB-IP API Key
    let dbipKey: String

    /// IPWHOIS API Key
    let ipwhoisKey: String

    // MARK: - 纯付费数据源

    /// AbuseIPDB API Key
    let abuseipdbKey: String

    /// IP2Location API Key
    let ip2locationKey: String

    /// ipregistry API Key
    let ipregistryKey: String

    // MARK: - Convenience Initializer

    /// 从 APIKeyManager 创建导出数据
    @MainActor
    init(from manager: APIKeyManager) {
        self.ipinfoToken = manager.ipinfoToken
        self.ipapiKey = manager.ipapiKey
        self.dbipKey = manager.dbipKey
        self.ipwhoisKey = manager.ipwhoisKey
        self.abuseipdbKey = manager.abuseipdbKey
        self.ip2locationKey = manager.ip2locationKey
        self.ipregistryKey = manager.ipregistryKey
    }

    /// 应用到 APIKeyManager
    @MainActor
    func apply(to manager: APIKeyManager) {
        manager.ipinfoToken = ipinfoToken
        manager.ipapiKey = ipapiKey
        manager.dbipKey = dbipKey
        manager.ipwhoisKey = ipwhoisKey
        manager.abuseipdbKey = abuseipdbKey
        manager.ip2locationKey = ip2locationKey
        manager.ipregistryKey = ipregistryKey
        manager.saveAPIKeys()
    }
}
