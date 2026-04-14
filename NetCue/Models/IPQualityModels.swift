//
//  IPQualityModels.swift
//  NetCue
//
//  Created by SlippinDylan on 2025/12/29.
//

import Foundation

// MARK: - Risk Level
enum RiskLevel: String, Codable {
    case veryLow = "very_low"
    case low = "low"
    case medium = "medium"
    case high = "high"
    case veryHigh = "very_high"

    var displayName: String {
        switch self {
        case .veryLow: return "极低"
        case .low: return "低"
        case .medium: return "中等"
        case .high: return "高"
        case .veryHigh: return "极高"
        }
    }

    var color: String {
        switch self {
        case .veryLow, .low: return "green"
        case .medium: return "yellow"
        case .high, .veryHigh: return "red"
        }
    }
}

// MARK: - IP Type
enum IPType: String, Codable {
    case isp = "isp"
    case hosting = "hosting"
    case business = "business"
    case education = "education"
    case government = "government"
    case cdn = "cdn"
    case mobile = "mobile"
    case unknown = "unknown"

    var displayName: String {
        switch self {
        case .isp: return "家庭宽带"
        case .hosting: return "数据中心"
        case .business: return "商业"
        case .education: return "教育"
        case .government: return "政府"
        case .cdn: return "CDN"
        case .mobile: return "移动网络"
        case .unknown: return "未知"
        }
    }
}

// MARK: - Streaming Status
struct StreamingStatus: Codable {
    var available: Bool
    var region: String?
    var unlockType: String? // 原生/DNS/-

    var displayStatus: String {
        return available ? "解锁" : "失败"
    }

    var displayRegion: String {
        guard let region = region, !region.isEmpty else {
            return "-"
        }
        return "[\(region)]"
    }

    var displayUnlockType: String {
        return unlockType ?? "-"
    }
}

// MARK: - Email Status
struct EmailStatus: Codable {
    var smtpConnectable: Bool
    var port25Open: Bool

    var displayStatus: String {
        if !port25Open {
            return "端口关闭"
        }
        return smtpConnectable ? "正常" : "无法连接"
    }
}

// MARK: - IP Quality Result
struct IPQualityResult: Codable {
    // 基础信息
    var ip: String
    var ipVersion: Int // 4 or 6
    var asn: String?
    var organization: String?
    var city: String?
    var country: String?
    var countryCode: String?
    var latitude: Double?
    var longitude: Double?
    var timezone: String?

    // IP类型
    var ipType: IPType

    // 风险评估
    var riskScore: Int // 0-100
    var riskLevel: RiskLevel

    // 风险因子
    var isProxy: Bool
    var isVPN: Bool
    var isTor: Bool
    var isDatacenter: Bool
    var isAbuser: Bool

    // 流媒体解锁
    var tiktok: StreamingStatus?
    var disney: StreamingStatus?
    var netflix: StreamingStatus?
    var youtube: StreamingStatus?
    var amazonPrime: StreamingStatus?
    var spotify: StreamingStatus?
    var chatGPT: StreamingStatus?

    // 邮件服务
    var emailStatus: EmailStatus?

    // 多数据源对比数据
    var multiSourceData: MultiSourceData?

    // 检测时间
    var detectedAt: Date

    init() {
        self.ip = ""
        self.ipVersion = 4
        self.ipType = .unknown
        self.riskScore = 0
        self.riskLevel = .veryLow
        self.isProxy = false
        self.isVPN = false
        self.isTor = false
        self.isDatacenter = false
        self.isAbuser = false
        self.detectedAt = Date()
        self.multiSourceData = MultiSourceData()
    }
}

// MARK: - API Response Models

// IPinfo API Response
struct IPInfoResponse: Codable {
    let ip: String
    let city: String?
    let region: String?
    let country: String?
    let loc: String? // "latitude,longitude"
    let org: String? // "AS15169 Google LLC"
    let timezone: String?

    // Privacy data
    let privacy: IPInfoPrivacy?

    struct IPInfoPrivacy: Codable {
        let vpn: Bool?
        let proxy: Bool?
        let tor: Bool?
        let hosting: Bool?
    }
}

// DB-IP API Response
struct DBIPResponse: Codable {
    let ipAddress: String?
    let continentCode: String?
    let continentName: String?
    let countryCode: String?
    let countryName: String?
    let stateProv: String?
    let city: String?

    // Threat data
    let threatLevel: String? // "low", "medium", "high"
    let isProxy: String? // "yes", "no"
}

// ipapi Response
struct IPAPIResponse: Codable {
    let ip: String?
    let asn: String?
    let org: String?
    let city: String?
    let country: String?
    let country_code: String?
    let latitude: Double?
    let longitude: Double?

    // Security data
    let is_proxy: Bool?
    let is_vpn: Bool?
    let is_tor: Bool?
    let is_datacenter: Bool?
    let is_abuser: Bool?
    let threat_score: Int? // 0-100
}

// MARK: - 多数据源对比结果

/// 单个数据源的 IP 类型判断
struct DataSourceIPType: Codable {
    let source: String  // 数据源名称
    let usageType: String?  // 使用类型：机房/家宽/商业等
    let companyType: String?  // 公司类型：家宽/商业/机房等
}

/// 单个数据源的风险评分
struct DataSourceRiskScore: Codable {
    let source: String
    let score: Int  // 0-100
    let level: String  // 低风险/中风险/高风险/可疑IP等
}

/// 单个数据源的风险因子判断
struct DataSourceRiskFactors: Codable {
    let source: String
    let region: String?  // 地区
    let isProxy: Bool?
    let isTor: Bool?
    let isVPN: Bool?
    let isDatacenter: Bool?
    let isAbuser: Bool?
    let isBot: Bool?
}

/// 多数据源对比数据（保留原始结果）
struct MultiSourceData: Codable {
    // IP 类型对比
    var ipTypes: [DataSourceIPType] = []

    // 风险评分对比
    var riskScores: [DataSourceRiskScore] = []

    // 风险因子对比
    var riskFactors: [DataSourceRiskFactors] = []
}
