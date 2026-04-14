//
//  StreamingTestUseCase.swift
//  NetCue
//
//  Created by SlippinDylan on 2025/12/31.
//  Refactored from IPQualityViewModel.swift - Streaming service testing logic
//
//  ## 2026/01/07 重构
//  - 提取通用测试方法 `testService`，减少重复代码
//  - 统一错误处理和日志记录
//  - 使用配置化方式定义测试参数
//

import Foundation

/// 流媒体测试用例 - 负责测试各种流媒体服务的可用性
///
/// ## 2026/01/07 重构
/// - 使用通用 `testService` 方法减少代码重复
/// - 7 个服务的测试逻辑从 ~200 行减少到 ~100 行
@MainActor
class StreamingTestUseCase {
    private let session: URLSession
    private let userAgent: String

    /// 默认失败状态
    private static let failedStatus = StreamingStatus(available: false, region: nil, unlockType: nil)

    init(session: URLSession, userAgent: String) {
        self.session = session
        self.userAgent = userAgent
    }

    // MARK: - Public API

    func testTikTok(ip: String) async -> StreamingStatus {
        await testService(
            name: "TikTok",
            domain: "tiktok.com",
            testURL: "https://www.tiktok.com/",
            regionPattern: #/"region":"([^"\\]+)"/#
        )
    }

    func testDisney(ip: String) async -> StreamingStatus {
        await testService(
            name: "Disney+",
            domain: "disneyplus.com",
            testURL: "https://www.disneyplus.com/"
        )
    }

    func testNetflix(ip: String) async -> StreamingStatus {
        await testService(
            name: "Netflix",
            domain: "netflix.com",
            testURL: "https://www.netflix.com/title/81280792",
            regionPattern: #/"country":"([^"\\]+)"/#
        )
    }

    func testYouTube(ip: String) async -> StreamingStatus {
        await testService(
            name: "YouTube",
            domain: "youtube.com",
            testURL: "https://www.youtube.com/premium"
        )
    }

    func testAmazonPrime(ip: String) async -> StreamingStatus {
        await testService(
            name: "Amazon Prime",
            domain: "primevideo.com",
            testURL: "https://www.primevideo.com/"
        )
    }

    func testSpotify(ip: String) async -> StreamingStatus {
        await testService(
            name: "Spotify",
            domain: "spotify.com",
            testURL: "https://www.spotify.com/"
        )
    }

    func testChatGPT(ip: String) async -> StreamingStatus {
        await testService(
            name: "ChatGPT",
            domain: "openai.com",
            testURL: "https://chat.openai.com/",
            blockedKeywords: ["not available", "Access denied"]
        )
    }

    // MARK: - Generic Test Method

    /// 通用流媒体服务测试方法
    ///
    /// ## 2026/01/07 重构
    /// - 统一了所有流媒体测试的逻辑
    /// - 支持可选的区域提取和阻止检测
    ///
    /// - Parameters:
    ///   - name: 服务名称（用于日志）
    ///   - domain: DNS 检查域名
    ///   - testURL: 测试 URL
    ///   - regionPattern: 可选的区域提取正则表达式
    ///   - blockedKeywords: 可选的阻止关键词列表
    /// - Returns: 流媒体状态
    private func testService(
        name: String,
        domain: String,
        testURL: String,
        regionPattern: Regex<(Substring, Substring)>? = nil,
        blockedKeywords: [String]? = nil
    ) async -> StreamingStatus {
        // 1. DNS 检查
        let unlockType = await DNSChecker.checkDomain(domain)

        // 2. 创建请求
        guard let url = URL(string: testURL) else {
            return Self.failedStatus
        }

        let request = URLRequest(url: url).withStandardHeaders(userAgent: userAgent)

        // 3. 发起请求
        do {
            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                return Self.failedStatus
            }

            // 4. 检查状态码
            if httpResponse.statusCode == 200 {
                // 5. 检查是否被阻止
                if let keywords = blockedKeywords,
                   let html = String(data: data, encoding: .utf8) {
                    for keyword in keywords {
                        if html.contains(keyword) {
                            return Self.failedStatus
                        }
                    }
                }

                // 6. 尝试提取区域
                var region: String?
                if let pattern = regionPattern,
                   let html = String(data: data, encoding: .utf8) {
                    region = extractRegion(from: html, pattern: pattern)
                }

                return StreamingStatus(
                    available: true,
                    region: region?.uppercased(),
                    unlockType: unlockType.displayName
                )
            } else if httpResponse.statusCode == 403 {
                return Self.failedStatus
            }
        } catch {
            AppLogger.error("❌ [\(name)] 网络请求失败: \(error.localizedDescription)")
        }

        return Self.failedStatus
    }

    // MARK: - Helper Methods

    /// 使用 Swift Regex 提取区域信息
    private func extractRegion(from html: String, pattern: Regex<(Substring, Substring)>) -> String? {
        guard let match = html.firstMatch(of: pattern) else {
            AppLogger.debug("未能从 HTML 中提取区域信息")
            return nil
        }
        return String(match.1)
    }
}
