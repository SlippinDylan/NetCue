//
//  GeoUtils.swift
//  NetCue
//
//  Created by SlippinDylan on 2025/12/30.
//

import Foundation

/// 地理信息工具类
enum GeoUtils {

    // MARK: - Coordinate Conversion

    /// 将十进制度数转换为度分秒格式
    /// - Parameters:
    ///   - decimal: 十进制度数
    ///   - isLatitude: 是否为纬度（true=纬度，false=经度）
    /// - Returns: 度分秒字符串，如 "37°20′22″N" 或 "121°53′42″W"
    static func degreesToDMS(decimal: Double, isLatitude: Bool) -> String {
        let absoluteValue = abs(decimal)
        let degrees = Int(absoluteValue)
        let minutesDecimal = (absoluteValue - Double(degrees)) * 60
        let minutes = Int(minutesDecimal)
        let seconds = Int((minutesDecimal - Double(minutes)) * 60)

        let direction: String
        if isLatitude {
            direction = decimal >= 0 ? "N" : "S"
        } else {
            direction = decimal >= 0 ? "E" : "W"
        }

        return "\(degrees)°\(minutes)′\(seconds)″\(direction)"
    }

    // MARK: - Continent Mapping

    /// 洲代码到洲名的映射
    private static let continentMap: [String: String] = [
        "AF": "非洲",
        "AN": "南极洲",
        "AS": "亚洲",
        "EU": "欧洲",
        "NA": "北美洲",
        "OC": "大洋洲",
        "SA": "南美洲"
    ]

    /// 将洲代码转换为中文洲名
    /// - Parameter code: 洲代码，如 "NA"
    /// - Returns: 中文洲名，如 "北美洲"
    static func continentName(from code: String) -> String {
        return continentMap[code.uppercased()] ?? code
    }

    // MARK: - Country Flag

    /// 将国家代码转换为国旗emoji
    /// - Parameter countryCode: 国家代码，如 "US"
    /// - Returns: 国旗emoji，如 "🇺🇸"
    static func countryFlag(countryCode: String) -> String {
        let base: UInt32 = 127397
        var flag = ""
        for scalar in countryCode.uppercased().unicodeScalars {
            if let unicodeScalar = UnicodeScalar(base + scalar.value) {
                flag.unicodeScalars.append(unicodeScalar)
            }
        }
        return flag
    }

    // MARK: - IP Type Mapping

    /// IP类型映射
    /// - Parameter type: API返回的类型，如 "hosting", "isp"
    /// - Returns: 中文类型，如 "数据中心IP", "原生IP"
    static func ipTypeDisplayName(from type: String) -> String {
        switch type.lowercased() {
        case "hosting", "business":
            return "数据中心IP"
        case "isp":
            return "原生IP"
        case "education":
            return "教育机构IP"
        case "government":
            return "政府机构IP"
        default:
            return "未知类型"
        }
    }

    // MARK: - State Name Translation (Optional)

    /// 美国州名翻译（部分常见州）
    private static let stateTranslationMap: [String: String] = [
        "California": "加州",
        "New York": "纽约州",
        "Texas": "德州",
        "Florida": "佛州",
        "Washington": "华盛顿州",
        "Illinois": "伊利诺伊州",
        "Pennsylvania": "宾州",
        "Ohio": "俄亥俄州",
        "Georgia": "佐治亚州",
        "North Carolina": "北卡州",
        "Michigan": "密歇根州",
        "New Jersey": "新泽西州",
        "Virginia": "弗吉尼亚州",
        "Massachusetts": "马萨诸塞州",
        "Arizona": "亚利桑那州",
        "Indiana": "印第安纳州",
        "Tennessee": "田纳西州",
        "Missouri": "密苏里州",
        "Maryland": "马里兰州",
        "Wisconsin": "威斯康星州",
        "Colorado": "科罗拉多州",
        "Minnesota": "明尼苏达州",
        "South Carolina": "南卡州",
        "Alabama": "阿拉巴马州",
        "Louisiana": "路易斯安那州",
        "Kentucky": "肯塔基州",
        "Oregon": "俄勒冈州",
        "Oklahoma": "俄克拉荷马州",
        "Connecticut": "康涅狄格州",
        "Utah": "犹他州",
        "Nevada": "内华达州",
        "Arkansas": "阿肯色州",
        "Mississippi": "密西西比州",
        "Kansas": "堪萨斯州",
        "New Mexico": "新墨西哥州",
        "Nebraska": "内布拉斯加州",
        "West Virginia": "西弗吉尼亚州",
        "Idaho": "爱达荷州",
        "Hawaii": "夏威夷州",
        "New Hampshire": "新罕布什尔州",
        "Maine": "缅因州",
        "Montana": "蒙大拿州",
        "Rhode Island": "罗德岛州",
        "Delaware": "特拉华州",
        "South Dakota": "南达科他州",
        "North Dakota": "北达科他州",
        "Alaska": "阿拉斯加州",
        "Vermont": "佛蒙特州",
        "Wyoming": "怀俄明州"
    ]

    /// 翻译州名（如果有翻译则返回中文，否则返回原文）
    /// - Parameter stateName: 英文州名
    /// - Returns: 中文州名或原文
    static func translateStateName(_ stateName: String) -> String {
        return stateTranslationMap[stateName] ?? stateName
    }
}
