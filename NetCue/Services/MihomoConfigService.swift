//
//  MihomoConfigService.swift
//  NetCue
//
//  Created by SlippinDylan on 2025/12/30.
//

import Foundation

/// Mihomo 配置管理服务
class MihomoConfigService {
    private let userDefaults = UserDefaults.standard
    private let configKey = "mihomo_config"

    // MARK: - 配置读写

    /// 加载配置
    /// - Returns: Mihomo 配置,如果不存在则返回默认配置
    func loadConfig() -> MihomoConfig {
        AppLogger.debug("加载 Mihomo 配置")
        guard let data = userDefaults.data(forKey: configKey),
              let config = try? JSONDecoder().decode(MihomoConfig.self, from: data) else {
            AppLogger.info("配置不存在，使用默认配置")
            return .default
        }
        AppLogger.info("Mihomo 配置加载成功")
        return config
    }

    /// 保存配置
    /// - Parameter config: 要保存的配置
    func saveConfig(_ config: MihomoConfig) {
        AppLogger.debug("保存 Mihomo 配置")
        if let data = try? JSONEncoder().encode(config) {
            userDefaults.set(data, forKey: configKey)
            AppLogger.info("Mihomo 配置保存成功")
        } else {
            AppLogger.error("Mihomo 配置保存失败: 编码错误")
        }
    }

    /// 重置为默认配置
    func resetToDefault() {
        AppLogger.debug("重置 Mihomo 配置为默认值")
        userDefaults.removeObject(forKey: configKey)
        AppLogger.info("Mihomo 配置已重置")
    }
}
