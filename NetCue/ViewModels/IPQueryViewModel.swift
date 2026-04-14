//
//  IPQueryViewModel.swift
//  NetCue
//
//  Created by SlippinDylan on 2025/12/30.
//

import Foundation
import Observation

@MainActor
@Observable
final class IPQueryViewModel {
    static let shared = IPQueryViewModel()

    var result: IPQueryResult?
    var isLoading = false
    var errorMessage: String?

    /// IP 地址输入（持久化存储，切换 Tab 后保留）
    var ipAddress: String = ""

    private let service = IPQueryService()

    private init() {}

    /// 查询IP信息
    /// - Parameter ip: IP地址
    func queryIP(_ ip: String) async {
        // 清理输入
        let trimmedIP = ip.trimmingCharacters(in: .whitespacesAndNewlines)

        // 空输入由 View 层的 disabled 处理，这里仅做防御性检查
        guard !trimmedIP.isEmpty else {
            return
        }

        AppLogger.debug("开始查询IP信息: \(trimmedIP)")
        isLoading = true
        errorMessage = nil
        result = nil

        do {
            let queryResult = try await service.fetchIPInfo(ip: trimmedIP)
            result = queryResult
            AppLogger.info("IP查询成功: \(trimmedIP)")
        } catch let error as IPQueryError {
            errorMessage = error.errorDescription
            AppLogger.error("IP查询失败: \(trimmedIP), 错误: \(error.errorDescription ?? "未知错误")")
        } catch {
            errorMessage = "查询失败: \(error.localizedDescription)"
            AppLogger.error("IP查询失败: \(trimmedIP), 错误: \(error.localizedDescription)")
        }

        isLoading = false
    }

    /// 重置状态
    func reset() {
        AppLogger.debug("重置IP查询状态")
        result = nil
        errorMessage = nil
        isLoading = false
    }
}
