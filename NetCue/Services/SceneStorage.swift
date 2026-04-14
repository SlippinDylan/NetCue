//
//  SceneStorage.swift
//  NetCue
//
//  Created by SlippinDylan on 2025/12/26.
//

import Foundation

class SceneStorage {
    private static let scenesKey = "networkScenes"

    private static var storageURL: URL {
        let urls = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        let base = urls.first ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        let netcueDir = base.appendingPathComponent("NetCue")
        try? FileManager.default.createDirectory(at: netcueDir, withIntermediateDirectories: true)
        return netcueDir.appendingPathComponent("scenes.json")
    }

    // 保存场景列表
    static func saveScenes(_ scenes: [NetworkScene]) {
        AppLogger.debug("开始保存网络场景，共 \(scenes.count) 个")
        if let encoded = try? JSONEncoder().encode(scenes) {
            do {
                // ✅ 开启 .atomic 原子写入选项，防止文件损坏
                try encoded.write(to: storageURL, options: .atomic)
                AppLogger.info("成功保存 \(scenes.count) 个网络场景")
            } catch {
                AppLogger.error("保存网络场景失败：文件写入错误 \(error)")
            }
        } else {
            AppLogger.error("保存网络场景失败：JSON编码错误")
        }
    }

    // 加载场景列表
    static func loadScenes() -> [NetworkScene] {
        AppLogger.debug("开始加载网络场景")
        
        // 迁移逻辑
        if let oldData = UserDefaults.standard.data(forKey: scenesKey), !FileManager.default.fileExists(atPath: storageURL.path) {
            AppLogger.info("发现旧版UserDefaults存储的网络场景，执行迁移")
            if let scenes = try? JSONDecoder().decode([NetworkScene].self, from: oldData) {
                saveScenes(scenes)
                UserDefaults.standard.removeObject(forKey: scenesKey)
                return scenes
            }
        }
        
        do {
            let data = try Data(contentsOf: storageURL)
            let scenes = try JSONDecoder().decode([NetworkScene].self, from: data)
            AppLogger.info("成功加载 \(scenes.count) 个网络场景")
            return scenes
        } catch {
            // 如果文件不存在，属于正常情况，不报 Error
            let nsError = error as NSError
            if nsError.domain == NSCocoaErrorDomain && nsError.code == NSFileReadNoSuchFileError {
                AppLogger.debug("未找到已保存的网络场景文件 (正常现象)")
            } else {
                AppLogger.error("加载网络场景失败: \(error.localizedDescription) (为了防止配置被错误覆盖，保持现有状态)")
            }
            return []
        }
    }
}
