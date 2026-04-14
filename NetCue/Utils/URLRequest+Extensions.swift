//
//  URLRequest+Extensions.swift
//  NetCue
//
//  Created by SlippinDylan on 2026/01/06.
//

import Foundation

extension URLRequest {
    /// 为 URLRequest 添加标准 HTTP 头
    ///
    /// - Parameter userAgent: User-Agent 字符串
    /// - Returns: 配置了标准头的 URLRequest
    ///
    /// ## 使用示例
    /// ```swift
    /// var request = URLRequest(url: url)
    ///     .withStandardHeaders(userAgent: userAgent)
    /// ```
    ///
    /// ## PM 价值
    /// - 消除 24 处重复代码
    /// - 统一 HTTP 头配置，便于未来扩展（如添加 Accept-Language）
    /// - 提升代码可维护性
    func withStandardHeaders(userAgent: String) -> URLRequest {
        var request = self
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        return request
    }
}
