//
//  IPDataFetchingUseCase.swift
//  NetCue
//
//  Created by SlippinDylan on 2025/12/31.
//  Refactored from IPQualityViewModel.swift - IP data fetching logic
//

import Foundation

/// IP数据获取用例 - 负责从各种API获取IP相关信息
@MainActor
class IPDataFetchingUseCase {
    private let session: URLSession
    private let userAgent: String

    // MARK: - Risk Score Weights (2026/01/07 提取为常量)

    /// 风险评分权重配置
    ///
    /// 用于根据风险因子计算综合风险评分
    private enum RiskWeight {
        static let proxy = 20      // 代理服务器
        static let vpn = 15        // VPN
        static let tor = 30        // Tor 网络
        static let datacenter = 10 // 数据中心 IP
        static let abuser = 25     // 已知滥用者
    }

    /// 威胁等级对应的风险评分
    private enum ThreatLevelScore {
        static let low = 20
        static let medium = 50
        static let high = 80
    }

    init(session: URLSession, userAgent: String) {
        self.session = session
        self.userAgent = userAgent
    }

    // MARK: - Get IP Address

    /// 获取当前公网 IP 地址
    ///
    /// **P2-5 修复**：移除硬编码 IP 回退机制
    ///
    /// **设计理念**：
    /// - DNS 问题应由用户在系统层面修复（系统偏好设置 → 网络 → DNS）
    /// - 不应在应用层绕过 DNS 解析问题
    /// - 简化逻辑，降低维护成本（无需追踪 CDN IP 变化）
    ///
    /// **备用 API**：
    /// - `api64.ipify.org` - 返回 JSON 格式
    /// - `checkip.amazonaws.com` - 返回纯文本
    /// - `icanhazip.com` - 返回纯文本
    ///
    /// - Returns: 公网 IP 地址字符串
    /// - Throws: 所有 API 均失败时抛出错误
    func getIPAddress() async throws -> String {
        let apis = [
            "https://api64.ipify.org?format=json",
            "https://checkip.amazonaws.com",
            "https://icanhazip.com"
        ]

        var lastError: Error?

        for urlString in apis {
            do {
                guard let url = URL(string: urlString) else {
                    continue
                }

                var request = URLRequest(url: url).withStandardHeaders(userAgent: userAgent)
                request.timeoutInterval = 5

                AppLogger.debug("尝试获取IP: \(urlString)")

                let (data, response) = try await session.data(for: request)

                // 验证 HTTP 响应
                if let httpResponse = response as? HTTPURLResponse {
                    AppLogger.debug("HTTP状态码: \(httpResponse.statusCode)")

                    guard (200...299).contains(httpResponse.statusCode) else {
                        AppLogger.warning("HTTP 错误: \(httpResponse.statusCode)")
                        continue
                    }
                }

                // 尝试解析 JSON 格式（ipify API）
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let ip = json["ip"] as? String {
                    AppLogger.info("成功获取IP（JSON 格式）: \(ip)")
                    return ip
                }

                // 尝试解析纯文本格式（AWS/icanhazip API）
                if let ipString = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !ipString.isEmpty {
                    AppLogger.info("成功获取IP（文本格式）: \(ipString)")
                    return ipString
                }

                AppLogger.warning("无法解析响应数据")

            } catch {
                AppLogger.error("API 失败: \(error.localizedDescription)")
                lastError = error
                continue
            }
        }

        throw lastError ?? NSError(
            domain: "IPQuality",
            code: -1,
            userInfo: [NSLocalizedDescriptionKey: "无法获取IP地址"]
        )
    }

