//
//  IPDataSourceService.swift
//  NetCue
//
//  Created by SlippinDylan on 2025/12/29.
//  Refactored on 2026/01/07 - 统一免费/付费 API 逻辑
//
//  ## 设计理念
//  - 有免费 API 的数据源：优先使用付费 API（数据更全），未配置时使用免费 API
//  - 纯付费数据源：未配置 API Key 时跳过
//

import Foundation

/// IP 数据源服务
///
/// ## 数据源列表
/// ### 有免费 API（配置 Key 后使用付费版）
/// 1. IPinfo - 免费 widget API / 付费官方 API
/// 2. ipapi.is - 免费 1000/天 / 付费无限制
/// 3. DB-IP - 免费基础数据 / 付费完整数据
/// 4. IPWHOIS - 免费 10k/月 / 付费无限制
///
/// ### 纯付费数据源
/// 5. AbuseIPDB - 需要 API Key
/// 6. IP2Location - 需要 API Key
/// 7. ipregistry - 需要 API Key
final class IPDataSourceService: Sendable {

    // MARK: - Types

    /// 数据源类型
    enum DataSource: String, CaseIterable, Sendable {
        // 有免费 API 的数据源
        case ipinfo         // IPinfo
        case ipapi          // ipapi.is
        case dbip           // DB-IP
        case ipwhois        // IPWHOIS

        // 纯付费数据源
        case abuseipdb      // AbuseIPDB
        case ip2location    // IP2Location
        case ipregistry     // ipregistry

        var displayName: String {
            switch self {
            case .ipinfo: return "IPinfo"
            case .ipapi: return "ipapi.is"
            case .dbip: return "DB-IP"
            case .ipwhois: return "IPWHOIS"
            case .abuseipdb: return "AbuseIPDB"
            case .ip2location: return "IP2Location"
            case .ipregistry: return "ipregistry"
            }
        }

        /// 是否有免费 API
        var hasFreeAPI: Bool {
            switch self {
            case .ipinfo, .ipapi, .dbip, .ipwhois:
                return true
            case .abuseipdb, .ip2location, .ipregistry:
                return false
            }
        }
    }

    /// 数据源结果
    struct DataSourceResult: Sendable {
        let source: DataSource
        let ipType: DataSourceIPType?
        let riskScore: DataSourceRiskScore?
        let riskFactors: DataSourceRiskFactors?
        let error: Error?
        let skipped: Bool
        let usedPaidAPI: Bool  // 是否使用了付费 API

        var isSuccess: Bool { error == nil && !skipped }

        /// 创建跳过的结果（nonisolated 避免 actor 隔离问题）
        nonisolated static func skipped(source: DataSource) -> DataSourceResult {
            DataSourceResult(source: source, ipType: nil, riskScore: nil, riskFactors: nil,
                           error: nil, skipped: true, usedPaidAPI: false)
        }
    }

    // MARK: - Properties

    private let session: URLSession
    private let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
    private let timeout: TimeInterval = 15.0

    // MARK: - Initialization

    init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: - Request Helpers

    /// 创建带有标准浏览器请求头的 URLRequest
    private func createRequest(url: URL, referer: String? = nil) -> URLRequest {
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        request.setValue("gzip, deflate, br", forHTTPHeaderField: "Accept-Encoding")
        request.setValue("keep-alive", forHTTPHeaderField: "Connection")

        if let referer = referer {
            request.setValue(referer, forHTTPHeaderField: "Referer")
        }

        return request
    }

    // MARK: - Public API

