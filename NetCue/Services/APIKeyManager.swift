//
//  APIKeyManager.swift
//  NetCue
//
//  Created by SlippinDylan on 2025/12/29.
//  Refactored on 2026/01/07 - 统一 API Key 管理
//
//  ## 设计理念
//  - 有免费 API 的数据源：未配置时使用免费 API，配置后使用付费 API
//  - 纯付费数据源：未配置时跳过，配置后启用
//

import Foundation
import Observation

/// API 密钥管理器
///
/// ## 数据源分类
/// ### 有免费 API（配置 Key 后使用付费版获取更多数据）
/// - IPinfo: 50k/月免费，付费版数据更全
/// - ipapi.is: 1000/天免费，付费版无限制
/// - DB-IP: 免费版基础数据，付费版完整数据
/// - IPWHOIS: 10k/月免费，付费版无限制
///
/// ### 纯付费数据源
/// - AbuseIPDB: 需要 API Key
/// - IP2Location: 需要 API Key
/// - ipregistry: 需要 API Key
@MainActor
@Observable
final class APIKeyManager {
    static let shared = APIKeyManager()

    // MARK: - API Keys (有免费 API 的数据源)

    /// IPinfo Token
    var ipinfoToken: String = ""

    /// ipapi.is API Key
    var ipapiKey: String = ""

    /// DB-IP API Key
    var dbipKey: String = ""

    /// IPWHOIS API Key
    var ipwhoisKey: String = ""

    // MARK: - API Keys (纯付费数据源)

    /// AbuseIPDB API Key
    var abuseipdbKey: String = ""

    /// IP2Location API Key
    var ip2locationKey: String = ""

    /// ipregistry API Key
    var ipregistryKey: String = ""

    // MARK: - UserDefaults Keys

    private enum Keys {
        static let ipinfoToken = "api_key_ipinfo"
        static let ipapiKey = "api_key_ipapi"
        static let dbipKey = "api_key_dbip"
        static let ipwhoisKey = "api_key_ipwhois"
        static let abuseipdbKey = "api_key_abuseipdb"
        static let ip2locationKey = "api_key_ip2location"
        static let ipregistryKey = "api_key_ipregistry"
    }

    // MARK: - Computed Properties (有免费 API 的数据源)

    /// IPinfo Token 是否已配置
    var hasIPinfoToken: Bool { !ipinfoToken.trimmingCharacters(in: .whitespaces).isEmpty }

    /// ipapi.is Key 是否已配置
    var hasIPAPIKey: Bool { !ipapiKey.trimmingCharacters(in: .whitespaces).isEmpty }

    /// DB-IP Key 是否已配置
    var hasDBIPKey: Bool { !dbipKey.trimmingCharacters(in: .whitespaces).isEmpty }

    /// IPWHOIS Key 是否已配置
    var hasIPWHOISKey: Bool { !ipwhoisKey.trimmingCharacters(in: .whitespaces).isEmpty }

    // MARK: - Computed Properties (纯付费数据源)

    /// AbuseIPDB Key 是否已配置
    var hasAbuseIPDBKey: Bool { !abuseipdbKey.trimmingCharacters(in: .whitespaces).isEmpty }

    /// IP2Location Key 是否已配置
    var hasIP2LocationKey: Bool { !ip2locationKey.trimmingCharacters(in: .whitespaces).isEmpty }

    /// ipregistry Key 是否已配置
    var hasIPRegistryKey: Bool { !ipregistryKey.trimmingCharacters(in: .whitespaces).isEmpty }

    // MARK: - Statistics

    /// 是否配置了任意一个 API Key
    var hasAnyAPIKey: Bool {
        hasIPinfoToken || hasIPAPIKey || hasDBIPKey || hasIPWHOISKey ||
        hasAbuseIPDBKey || hasIP2LocationKey || hasIPRegistryKey
    }

    /// 已配置的 API Key 数量
    var configuredKeyCount: Int {
        [hasIPinfoToken, hasIPAPIKey, hasDBIPKey, hasIPWHOISKey,
         hasAbuseIPDBKey, hasIP2LocationKey, hasIPRegistryKey].filter { $0 }.count
    }

    /// 总数据源数量
    /// - 4 个有免费 API 的数据源始终可用
    /// - 3 个纯付费数据源按配置启用
    var totalEnabledSourceCount: Int {
        let freeSourceCount = 4  // IPinfo, ipapi.is, DB-IP, IPWHOIS 始终有免费版
        let paidSourceCount = [hasAbuseIPDBKey, hasIP2LocationKey, hasIPRegistryKey].filter { $0 }.count
        return freeSourceCount + paidSourceCount
    }

    // MARK: - Initialization

    private init() {
        loadAPIKeys()
    }

    // MARK: - Persistence

    /// 加载 API Keys
    func loadAPIKeys() {
        AppLogger.debug("加载 API Keys")

        ipinfoToken = UserDefaults.standard.string(forKey: Keys.ipinfoToken) ?? ""
        ipapiKey = UserDefaults.standard.string(forKey: Keys.ipapiKey) ?? ""
        dbipKey = UserDefaults.standard.string(forKey: Keys.dbipKey) ?? ""
        ipwhoisKey = UserDefaults.standard.string(forKey: Keys.ipwhoisKey) ?? ""
        abuseipdbKey = UserDefaults.standard.string(forKey: Keys.abuseipdbKey) ?? ""
        ip2locationKey = UserDefaults.standard.string(forKey: Keys.ip2locationKey) ?? ""
        ipregistryKey = UserDefaults.standard.string(forKey: Keys.ipregistryKey) ?? ""

        AppLogger.info("API Keys 加载完成: \(configuredKeyCount) 个已配置")
    }

    /// 保存 API Keys
    func saveAPIKeys() {
        AppLogger.debug("保存 API Keys")

        UserDefaults.standard.set(ipinfoToken.trimmingCharacters(in: .whitespaces), forKey: Keys.ipinfoToken)
        UserDefaults.standard.set(ipapiKey.trimmingCharacters(in: .whitespaces), forKey: Keys.ipapiKey)
        UserDefaults.standard.set(dbipKey.trimmingCharacters(in: .whitespaces), forKey: Keys.dbipKey)
        UserDefaults.standard.set(ipwhoisKey.trimmingCharacters(in: .whitespaces), forKey: Keys.ipwhoisKey)
        UserDefaults.standard.set(abuseipdbKey.trimmingCharacters(in: .whitespaces), forKey: Keys.abuseipdbKey)
        UserDefaults.standard.set(ip2locationKey.trimmingCharacters(in: .whitespaces), forKey: Keys.ip2locationKey)
        UserDefaults.standard.set(ipregistryKey.trimmingCharacters(in: .whitespaces), forKey: Keys.ipregistryKey)

        AppLogger.info("API Keys 保存成功: \(configuredKeyCount) 个已配置")
    }

    /// 清除所有 API Keys
    func clearAllAPIKeys() {
        AppLogger.debug("清除所有 API Keys")

        ipinfoToken = ""
        ipapiKey = ""
        dbipKey = ""
        ipwhoisKey = ""
        abuseipdbKey = ""
        ip2locationKey = ""
        ipregistryKey = ""

        saveAPIKeys()
        AppLogger.info("所有 API Keys 已清除")
    }
}
