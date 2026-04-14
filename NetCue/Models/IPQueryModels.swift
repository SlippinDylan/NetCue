//
//  IPQueryModels.swift
//  NetCue
//
//  Created by SlippinDylan on 2025/12/30.
//

import Foundation

// MARK: - IP Query Result

/// IP查询结果
struct IPQueryResult {
    let ip: String
    let asn: String                    // 自治系统号，如 "AS15169"
    let organization: String           // 组织名称
    let coordinates: Coordinates       // 坐标（度分秒格式）
    let location: LocationInfo         // 位置信息
    let registrationCountry: String    // 注册地，如 "[US]美国"
    let timezone: String               // 时区
    let ipType: String                 // IP类型：原生IP/数据中心IP
    let latitude: Double               // 纬度（用于地图）
    let longitude: Double              // 经度（用于地图）
}

/// 坐标信息（度分秒格式）
struct Coordinates {
    let latitudeDMS: String    // 如 "37°20′22″N"
    let longitudeDMS: String   // 如 "121°53′42″W"

    var displayString: String {
        return "\(longitudeDMS), \(latitudeDMS)"
    }
}

/// 位置信息
struct LocationInfo {
    let state: String          // 州/省
    let city: String           // 城市
    let zipCode: String        // 邮编
    let countryCode: String    // 国家代码
    let countryName: String    // 国家名称
    let continentCode: String  // 洲代码
    let continentName: String  // 洲名称

    /// 城市完整信息：州, 城市, 邮编
    var cityDisplay: String {
        return "\(state), \(city), \(zipCode)"
    }

    /// 使用地：🇨🇳[CN]China, [AS]亚洲
    var usageLocation: String {
        let flag = GeoUtils.countryFlag(countryCode: countryCode)
        return "\(flag)[\(countryCode)]\(countryName), [\(continentCode)]\(continentName)"
    }
}

// MARK: - API Response Models

/// ipapi.is 完整响应模型
struct IPAPIDetailResponse: Codable {
    let ip: String
    let asn: ASNInfo
    let company: CompanyInfo
    let location: LocationDetail
    let isDatacenter: Bool?

    enum CodingKeys: String, CodingKey {
        case ip, asn, company, location
        case isDatacenter = "is_datacenter"
    }

    struct ASNInfo: Codable {
        let asn: Int
        let org: String
        let type: String
        let country: String
        let route: String?
        let domain: String?
    }

    struct CompanyInfo: Codable {
        let name: String
        let type: String
        let domain: String?
    }

    struct LocationDetail: Codable {
        let city: String
        let state: String
        let country: String
        let countryCode: String
        let continent: String
        let latitude: Double
        let longitude: Double
        let timezone: String
        let zip: String

        enum CodingKeys: String, CodingKey {
            case city, state, country, continent, latitude, longitude, timezone, zip
            case countryCode = "country_code"
        }
    }
}