    /// 并发获取所有数据源的数据
    @MainActor
    func fetchAllSources(ip: String, apiKeyManager: APIKeyManager) async -> [DataSourceResult] {
        AppLogger.debug("🔍 开始多数据源检测")

        return await withTaskGroup(of: DataSourceResult.self) { group in
            // ========== 有免费 API 的数据源 ==========

            // 1. IPinfo (优先付费 API，否则免费 widget)
            let ipinfoToken = apiKeyManager.hasIPinfoToken ? apiKeyManager.ipinfoToken : nil
            group.addTask {
                await self.fetchIPinfo(ip: ip, token: ipinfoToken)
            }

            // 2. ipapi.is (优先付费 API，否则免费 API)
            let ipapiKey = apiKeyManager.hasIPAPIKey ? apiKeyManager.ipapiKey : nil
            group.addTask {
                await self.fetchIPAPI(ip: ip, apiKey: ipapiKey)
            }

            // 3. DB-IP (优先付费 API，否则免费 API)
            let dbipKey = apiKeyManager.hasDBIPKey ? apiKeyManager.dbipKey : nil
            group.addTask {
                await self.fetchDBIP(ip: ip, apiKey: dbipKey)
            }

            // 4. IPWHOIS (优先付费 API，否则免费 API)
            let ipwhoisKey = apiKeyManager.hasIPWHOISKey ? apiKeyManager.ipwhoisKey : nil
            group.addTask {
                await self.fetchIPWHOIS(ip: ip, apiKey: ipwhoisKey)
            }

            // ========== 纯付费数据源 ==========

            // 5. AbuseIPDB
            if apiKeyManager.hasAbuseIPDBKey {
                let key = apiKeyManager.abuseipdbKey
                group.addTask {
                    await self.fetchAbuseIPDB(ip: ip, apiKey: key)
                }
            } else {
                group.addTask { .skipped(source: .abuseipdb) }
            }

            // 6. IP2Location
            if apiKeyManager.hasIP2LocationKey {
                let key = apiKeyManager.ip2locationKey
                group.addTask {
                    await self.fetchIP2Location(ip: ip, apiKey: key)
                }
            } else {
                group.addTask { .skipped(source: .ip2location) }
            }

            // 7. ipregistry
            if apiKeyManager.hasIPRegistryKey {
                let key = apiKeyManager.ipregistryKey
                group.addTask {
                    await self.fetchIPRegistry(ip: ip, apiKey: key)
                }
            } else {
                group.addTask { .skipped(source: .ipregistry) }
            }

            var results: [DataSourceResult] = []
            for await result in group {
                results.append(result)
            }

            // 统计
            let successCount = results.filter { $0.isSuccess }.count
            let skippedCount = results.filter { $0.skipped }.count
            let failedCount = results.filter { $0.error != nil }.count
            let paidCount = results.filter { $0.usedPaidAPI }.count
            AppLogger.info("✅ 数据源检测完成: 成功 \(successCount), 跳过 \(skippedCount), 失败 \(failedCount), 付费API \(paidCount)")

            return results
        }
    }

    // MARK: - IPinfo

    /// 获取 IPinfo 数据
    /// - 优先使用 widget API（数据更全，包含 privacy、asn.type 等）
    /// - widget 失败时，如果有 Token 则用 Token API 作为 fallback
    private func fetchIPinfo(ip: String, token: String?) async -> DataSourceResult {
        // 优先尝试 widget API（数据更全）
        let widgetURL = "https://ipinfo.io/widget/demo/\(ip)"

        if let url = URL(string: widgetURL) {
            do {
                let request = createRequest(url: url, referer: "https://ipinfo.io/")
                let (data, response) = try await session.data(for: request)

                if let httpResponse = response as? HTTPURLResponse,
                   (200...299).contains(httpResponse.statusCode),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    AppLogger.debug("✅ [IPinfo] 数据获取成功 (Widget API)")
                    AppLogger.debug("📦 [IPinfo] 原始数据: \(json)")
                    return parseIPinfo(json: json, usedPaidAPI: false)
                }
            } catch {
                AppLogger.debug("⚠️ [IPinfo] Widget API 失败: \(error.localizedDescription)")
            }
        }