    // MARK: - Fetch IPinfo Data
    func fetchIPInfo(ip: String) async throws -> IPInfoResponse {
        // Using free IPinfo API
        let urlString = "https://ipinfo.io/\(ip)/json"
        guard let url = URL(string: urlString) else {
            throw NSError(domain: "IPQuality", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
        }

        let request = URLRequest(url: url).withStandardHeaders(userAgent: userAgent)

        let (data, _) = try await session.data(for: request)
        let decoder = JSONDecoder()
        return try decoder.decode(IPInfoResponse.self, from: data)
    }

    func parseIPInfo(_ info: IPInfoResponse, into result: inout IPQualityResult) {
        result.city = info.city
        result.country = info.country
        result.countryCode = info.country
        result.timezone = info.timezone

        // Parse location
        if let loc = info.loc?.split(separator: ","), loc.count == 2 {
            result.latitude = Double(loc[0])
            result.longitude = Double(loc[1])
        }

        // Parse ASN from org
        if let org = info.org {
            let components = org.split(separator: " ", maxSplits: 1)
            if components.count == 2 {
                result.asn = String(components[0])
                result.organization = String(components[1])
            } else {
                result.organization = org
            }
        }

        // Parse privacy data
        if let privacy = info.privacy {
            result.isVPN = privacy.vpn ?? false
            result.isProxy = privacy.proxy ?? false
            result.isTor = privacy.tor ?? false
            result.isDatacenter = privacy.hosting ?? false
        }

        // Determine IP type
        if result.isDatacenter {
            result.ipType = .hosting
        } else {
            result.ipType = .isp
        }
    }

    // MARK: - Fetch ipapi Data
    func fetchIPAPI(ip: String) async throws -> IPAPIResponse {
        let urlString = "https://api.ipapi.is/?q=\(ip)"
        guard let url = URL(string: urlString) else {
            throw NSError(domain: "IPQuality", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
        }

        let request = URLRequest(url: url).withStandardHeaders(userAgent: userAgent)

        let (data, _) = try await session.data(for: request)
        let decoder = JSONDecoder()
        return try decoder.decode(IPAPIResponse.self, from: data)
    }

    func parseIPAPI(_ info: IPAPIResponse, into result: inout IPQualityResult) {
        // Update location if not set
        if result.city == nil {
            result.city = info.city
        }
        if result.country == nil {
            result.country = info.country
        }
        if result.countryCode == nil {
            result.countryCode = info.country_code
        }
        if result.latitude == nil {
            result.latitude = info.latitude
        }
        if result.longitude == nil {
            result.longitude = info.longitude
        }

        // Update ASN if not set
        if result.asn == nil {
            result.asn = info.asn
        }
        if result.organization == nil {
            result.organization = info.org
        }

        // Update risk factors
        result.isProxy = info.is_proxy ?? result.isProxy
        result.isVPN = info.is_vpn ?? result.isVPN
        result.isTor = info.is_tor ?? result.isTor
        result.isDatacenter = info.is_datacenter ?? result.isDatacenter
        result.isAbuser = info.is_abuser ?? false

        // Calculate risk score
        if let threatScore = info.threat_score {
            result.riskScore = threatScore
        } else {
            // Calculate based on risk factors (using defined weights)
            var score = 0
            if result.isProxy { score += RiskWeight.proxy }
            if result.isVPN { score += RiskWeight.vpn }
            if result.isTor { score += RiskWeight.tor }
            if result.isDatacenter { score += RiskWeight.datacenter }
            if result.isAbuser { score += RiskWeight.abuser }
            result.riskScore = min(score, 100)
        }

        // Determine risk level
        result.riskLevel = calculateRiskLevel(score: result.riskScore)
    }

    // MARK: - Fetch DB-IP Data
    func fetchDBIP(ip: String) async throws -> DBIPResponse {
        let urlString = "https://api.db-ip.com/v2/free/\(ip)"
        guard let url = URL(string: urlString) else {
            throw NSError(domain: "IPQuality", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
        }

        let request = URLRequest(url: url).withStandardHeaders(userAgent: userAgent)

        let (data, _) = try await session.data(for: request)
        let decoder = JSONDecoder()
        return try decoder.decode(DBIPResponse.self, from: data)
    }

    func parseDBIP(_ info: DBIPResponse, into result: inout IPQualityResult) {
        // Update location if not set
        if result.city == nil {
            result.city = info.city
        }
        if result.countryCode == nil {
            result.countryCode = info.countryCode
        }
        if result.country == nil {
            result.country = info.countryName
        }

        // Update proxy detection
        if let isProxy = info.isProxy, isProxy.lowercased() == "yes" {
            result.isProxy = true
        }

        // Update risk based on threat level (using defined scores)
        if let threatLevel = info.threatLevel?.lowercased() {
            switch threatLevel {
            case "low":
                if result.riskScore < ThreatLevelScore.low {
                    result.riskScore = ThreatLevelScore.low
                }
            case "medium":
                if result.riskScore < ThreatLevelScore.medium {
                    result.riskScore = ThreatLevelScore.medium
                }
            case "high":
                if result.riskScore < ThreatLevelScore.high {
                    result.riskScore = ThreatLevelScore.high
                }
            default:
                break
            }
            result.riskLevel = calculateRiskLevel(score: result.riskScore)
        }
    }

    // MARK: - Calculate Risk Level
    private func calculateRiskLevel(score: Int) -> RiskLevel {
        switch score {
        case 0..<20:
            return .veryLow
        case 20..<40:
            return .low
        case 40..<60:
            return .medium
        case 60..<80:
            return .high
        default:
            return .veryHigh
        }
    }
}
