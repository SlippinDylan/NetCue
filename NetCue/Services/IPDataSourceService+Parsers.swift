//
//  IPDataSourceService+Parsers.swift
//  NetCue
//
//  Created by SlippinDylan on 2026/01/06.
//  Refactored on 2026/01/07 - 统一解析器签名，删除 ipdata/IPQS
//

import Foundation

// MARK: - Data Source Parsers

extension IPDataSourceService {

    // MARK: - IPinfo

    func parseIPinfo(json: [String: Any], usedPaidAPI: Bool) -> DataSourceResult {
        // 免费 widget API 的数据在 json["data"] 里，付费 API 直接在根节点
        let dataDict: [String: Any]
        if let data = json["data"] as? [String: Any] {
            dataDict = data
        } else {
            dataDict = json
        }

        // 提取 IP 类型
        // Pro API 有 asn 和 company 对象，Lite API 只有 org 字符串
        var usageType = "-"
        var companyType = "-"

        if let asn = dataDict["asn"] as? [String: Any] {
            // Pro/Widget API 格式
            usageType = mapIPinfoType(asn["type"] as? String)
        }

        if let company = dataDict["company"] as? [String: Any] {
            // Pro/Widget API 格式
            companyType = mapIPinfoType(company["type"] as? String)
        }

        // Lite API 没有类型信息，IPinfo Lite 只返回基础地理和 ASN 数据
        let ipType = DataSourceIPType(
            source: "IPinfo",
            usageType: usageType,
            companyType: companyType
        )

        // 提取风险因子
        let countryCode = dataDict["country"] as? String ?? dataDict["country_code"] as? String
        let privacy = dataDict["privacy"] as? [String: Any]

        let riskFactors = DataSourceRiskFactors(
            source: "IPinfo",
            region: countryCode,
            isProxy: privacy?["proxy"] as? Bool,
            isTor: privacy?["tor"] as? Bool,
            isVPN: privacy?["vpn"] as? Bool,
            isDatacenter: privacy?["hosting"] as? Bool,
            isAbuser: nil,
            isBot: nil
        )

        return DataSourceResult(source: .ipinfo, ipType: ipType, riskScore: nil,
                                riskFactors: riskFactors, error: nil, skipped: false, usedPaidAPI: usedPaidAPI)
    }

    // MARK: - ipapi.is

    func parseIPAPI(json: [String: Any], usedPaidAPI: Bool) -> DataSourceResult {
        // 提取 IP 类型
        let company = json["company"] as? [String: Any]
        let usageTypeRaw = company?["type"] as? String
        let usageType = mapIPAPIType(usageTypeRaw)

        let ipType = DataSourceIPType(
            source: "ipapi.is",
            usageType: usageType,
            companyType: usageType
        )

        // 提取风险评分
        var riskScore: DataSourceRiskScore?
        if let isDatacenter = json["is_datacenter"] as? Bool,
           let isVPN = json["is_vpn"] as? Bool,
           let isProxy = json["is_proxy"] as? Bool,
           let isTor = json["is_tor"] as? Bool {
            // 根据风险因子计算评分
            var score = 0
            if isDatacenter { score += 30 }
            if isVPN { score += 25 }
            if isProxy { score += 25 }
            if isTor { score += 40 }

            let level: String
            if score == 0 {
                level = "低风险"
            } else if score < 50 {
                level = "中风险"
            } else {
                level = "高风险"
            }

            riskScore = DataSourceRiskScore(source: "ipapi.is", score: score, level: level)
        }

        // 提取风险因子
        let location = json["location"] as? [String: Any]
        let countryCode = location?["country_code"] as? String

        let riskFactors = DataSourceRiskFactors(
            source: "ipapi.is",
            region: countryCode,
            isProxy: json["is_proxy"] as? Bool,
            isTor: json["is_tor"] as? Bool,
            isVPN: json["is_vpn"] as? Bool,
            isDatacenter: json["is_datacenter"] as? Bool,
            isAbuser: json["is_abuser"] as? Bool,
            isBot: nil
        )

        return DataSourceResult(source: .ipapi, ipType: ipType, riskScore: riskScore,
                                riskFactors: riskFactors, error: nil, skipped: false, usedPaidAPI: usedPaidAPI)
    }

    // MARK: - DB-IP