        // Widget 失败，尝试 Token API（如果有配置）
        if let token = token {
            let tokenURL = "https://ipinfo.io/\(ip)?token=\(token)"

            guard let url = URL(string: tokenURL) else {
                return DataSourceResult(source: .ipinfo, ipType: nil, riskScore: nil, riskFactors: nil,
                                        error: URLError(.badURL), skipped: false, usedPaidAPI: true)
            }

            do {
                let request = createRequest(url: url)
                let (data, response) = try await session.data(for: request)

                guard let httpResponse = response as? HTTPURLResponse,
                      (200...299).contains(httpResponse.statusCode) else {
                    throw URLError(.badServerResponse)
                }

                guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    throw URLError(.cannotParseResponse)
                }

                AppLogger.debug("✅ [IPinfo] 数据获取成功 (Token API)")
                AppLogger.debug("📦 [IPinfo] 原始数据: \(json)")
                return parseIPinfo(json: json, usedPaidAPI: true)

            } catch {
                AppLogger.warning("⚠️ [IPinfo] Token API 失败: \(error.localizedDescription)")
                return DataSourceResult(source: .ipinfo, ipType: nil, riskScore: nil, riskFactors: nil,
                                        error: error, skipped: false, usedPaidAPI: true)
            }
        }

        // 都失败了
        AppLogger.warning("⚠️ [IPinfo] 数据获取失败")
        return DataSourceResult(source: .ipinfo, ipType: nil, riskScore: nil, riskFactors: nil,
                                error: URLError(.badServerResponse), skipped: false, usedPaidAPI: false)
    }

    // MARK: - ipapi.is

    /// 获取 ipapi.is 数据
    /// - 有 API Key: 使用付费 API (无限制)
    /// - 无 API Key: 使用免费 API (1000/天)
    private func fetchIPAPI(ip: String, apiKey: String?) async -> DataSourceResult {
        let usedPaidAPI = apiKey != nil
        var urlString = "https://api.ipapi.is/?q=\(ip)"

        if let apiKey = apiKey {
            urlString += "&key=\(apiKey)"
        }

        guard let url = URL(string: urlString) else {
            return DataSourceResult(source: .ipapi, ipType: nil, riskScore: nil, riskFactors: nil,
                                    error: URLError(.badURL), skipped: false, usedPaidAPI: usedPaidAPI)
        }

        do {
            let request = createRequest(url: url)
            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                throw URLError(.badServerResponse)
            }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw URLError(.cannotParseResponse)
            }

            let apiType = usedPaidAPI ? "付费" : "免费"
            AppLogger.debug("✅ [ipapi.is] 数据获取成功 (\(apiType) API)")
            AppLogger.debug("📦 [ipapi.is] 原始数据: \(json)")
            return parseIPAPI(json: json, usedPaidAPI: usedPaidAPI)

        } catch {
            AppLogger.warning("⚠️ [ipapi.is] 数据获取失败: \(error.localizedDescription)")
            return DataSourceResult(source: .ipapi, ipType: nil, riskScore: nil, riskFactors: nil,
                                    error: error, skipped: false, usedPaidAPI: usedPaidAPI)
        }
    }

    // MARK: - DB-IP

    /// 获取 DB-IP 数据
    /// - 有 API Key: 使用付费 API (完整数据)
    /// - 无 API Key: 使用免费 API (基础数据)
    private func fetchDBIP(ip: String, apiKey: String?) async -> DataSourceResult {
        let usedPaidAPI = apiKey != nil
        let urlString: String

        if let apiKey = apiKey {
            urlString = "https://api.db-ip.com/v2/\(apiKey)/\(ip)"
        } else {
            // 免费 API 也需要使用 HTTPS
            urlString = "https://api.db-ip.com/v2/free/\(ip)"
        }

        guard let url = URL(string: urlString) else {
            return DataSourceResult(source: .dbip, ipType: nil, riskScore: nil, riskFactors: nil,
                                    error: URLError(.badURL), skipped: false, usedPaidAPI: usedPaidAPI)
        }

        do {
            let request = createRequest(url: url)
            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                throw URLError(.badServerResponse)
            }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw URLError(.cannotParseResponse)
            }

            let apiType = usedPaidAPI ? "付费" : "免费"
            AppLogger.debug("✅ [DB-IP] 数据获取成功 (\(apiType) API)")
            AppLogger.debug("📦 [DB-IP] 原始数据: \(json)")
            return parseDBIP(json: json, usedPaidAPI: usedPaidAPI)

        } catch {
            AppLogger.warning("⚠️ [DB-IP] 数据获取失败: \(error.localizedDescription)")
            return DataSourceResult(source: .dbip, ipType: nil, riskScore: nil, riskFactors: nil,
                                    error: error, skipped: false, usedPaidAPI: usedPaidAPI)
        }
    }

    // MARK: - IPWHOIS

    /// 获取 IPWHOIS 数据
    /// - 有 API Key: 使用付费 API (无限制)
    /// - 无 API Key: 使用免费 API (10k/月)
    private func fetchIPWHOIS(ip: String, apiKey: String?) async -> DataSourceResult {
        let usedPaidAPI = apiKey != nil
        let urlString: String

        if let apiKey = apiKey {
            urlString = "https://ipwhois.io/json/\(ip)?key=\(apiKey)"
        } else {
            // 免费 API 使用 ipwho.is 端点
            urlString = "https://ipwho.is/\(ip)"
        }

        guard let url = URL(string: urlString) else {
            return DataSourceResult(source: .ipwhois, ipType: nil, riskScore: nil, riskFactors: nil,
                                    error: URLError(.badURL), skipped: false, usedPaidAPI: usedPaidAPI)
        }

        do {
            let request = createRequest(url: url)
            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                AppLogger.debug("🔍 [IPWHOIS] HTTP 状态码: \((response as? HTTPURLResponse)?.statusCode ?? -1)")
                throw URLError(.badServerResponse)
            }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw URLError(.cannotParseResponse)
            }

            // 检查 API 是否返回错误
            if let success = json["success"] as? Bool, !success {
                let message = json["message"] as? String ?? "Unknown error"
                AppLogger.warning("⚠️ [IPWHOIS] API 返回错误: \(message)")
                throw NSError(domain: "IPWHOIS", code: -1, userInfo: [NSLocalizedDescriptionKey: message])
            }

            let apiType = usedPaidAPI ? "付费" : "免费"
            AppLogger.debug("✅ [IPWHOIS] 数据获取成功 (\(apiType) API)")
            AppLogger.debug("📦 [IPWHOIS] 原始数据: \(json)")
            return parseIPWHOIS(json: json, usedPaidAPI: usedPaidAPI)

        } catch {
            AppLogger.warning("⚠️ [IPWHOIS] 数据获取失败: \(error.localizedDescription)")
            return DataSourceResult(source: .ipwhois, ipType: nil, riskScore: nil, riskFactors: nil,
                                    error: error, skipped: false, usedPaidAPI: usedPaidAPI)
        }
    }

    // MARK: - AbuseIPDB (纯付费)

    /// 获取 AbuseIPDB 数据
    private func fetchAbuseIPDB(ip: String, apiKey: String) async -> DataSourceResult {
        let urlString = "https://api.abuseipdb.com/api/v2/check?ipAddress=\(ip)"
        guard let url = URL(string: urlString) else {
            return DataSourceResult(source: .abuseipdb, ipType: nil, riskScore: nil, riskFactors: nil,
                                    error: URLError(.badURL), skipped: false, usedPaidAPI: true)
        }

        do {
            var request = createRequest(url: url)
            request.setValue(apiKey, forHTTPHeaderField: "Key")
            request.setValue("application/json", forHTTPHeaderField: "Accept")

            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                throw URLError(.badServerResponse)
            }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let dataDict = json["data"] as? [String: Any] else {
                throw URLError(.cannotParseResponse)
            }

            AppLogger.debug("✅ [AbuseIPDB] 数据获取成功")
            AppLogger.debug("📦 [AbuseIPDB] 原始数据: \(dataDict)")
            return parseAbuseIPDB(json: dataDict)

        } catch {
            AppLogger.warning("⚠️ [AbuseIPDB] 数据获取失败: \(error.localizedDescription)")
            return DataSourceResult(source: .abuseipdb, ipType: nil, riskScore: nil, riskFactors: nil,
                                    error: error, skipped: false, usedPaidAPI: true)
        }
    }

    // MARK: - IP2Location (纯付费)

    /// 获取 IP2Location 数据
    private func fetchIP2Location(ip: String, apiKey: String) async -> DataSourceResult {
        let urlString = "https://api.ip2location.io/?key=\(apiKey)&ip=\(ip)"
        guard let url = URL(string: urlString) else {
            return DataSourceResult(source: .ip2location, ipType: nil, riskScore: nil, riskFactors: nil,
                                    error: URLError(.badURL), skipped: false, usedPaidAPI: true)
        }

        do {
            let request = createRequest(url: url)
            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                throw URLError(.badServerResponse)
            }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw URLError(.cannotParseResponse)
            }

            AppLogger.debug("✅ [IP2Location] 数据获取成功")
            AppLogger.debug("📦 [IP2Location] 原始数据: \(json)")
            return parseIP2Location(json: json)

        } catch {
            AppLogger.warning("⚠️ [IP2Location] 数据获取失败: \(error.localizedDescription)")
            return DataSourceResult(source: .ip2location, ipType: nil, riskScore: nil, riskFactors: nil,
                                    error: error, skipped: false, usedPaidAPI: true)
        }
    }

    // MARK: - ipregistry (纯付费)

    /// 获取 ipregistry 数据
    private func fetchIPRegistry(ip: String, apiKey: String) async -> DataSourceResult {
        let urlString = "https://api.ipregistry.co/\(ip)?key=\(apiKey)"
        guard let url = URL(string: urlString) else {
            return DataSourceResult(source: .ipregistry, ipType: nil, riskScore: nil, riskFactors: nil,
                                    error: URLError(.badURL), skipped: false, usedPaidAPI: true)
        }

        do {
            let request = createRequest(url: url)
            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                throw URLError(.badServerResponse)
            }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw URLError(.cannotParseResponse)
            }

            AppLogger.debug("✅ [ipregistry] 数据获取成功")
            AppLogger.debug("📦 [ipregistry] 原始数据: \(json)")
            return parseIPRegistry(json: json)

        } catch {
            AppLogger.warning("⚠️ [ipregistry] 数据获取失败: \(error.localizedDescription)")
            return DataSourceResult(source: .ipregistry, ipType: nil, riskScore: nil, riskFactors: nil,
                                    error: error, skipped: false, usedPaidAPI: true)
        }
    }
}
