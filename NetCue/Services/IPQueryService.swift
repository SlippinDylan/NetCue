//
//  IPQueryService.swift
//  NetCue
//
//  Created by SlippinDylan on 2025/12/30.
//

import Foundation

/// IP查询服务
class IPQueryService {
    private let session: URLSession
    private let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 30
        self.session = URLSession(configuration: config)
    }

    // MARK: - Public API

    /// 查询IP详细信息
    /// - Parameter ip: IP地址
    /// - Returns: IP查询结果
    /// - Throws: 网络错误或解析错误
    ///
    /// **P2-3 修复**：复用 `NetworkValidator.isValidIP()` 进行 IP 验证，移除重复代码
    func fetchIPInfo(ip: String) async throws -> IPQueryResult {
        // 验证IP地址格式（复用 NetworkValidator）
        guard NetworkValidator.isValidIP(ip) else {
            throw IPQueryError.invalidIPAddress
        }

        // 调用ipapi.is API
        let apiResponse = try await fetchFromIPAPI(ip: ip)

        // 转换为查询结果
        return convertToQueryResult(from: apiResponse)
    }

    // MARK: - Private Methods

    /// 从ipapi.is获取数据
    private func fetchFromIPAPI(ip: String) async throws -> IPAPIDetailResponse {
        let urlString = "https://api.ipapi.is/?q=\(ip)"
        guard let url = URL(string: urlString) else {
            throw IPQueryError.invalidURL
        }

        let request = URLRequest(url: url).withStandardHeaders(userAgent: userAgent)

        let (data, response) = try await session.data(for: request)

        // 检查HTTP状态码
        guard let httpResponse = response as? HTTPURLResponse else {
            throw IPQueryError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw IPQueryError.httpError(statusCode: httpResponse.statusCode)
        }

        // 解析JSON
        let decoder = JSONDecoder()
        do {
            return try decoder.decode(IPAPIDetailResponse.self, from: data)
        } catch {
            throw IPQueryError.decodingError(error)
        }
    }

    /// 将API响应转换为查询结果
    private func convertToQueryResult(from response: IPAPIDetailResponse) -> IPQueryResult {
        // 1. ASN格式化
        let asn = "AS\(response.asn.asn)"

        // 2. 坐标转换为度分秒
        let latitudeDMS = GeoUtils.degreesToDMS(
            decimal: response.location.latitude,
            isLatitude: true
        )
        let longitudeDMS = GeoUtils.degreesToDMS(
            decimal: response.location.longitude,
            isLatitude: false
        )
        let coordinates = Coordinates(
            latitudeDMS: latitudeDMS,
            longitudeDMS: longitudeDMS
        )

        // 3. 位置信息
        let stateTranslated = GeoUtils.translateStateName(response.location.state)
        let continentName = GeoUtils.continentName(from: response.location.continent)
        let location = LocationInfo(
            state: stateTranslated,
            city: response.location.city,
            zipCode: response.location.zip,
            countryCode: response.location.countryCode.uppercased(),
            countryName: response.location.country,
            continentCode: response.location.continent.uppercased(),
            continentName: continentName
        )

        // 4. 注册地：🇨🇳[CN]China
        let regCountryCode = response.asn.country.uppercased()
        let regCountryFlag = GeoUtils.countryFlag(countryCode: regCountryCode)
        let registrationCountry = "\(regCountryFlag)[\(regCountryCode)]\(response.location.country)"

        // 5. IP类型
        let ipType = GeoUtils.ipTypeDisplayName(from: response.company.type)

        return IPQueryResult(
            ip: response.ip,
            asn: asn,
            organization: response.company.name,
            coordinates: coordinates,
            location: location,
            registrationCountry: registrationCountry,
            timezone: response.location.timezone,
            ipType: ipType,
            latitude: response.location.latitude,
            longitude: response.location.longitude
        )
    }
}

// MARK: - Error Types

enum IPQueryError: LocalizedError {
    case invalidIPAddress
    case invalidURL
    case invalidResponse
    case httpError(statusCode: Int)
    case decodingError(Error)

    var errorDescription: String? {
        switch self {
        case .invalidIPAddress:
            return "无效的IP地址格式"
        case .invalidURL:
            return "无效的URL"
        case .invalidResponse:
            return "无效的服务器响应"
        case .httpError(let statusCode):
            return "HTTP错误: \(statusCode)"
        case .decodingError(let error):
            return "数据解析失败: \(error.localizedDescription)"
        }
    }
}
