//
//  DNSSceneStorage.swift
//  NetCue
//
//  Created by SlippinDylan on 2025/12/26.
//

import Foundation

/// DNS 场景持久化存储
class DNSSceneStorage {
    static let shared = DNSSceneStorage()

    private let storageKey = "dnsScenes"

    private var storageURL: URL {
        let urls = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        let base = urls.first ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        let netcueDir = base.appendingPathComponent("NetCue")
        try? FileManager.default.createDirectory(at: netcueDir, withIntermediateDirectories: true)
        return netcueDir.appendingPathComponent("dnsScenes.json")
    }

    private init() {}

    /// 保存 DNS 场景列表
    func saveScenes(_ scenes: [DNSScene]) {
        AppLogger.debug("开始保存DNS场景，共 \(scenes.count) 个")
        if let encoded = try? JSONEncoder().encode(scenes) {
            do {
                // ✅ 开启 .atomic 原子写入选项，防止文件损坏
                try encoded.write(to: storageURL, options: .atomic)
                AppLogger.info("成功保存 \(scenes.count) 个DNS场景")
            } catch {
                AppLogger.error("保存DNS场景失败：文件写入错误 \(error)")
            }
        } else {
            AppLogger.error("保存DNS场景失败：JSON编码错误")
        }
    }

    /// 加载 DNS 场景列表
    func loadScenes() -> [DNSScene] {
        AppLogger.debug("开始加载DNS场景")
        
        // 迁移逻辑
        if let oldData = UserDefaults.standard.data(forKey: storageKey), !FileManager.default.fileExists(atPath: storageURL.path) {
            AppLogger.info("发现旧版UserDefaults存储的DNS场景，执行迁移")
            if let scenes = try? JSONDecoder().decode([DNSScene].self, from: oldData) {
                saveScenes(scenes)
                UserDefaults.standard.removeObject(forKey: storageKey)
                return scenes
            }
        }

        do {
            let data = try Data(contentsOf: storageURL)
            let scenes = try JSONDecoder().decode([DNSScene].self, from: data)
            AppLogger.info("成功加载 \(scenes.count) 个DNS场景")
            return scenes
        } catch {
            // 如果文件不存在，属于正常情况
            let nsError = error as NSError
            if nsError.domain == NSCocoaErrorDomain && nsError.code == NSFileReadNoSuchFileError {
                AppLogger.debug("未找到已保存的DNS场景文件 (正常现象)")
            } else {
                AppLogger.error("加载DNS场景失败: \(error.localizedDescription)")
            }
            return []
        }
    }

    /// 清除所有场景
    func clearScenes() {
        AppLogger.info("清除所有DNS场景")
        try? FileManager.default.removeItem(at: storageURL)
    }
}