    func parseDBIP(json: [String: Any], usedPaidAPI: Bool) -> DataSourceResult {
        // 提取地区信息
        let countryCode = json["countryCode"] as? String

        // 免费 API 只有基础地理信息，付费 API 有更多字段
        var riskScore: DataSourceRiskScore?
        var riskFactors: DataSourceRiskFactors?

        if usedPaidAPI {
            // 付费 API 可能有威胁等级
            if let threatLevel = json["threatLevel"] as? String {
                let level: String
                var score = 0

                switch threatLevel.lowercased() {
                case "high":
                    level = "高风险"
                    score = 80
                case "medium":
                    level = "中风险"
                    score = 50
                default:
                    level = "低风险"
                    score = 10
                }

                riskScore = DataSourceRiskScore(source: "DB-IP", score: score, level: level)
            }

            // 付费 API 的代理检测
            let isProxy = json["isProxy"] as? Bool

            riskFactors = DataSourceRiskFactors(
                source: "DB-IP",
                region: countryCode,
                isProxy: isProxy,
                isTor: nil,
                isVPN: nil,
                isDatacenter: nil,
                isAbuser: nil,
                isBot: nil
            )
        } else {
            // 免费 API 只有地区信息
            riskFactors = DataSourceRiskFactors(
                source: "DB-IP",
                region: countryCode,
                isProxy: nil,
                isTor: nil,
                isVPN: nil,
                isDatacenter: nil,
                isAbuser: nil,
                isBot: nil
            )
        }

        return DataSourceResult(source: .dbip, ipType: nil, riskScore: riskScore,
                                riskFactors: riskFactors, error: nil, skipped: false, usedPaidAPI: usedPaidAPI)
    }

    // MARK: - IPWHOIS

    func parseIPWHOIS(json: [String: Any], usedPaidAPI: Bool) -> DataSourceResult {
        let countryCode = json["country_code"] as? String
        let security = json["security"] as? [String: Any]

        let riskFactors = DataSourceRiskFactors(
            source: "IPWHOIS",
            region: countryCode,
            isProxy: security?["proxy"] as? Bool,
            isTor: security?["tor"] as? Bool,
            isVPN: security?["vpn"] as? Bool,
            isDatacenter: security?["hosting"] as? Bool,
            isAbuser: nil,
            isBot: nil
        )

        return DataSourceResult(source: .ipwhois, ipType: nil, riskScore: nil,
                                riskFactors: riskFactors, error: nil, skipped: false, usedPaidAPI: usedPaidAPI)
    }

    // MARK: - AbuseIPDB

    func parseAbuseIPDB(json: [String: Any]) -> DataSourceResult {
        // 提取 IP 类型
        let usageTypeRaw = json["usageType"] as? String
        let usageType = mapAbuseIPDBType(usageTypeRaw)

        let ipType = DataSourceIPType(
            source: "AbuseIPDB",
            usageType: usageType,
            companyType: nil
        )

        // 提取风险评分
        var riskScore: DataSourceRiskScore?
        if let score = json["abuseConfidenceScore"] as? Int {
            let level: String
            if score < 25 {
                level = "低风险"
            } else if score < 75 {
                level = "高风险"
            } else {
                level = "极高风险"
            }

            riskScore = DataSourceRiskScore(source: "AbuseIPDB", score: score, level: level)
        }

        // 提取风险因子
        let countryCode = json["countryCode"] as? String
        let isTor = json["isTor"] as? Bool

        let riskFactors = DataSourceRiskFactors(
            source: "AbuseIPDB",
            region: countryCode,
            isProxy: nil,
            isTor: isTor,
            isVPN: nil,
            isDatacenter: nil,
            isAbuser: (json["abuseConfidenceScore"] as? Int ?? 0) > 25,
            isBot: nil
        )

        return DataSourceResult(source: .abuseipdb, ipType: ipType, riskScore: riskScore,
                                riskFactors: riskFactors, error: nil, skipped: false, usedPaidAPI: true)
    }

    // MARK: - IP2Location

    func parseIP2Location(json: [String: Any]) -> DataSourceResult {
        // 提取 IP 类型（某些 API 计划可能没有 usage_type）
        let usageTypeRaw = json["usage_type"] as? String
        let usageType = mapIP2LocationType(usageTypeRaw)

        let ipType = DataSourceIPType(
            source: "IP2Location",
            usageType: usageType,
            companyType: usageType
        )

        // 提取风险评分（基于代理检测）
        // is_proxy 可能是 Bool 或 Int (0/1)
        var isProxy = false
        if let proxyBool = json["is_proxy"] as? Bool {
            isProxy = proxyBool
        } else if let proxyInt = json["is_proxy"] as? Int {
            isProxy = proxyInt != 0
        }

        var riskScore: DataSourceRiskScore?
        if isProxy {
            riskScore = DataSourceRiskScore(source: "IP2Location", score: 70, level: "高风险")
        } else {
            riskScore = DataSourceRiskScore(source: "IP2Location", score: 10, level: "低风险")
        }

        // 提取风险因子
        let countryCode = json["country_code"] as? String

        let riskFactors = DataSourceRiskFactors(
            source: "IP2Location",
            region: countryCode,
            isProxy: isProxy,
            isTor: nil,
            isVPN: nil,
            isDatacenter: usageTypeRaw?.uppercased().contains("DCH") == true,
            isAbuser: nil,
            isBot: nil
        )

        return DataSourceResult(source: .ip2location, ipType: ipType, riskScore: riskScore,
                                riskFactors: riskFactors, error: nil, skipped: false, usedPaidAPI: true)
    }

