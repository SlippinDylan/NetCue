//
//  DNSTestViewModel.swift
//  NetCue
//
//  Created by SlippinDylan on 2026/01/06.
//  Extracted from DNSTestView for reuse in DNSTestCardView
//

import SwiftUI

/// DNS 测试 ViewModel
///
/// ## 职责
/// - 管理 DNS 测试的三种状态：输入、测试中、结果展示
/// - 协调 DNSBenchmarkService 执行测试
/// - 提供进度更新和结果统计
@MainActor
@Observable
final class DNSTestViewModel {
    // MARK: - Singleton

    static let shared = DNSTestViewModel()

    // MARK: - State

    /// 视图状态
    enum ViewState {
        case input      // 输入状态
        case testing    // 测试中
        case result     // 结果展示
    }

    /// 当前状态
    var state: ViewState = .input

    /// DNS 服务器地址
    var dnsServer: String = ""

    /// 当前测试进度
    var currentProgress: DNSTestProgress?

    /// 测试结果
    var results: [DNSTestResult] = []

    // MARK: - Private Properties

    /// 当前测试任务（用于取消）
    private var testTask: Task<Void, Never>?

    // MARK: - Dependencies

    private let benchmarkService = DNSBenchmarkService()

    // MARK: - Initialization

    private init() {
        // 私有初始化器，确保单例模式
    }

    // MARK: - Public Methods

    /// 开始测试
    func startTest() {
        let server = dnsServer.trimmingCharacters(in: .whitespaces)

        guard !server.isEmpty else {
            AppLogger.warning("DNS 服务器地址为空，无法开始测试")
            return
        }

        // 切换到测试状态
        state = .testing
        currentProgress = nil
        results = []

        AppLogger.info("🚀 开始 DNS 测试: \(server)")

        // 启动测试任务并保存引用
        testTask = Task {
            // 监听进度更新
            for await progress in benchmarkService.testDNS(server: server, domains: defaultTestSites) {
                // 检查任务是否被取消
                if Task.isCancelled {
                    AppLogger.info("DNS 测试已取消")
                    return
                }
                currentProgress = progress
            }

            // 检查任务是否被取消
            guard !Task.isCancelled else {
                AppLogger.info("DNS 测试已取消")
                return
            }

            // 测试完成，获取结果
            results = await benchmarkService.getResults()

            // 切换到结果状态
            state = .result

            AppLogger.info("✅ DNS 测试完成，共测试 \(results.count) 个域名")
        }
    }

    /// 取消测试
    func cancelTest() {
        // 先取消Task
        testTask?.cancel()
        testTask = nil

        // 通知service取消
        Task {
            await benchmarkService.cancel()
        }

        // 重置UI状态
        state = .input
        currentProgress = nil
        results = []
        AppLogger.info("用户取消了 DNS 测试")
    }

    /// 重置测试（返回输入状态）
    func resetTest() {
        state = .input
        currentProgress = nil
        results = []
    }

    // MARK: - Computed Properties

    /// 计算所有网站的平均统计值
    var overallStatistics: (averageTime: Double, minTime: Int, maxTime: Int, successRate: Double)? {
        guard !results.isEmpty else { return nil }

        let totalAverage = results.map { $0.averageTime }.reduce(0, +) / Double(results.count)
        let globalMin = results.map { $0.minTime }.min() ?? 0
        let globalMax = results.map { $0.maxTime }.max() ?? 0

        let totalSuccesses = results.map { $0.successCount }.reduce(0, +)
        let totalAttempts = results.map { $0.totalCount }.reduce(0, +)
        let overallSuccessRate = totalAttempts > 0 ? Double(totalSuccesses) / Double(totalAttempts) : 0.0

        return (totalAverage, globalMin, globalMax, overallSuccessRate)
    }
}