    // MARK: - ipregistry

    func parseIPRegistry(json: [String: Any]) -> DataSourceResult {
        // 提取 IP 类型
        let connection = json["connection"] as? [String: Any]
        let company = json["company"] as? [String: Any]
        let usageTypeRaw = connection?["type"] as? String
        let companyTypeRaw = company?["type"] as? String

        let usageType = mapIPRegistryType(usageTypeRaw)
        let companyType = mapIPRegistryType(companyTypeRaw)

        let ipType = DataSourceIPType(
            source: "ipregistry",
            usageType: usageType,
            companyType: companyType
        )

        // 提取风险因子
        let location = json["location"] as? [String: Any]
        let countryDict = location?["country"] as? [String: Any]
        let countryCode = countryDict?["code"] as? String

        let security = json["security"] as? [String: Any]
        let tor1 = security?["is_tor"] as? Bool
        let tor2 = security?["is_tor_exit"] as? Bool
        let isTor = (tor1 == true || tor2 == true) ? true : ((tor1 == false && tor2 == false) ? false : nil)

        let riskFactors = DataSourceRiskFactors(
            source: "ipregistry",
            region: countryCode,
            isProxy: security?["is_proxy"] as? Bool,
            isTor: isTor,
            isVPN: security?["is_vpn"] as? Bool,
            isDatacenter: security?["is_cloud_provider"] as? Bool,
            isAbuser: security?["is_abuser"] as? Bool,
            isBot: nil
        )

        return DataSourceResult(source: .ipregistry, ipType: ipType, riskScore: nil,
                                riskFactors: riskFactors, error: nil, skipped: false, usedPaidAPI: true)
    }

    // MARK: - Type Mapping Helpers

    private func mapIPinfoType(_ type: String?) -> String {
        guard let type = type else { return "-" }

        switch type.lowercased() {
        case "business": return "商业"
        case "isp": return "家宽"
        case "hosting": return "机房"
        case "education": return "教育"
        default: return "其他"
        }
    }

    private func mapIPAPIType(_ type: String?) -> String {
        guard let type = type else { return "-" }

        switch type.lowercased() {
        case "business": return "商业"
        case "isp": return "家宽"
        case "hosting": return "机房"
        case "education": return "教育"
        default: return "其他"
        }
    }

    private func mapIPRegistryType(_ type: String?) -> String {
        guard let type = type else { return "-" }

        switch type.lowercased() {
        case "business": return "商业"
        case "isp": return "家宽"
        case "hosting": return "机房"
        case "education": return "教育"
        case "government": return "政府"
        default: return "其他"
        }
    }

    private func mapAbuseIPDBType(_ type: String?) -> String {
        guard let type = type else { return "-" }

        switch type {
        case "Commercial": return "商业"
        case "Data Center/Web Hosting/Transit": return "机房"
        case "University/College/School": return "教育"
        case "Government": return "政府"
        case "Organization": return "组织"
        case "Military": return "军事"
        case "Content Delivery Network": return "CDN"
        case "Fixed Line ISP": return "家宽"
        case "Mobile ISP": return "移动网络"
        case "Search Engine Spider": return "爬虫"
        default: return "其他"
        }
    }

    private func mapIP2LocationType(_ type: String?) -> String {
        guard let type = type else { return "-" }

        // IP2Location 可能返回 "DCH/ISP" 这样的格式，取第一个
        let firstType = type.components(separatedBy: "/").first ?? type

        switch firstType.uppercased() {
        case "COM": return "商业"
        case "DCH": return "机房"
        case "EDU": return "教育"
        case "GOV": return "政府"
        case "ORG": return "组织"
        case "MIL": return "军事"
        case "CDN": return "CDN"
        case "ISP": return "家宽"
        case "MOB": return "移动网络"
        case "SES": return "爬虫"
        default: return "其他"
        }
    }
}
