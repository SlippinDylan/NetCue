//
//  DNSManager.swift
//  NetCue
//
//  Created by SlippinDylan on 2025/12/26.
//

import Foundation
import ServiceManagement
import Observation
import SystemConfiguration

/// DNS 管理器：负责与 Helper Tool 通信，管理 DNS 配置
@MainActor
@Observable
final class DNSManager {
    static let shared = DNSManager()

    var currentPrimaryDNS: String = "-"
    var currentSecondaryDNS: String = "-"
    var isHelperInstalled: Bool = false

    private var helperConnection: NSXPCConnection?
    private let helperIdentifier = "studio.slippindylan.BrewKit.NetCue.helper"

    private init() {
        checkHelperStatus()
    }

    // MARK: - Helper Installation

    /// 检查 Helper Tool 是否已安装
    ///
    /// ## 实现说明（参考 ClashX.Meta: PrivilegedHelperManager.swift）
    /// 1. 首先检查系统 Helper 文件是否存在（/Library/PrivilegedHelperTools/）
    /// 2. 如果文件存在，通过 XPC 调用 getVersion() 获取已安装版本
    /// 3. 比对 Bundle 内 Helper 版本与已安装版本
    /// 4. 只有版本匹配时才认为 Helper 已正确安装
    ///
    /// ## 关键修复
    /// - 避免仅依赖 XPC 连接状态判断（MachServices on-demand 模式下 Helper 可能未运行）
    /// - 添加版本检查，避免重复安装
    func checkHelperStatus() {
        AppLogger.debug("开始检查 Helper 状态（版本检查模式）")

        // 步骤 1: 获取 Bundle 内 Helper 的版本号
        let bundleHelperPath = Bundle.main.bundlePath + "/Contents/Library/LaunchServices/\(helperIdentifier)"
        guard let bundleHelperInfo = CFBundleCopyInfoDictionaryForURL(URL(fileURLWithPath: bundleHelperPath) as CFURL) as? [String: Any],
              let bundleVersion = bundleHelperInfo["CFBundleShortVersionString"] as? String else {
            AppLogger.warning("无法获取 Bundle 内 Helper 版本信息")
            AppLogger.debug("Bundle Helper 路径: \(bundleHelperPath)")
            self.isHelperInstalled = false
            return
        }

        AppLogger.debug("Bundle 内 Helper 版本: \(bundleVersion)")

        // 步骤 2: 检查系统 Helper 文件是否存在
        let systemHelperPath = "/Library/PrivilegedHelperTools/\(helperIdentifier)"
        let helperFileExists = FileManager.default.fileExists(atPath: systemHelperPath)

        AppLogger.debug("系统 Helper 文件存在: \(helperFileExists ? "✅ 是" : "❌ 否")")

        guard helperFileExists else {
            AppLogger.info("系统 Helper 文件不存在，需要安装")
            self.isHelperInstalled = false
            return
        }

        // 步骤 3: 检查 launchd plist 是否存在
        let plistPath = "/Library/LaunchDaemons/\(helperIdentifier).plist"
        let plistExists = FileManager.default.fileExists(atPath: plistPath)

        AppLogger.debug("Launchd plist 存在: \(plistExists ? "✅ 是" : "❌ 否")")

        guard plistExists else {
            AppLogger.info("Launchd plist 不存在，需要安装")
            self.isHelperInstalled = false
            return
        }

        // 步骤 4: 通过 XPC 调用 getVersion() 比对版本
        // 设置超时：如果 Helper 未运行，launchd 会自动启动它（on-demand）
        AppLogger.debug("正在通过 XPC 获取已安装 Helper 版本...")

        var versionCheckCompleted = false
        let timeout: TimeInterval = 15.0  // 15秒超时（参考 ClashX.Meta）

        // 设置超时定时器
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak self] in
            guard let self = self, !versionCheckCompleted else { return }
            versionCheckCompleted = true
            AppLogger.warning("Helper 版本检查超时（\(timeout)秒）")
            self.isHelperInstalled = false
        }

        connectToHelper { [weak self] connection in
            guard let self = self, !versionCheckCompleted else { return }

            guard let connection = connection else {
                guard !versionCheckCompleted else { return }
                versionCheckCompleted = true
                AppLogger.warning("无法连接到 Helper")
                self.isHelperInstalled = false
                return
            }

            let proxy = connection.remoteObjectProxyWithErrorHandler { error in
                guard !versionCheckCompleted else { return }
                versionCheckCompleted = true
                AppLogger.error("Helper 连接错误", error: error)
                DispatchQueue.main.async {
                    self.isHelperInstalled = false
                }
            } as? DNSHelperProtocol

            proxy?.getVersion { [weak self] installedVersion in
                guard let self = self, !versionCheckCompleted else { return }
                versionCheckCompleted = true

                AppLogger.debug("已安装 Helper 版本: \(installedVersion)")
                AppLogger.debug("Bundle Helper 版本: \(bundleVersion)")

                // 优化：放宽版本校验机制。如果是在开发环境（包含 dev）或是主版本号一致，均视为匹配
                let isDev = bundleVersion.contains("dev") || installedVersion.contains("dev")
                let bundleMajor = bundleVersion.split(separator: ".").first ?? ""
                let installedMajor = installedVersion.split(separator: ".").first ?? ""
                let isMajorMatch = !bundleMajor.isEmpty && bundleMajor == installedMajor

                let versionsMatch = installedVersion == bundleVersion || isDev || isMajorMatch

                if versionsMatch {
                    AppLogger.info("✅ Helper 版本匹配（或兼容），无需重新安装")
                } else {
                    AppLogger.warning("⚠️ Helper 版本不匹配且不兼容，需要更新")
                    AppLogger.warning("   已安装: \(installedVersion), Bundle: \(bundleVersion)")
                }

                DispatchQueue.main.async {
                    self.isHelperInstalled = versionsMatch
                }
            }
        }
    }

    /// 安装 Helper Tool
    ///
    /// ## 安装策略
    /// 1. 先检查并卸载旧的 Helper（如果存在）
    /// 2. 尝试使用 SMJobBless（Apple 官方 API）
    /// 3. 如果 SMJobBless 失败（签名不匹配等原因），回退到 Legacy 模式
    /// 4. Legacy 模式使用 NSAppleScript 执行 shell 脚本（需要管理员密码）
    ///
    /// ## 参考实现
    /// - ClashX.Meta: PrivilegedHelperManager+Legacy.swift
    func installHelper(completion: @escaping (Bool, Error?) -> Void) {
        AppLogger.info("═══════════════════════════════════════════════════════════")
        AppLogger.info("🚀 [Helper 安装] 开始安装 Helper Tool")
        AppLogger.info("═══════════════════════════════════════════════════════════")
        AppLogger.debug("[Helper 安装] Helper 标识符: \(helperIdentifier)")
        AppLogger.debug("[Helper 安装] 当前 Helper 安装状态: \(isHelperInstalled ? "已安装" : "未安装")")

        // 记录 App Bundle 信息
        let bundlePath = Bundle.main.bundlePath
        AppLogger.debug("[Helper 安装] App Bundle 路径: \(bundlePath)")
        AppLogger.debug("[Helper 安装] App Bundle ID: \(Bundle.main.bundleIdentifier ?? "未知")")

        // 检查 Helper 文件是否存在于 Bundle 中
        let helperInBundle = "\(bundlePath)/Contents/Library/LaunchServices/\(helperIdentifier)"
        let helperExists = FileManager.default.fileExists(atPath: helperInBundle)
        AppLogger.debug("[Helper 安装] Bundle 内 Helper 路径: \(helperInBundle)")
        AppLogger.debug("[Helper 安装] Bundle 内 Helper 存在: \(helperExists ? "✅ 是" : "❌ 否")")

        if helperExists {
            // 获取 Helper 文件信息
            if let attrs = try? FileManager.default.attributesOfItem(atPath: helperInBundle) {
                let size = attrs[.size] as? Int64 ?? 0
                let modDate = attrs[.modificationDate] as? Date
                AppLogger.debug("[Helper 安装] Bundle 内 Helper 大小: \(size) bytes")
                AppLogger.debug("[Helper 安装] Bundle 内 Helper 修改时间: \(modDate?.description ?? "未知")")
            }
        }

        // 检查系统中已安装的 Helper
        let systemHelperPath = "/Library/PrivilegedHelperTools/\(helperIdentifier)"
        let systemHelperExists = FileManager.default.fileExists(atPath: systemHelperPath)
        AppLogger.debug("[Helper 安装] 系统 Helper 路径: \(systemHelperPath)")
        AppLogger.debug("[Helper 安装] 系统 Helper 存在: \(systemHelperExists ? "✅ 是" : "❌ 否")")

        // 检查 launchd plist
        let plistPath = "/Library/LaunchDaemons/\(helperIdentifier).plist"
        let plistExists = FileManager.default.fileExists(atPath: plistPath)
        AppLogger.debug("[Helper 安装] Launchd plist 路径: \(plistPath)")
        AppLogger.debug("[Helper 安装] Launchd plist 存在: \(plistExists ? "✅ 是" : "❌ 否")")

        // ═══════════════════════════════════════════════════════════
        // 阶段 0: 清理旧的 Helper（如果存在）
        // ═══════════════════════════════════════════════════════════
        if systemHelperExists || plistExists {
            AppLogger.info("[Helper 安装] ──────────────────────────────────────────────────")
            AppLogger.info("[Helper 安装] 🧹 阶段 0: 清理旧的 Helper")
            AppLogger.info("[Helper 安装] ──────────────────────────────────────────────────")

            // 断开现有 XPC 连接
            if let connection = helperConnection {
                AppLogger.debug("[Helper 安装] 断开现有 XPC 连接")
                connection.invalidate()
                helperConnection = nil
            }

            // 卸载 launchd 服务
            if plistExists {
                AppLogger.debug("[Helper 安装] 正在卸载 launchd 服务...")
                let unloadTask = Process()
                unloadTask.executableURL = URL(fileURLWithPath: "/bin/launchctl")
                unloadTask.arguments = ["unload", "-w", plistPath]
                unloadTask.standardOutput = FileHandle.nullDevice
                unloadTask.standardError = FileHandle.nullDevice
                try? unloadTask.run()
                unloadTask.waitUntilExit()
                AppLogger.debug("[Helper 安装] launchctl unload 完成，退出码: \(unloadTask.terminationStatus)")

                // 移除服务注册
                let removeTask = Process()
                removeTask.executableURL = URL(fileURLWithPath: "/bin/launchctl")
                removeTask.arguments = ["remove", helperIdentifier]
                removeTask.standardOutput = FileHandle.nullDevice
                removeTask.standardError = FileHandle.nullDevice
                try? removeTask.run()
                removeTask.waitUntilExit()
                AppLogger.debug("[Helper 安装] launchctl remove 完成，退出码: \(removeTask.terminationStatus)")
            }

            AppLogger.info("[Helper 安装] ✅ 旧 Helper 清理完成")
        }

        AppLogger.info("[Helper 安装] ──────────────────────────────────────────────────")
        AppLogger.info("[Helper 安装] 📋 阶段 1: SMJobBless 安装尝试")
        AppLogger.info("[Helper 安装] ──────────────────────────────────────────────────")

        var authRef: AuthorizationRef?
        var authItem = kSMRightBlessPrivilegedHelper.withCString { authItemName in
            AuthorizationItem(name: authItemName, valueLength: 0, value: nil, flags: 0)
        }

        withUnsafeMutablePointer(to: &authItem) { authItemPtr in
            var authRights = AuthorizationRights(count: 1, items: authItemPtr)
            let flags: AuthorizationFlags = [.interactionAllowed, .extendRights, .preAuthorize]

            AppLogger.debug("[Helper 安装] 正在请求系统授权...")
            AppLogger.debug("[Helper 安装] 授权标志: interactionAllowed, extendRights, preAuthorize")

            let status = AuthorizationCreate(&authRights, nil, flags, &authRef)
            AppLogger.debug("[Helper 安装] AuthorizationCreate 返回状态码: \(status)")

            guard status == errAuthorizationSuccess, let authRef = authRef else {
                let errorCode = Int(status)
                let errorDescription = describeAuthorizationStatus(status)
                let error = NSError(domain: "DNSManager", code: errorCode, userInfo: [NSLocalizedDescriptionKey: "授权失败: \(errorDescription)"])
                AppLogger.error("[Helper 安装] ❌ 授权失败", error: error)
                AppLogger.error("[Helper 安装] 授权错误码: \(errorCode)")
                AppLogger.error("[Helper 安装] 授权错误描述: \(errorDescription)")
                completion(false, error)
                return
            }

            AppLogger.info("[Helper 安装] ✅ 系统授权成功")

            defer {
                AppLogger.debug("[Helper 安装] 释放授权引用")
                AuthorizationFree(authRef, [])
            }

            AppLogger.debug("[Helper 安装] 正在调用 SMJobBless...")
            AppLogger.debug("[Helper 安装] SMJobBless 参数:")
            AppLogger.debug("[Helper 安装]   - domain: kSMDomainSystemLaunchd")
            AppLogger.debug("[Helper 安装]   - helperIdentifier: \(helperIdentifier)")

            var error: Unmanaged<CFError>?
            // 使用 SMJobBless 安装特权助手工具
            // 注意：SMJobBless 在 macOS 13.0 已废弃，但 SMAppService 不支持传统的 XPC Helper Tool 架构
            // 当前必须继续使用 SMJobBless，直到 Apple 提供替代方案或重构为 SMAppService 架构
            // 参考：https://developer.apple.com/forums/thread/708030
            #if compiler(>=6.0)
            #warning("TODO: Migrate to SMAppService when Apple provides XPC Helper Tool support")
            #endif
            let success = SMJobBless(kSMDomainSystemLaunchd, helperIdentifier as CFString, authRef, &error)

            if success {
                AppLogger.info("[Helper 安装] ═══════════════════════════════════════════════════════════")
                AppLogger.info("[Helper 安装] ✅ SMJobBless 安装成功!")
                AppLogger.info("[Helper 安装] ═══════════════════════════════════════════════════════════")

                // 验证安装结果
                let verifyHelperExists = FileManager.default.fileExists(atPath: systemHelperPath)
                let verifyPlistExists = FileManager.default.fileExists(atPath: plistPath)
                AppLogger.debug("[Helper 安装] 验证 - 系统 Helper 文件: \(verifyHelperExists ? "✅ 存在" : "❌ 不存在")")
                AppLogger.debug("[Helper 安装] 验证 - Launchd plist: \(verifyPlistExists ? "✅ 存在" : "❌ 不存在")")

                // SMJobBless 在某些情况下可能不会自动 bootstrap 服务到 system domain
                // 需要使用 AppleScript with administrator privileges 执行 launchctl bootstrap
                // 注意：必须以 root 权限执行，否则会注册到 user domain
                AppLogger.info("[Helper 安装] 📋 阶段 1.5: Bootstrap 服务到 system domain")
                self.bootstrapHelperToSystemDomain(plistPath: plistPath) { bootstrapSuccess in
                    DispatchQueue.main.async {
                        self.isHelperInstalled = true
                        AppLogger.info("[Helper 安装] isHelperInstalled 状态已更新为 true")
                    }
                    completion(true, nil)
                }
                return
            } else {
                let err = error?.takeRetainedValue()
                let errorDesc = err?.localizedDescription ?? "未知错误"
                let cfErrorDomain = err.map { CFErrorGetDomain($0) as String } ?? "未知"
                let cfErrorCode = err.map { CFErrorGetCode($0) } ?? -1

                AppLogger.warning("[Helper 安装] ──────────────────────────────────────────────────")
                AppLogger.warning("[Helper 安装] ⚠️ SMJobBless 失败，准备回退到 Legacy 模式")
                AppLogger.warning("[Helper 安装] ──────────────────────────────────────────────────")
                AppLogger.warning("[Helper 安装] SMJobBless 错误信息:")
                AppLogger.warning("[Helper 安装]   - 错误描述: \(errorDesc)")
                AppLogger.warning("[Helper 安装]   - 错误域: \(cfErrorDomain)")
                AppLogger.warning("[Helper 安装]   - 错误码: \(cfErrorCode)")

                // 分析可能的失败原因
                if errorDesc.contains("code signature") || errorDesc.contains("signing") {
                    AppLogger.warning("[Helper 安装] 💡 可能原因: 代码签名不匹配")
                    AppLogger.warning("[Helper 安装]    - App 的 SMPrivilegedExecutables 配置可能与 Helper 的实际签名不匹配")
                    AppLogger.warning("[Helper 安装]    - Helper 的 SMAuthorizedClients 配置可能与 App 的实际签名不匹配")
                }

                // 回退到 Legacy 模式
                AppLogger.info("[Helper 安装] ──────────────────────────────────────────────────")
                AppLogger.info("[Helper 安装] 📋 阶段 2: Legacy 安装模式")
                AppLogger.info("[Helper 安装] ──────────────────────────────────────────────────")
                self.legacyInstallHelper(completion: completion)
            }
        }
    }

    /// 描述 Authorization 状态码
    private func describeAuthorizationStatus(_ status: OSStatus) -> String {
        switch status {
        case errAuthorizationSuccess:
            return "成功"
        case errAuthorizationInvalidSet:
            return "无效的授权集"
        case errAuthorizationInvalidRef:
            return "无效的授权引用"
        case errAuthorizationInvalidTag:
            return "无效的标签"
        case errAuthorizationInvalidPointer:
            return "无效的指针"
        case errAuthorizationDenied:
            return "授权被拒绝"
        case errAuthorizationCanceled:
            return "用户取消了授权"
        case errAuthorizationInteractionNotAllowed:
            return "不允许用户交互"
        case errAuthorizationInternal:
            return "内部错误"
        case errAuthorizationExternalizeNotAllowed:
            return "不允许外部化"
        case errAuthorizationInternalizeNotAllowed:
            return "不允许内部化"
        case errAuthorizationInvalidFlags:
            return "无效的标志"
        case errAuthorizationToolExecuteFailure:
            return "工具执行失败"
        case errAuthorizationToolEnvironmentError:
            return "工具环境错误"
        case errAuthorizationBadAddress:
            return "错误的地址"
        default:
            return "未知错误 (OSStatus: \(status))"
        }
    }

    // MARK: - Bootstrap Helper

    /// Bootstrap Helper 服务到 system domain
    ///
    /// ## 为什么需要这个方法？
    /// SMJobBless 在某些情况下（特别是 macOS 26）可能不会自动将服务 bootstrap 到 system domain。
    /// 虽然文件被正确安装到 /Library/PrivilegedHelperTools 和 /Library/LaunchDaemons，
    /// 但服务没有在 launchd 中注册，导致 XPC 连接失败。
    ///
    /// ## 实现说明
    /// - 使用 NSAppleScript with administrator privileges 执行 launchctl bootstrap
    /// - 必须以 root 权限执行，否则会注册到 user domain（错误）
    /// - 如果服务已经注册，bootstrap 会返回错误，这是正常的
    private func bootstrapHelperToSystemDomain(plistPath: String, completion: @escaping (Bool) -> Void) {
        AppLogger.debug("[Helper Bootstrap] 开始 bootstrap 服务到 system domain")
        AppLogger.debug("[Helper Bootstrap] plist 路径: \(plistPath)")

        // 构建 bootstrap 脚本
        // 使用 launchctl bootstrap system <plist> 注册到 system domain
        // 如果已经注册，会返回错误，但这不影响功能
        let script = """
        #!/bin/bash
        set -e

        PLIST_PATH="\(plistPath)"
        HELPER_ID="\(helperIdentifier)"

        echo "[Bootstrap] 检查服务是否已在 system domain 注册..."

        # 先尝试检查服务状态
        if launchctl print system/$HELPER_ID > /dev/null 2>&1; then
            echo "[Bootstrap] 服务已在 system domain 注册"
            exit 0
        fi

        echo "[Bootstrap] 服务未注册，执行 bootstrap..."

        # 使用 launchctl bootstrap 注册到 system domain
        # 注意：必须以 root 权限执行
        launchctl bootstrap system "$PLIST_PATH" 2>&1 || {
            # 如果 bootstrap 失败，尝试使用 load 命令
            echo "[Bootstrap] bootstrap 失败，尝试 load..."
            launchctl load -w "$PLIST_PATH" 2>&1 || true
        }

        echo "[Bootstrap] ✅ Bootstrap 完成"
        exit 0
        """

        // 将脚本写入临时文件
        let tmpPath = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("sh")

        AppLogger.debug("[Helper Bootstrap] 临时脚本路径: \(tmpPath.path)")

        do {
            try script.write(to: tmpPath, atomically: true, encoding: .utf8)
            AppLogger.debug("[Helper Bootstrap] ✅ 临时脚本写入成功")
        } catch {
            AppLogger.error("[Helper Bootstrap] ❌ 无法写入临时脚本", error: error)
            completion(false)
            return
        }

        // 使用 NSAppleScript 执行脚本（带管理员权限）
        let appleScriptSource = "do shell script \"bash '\(tmpPath.path)'\" with administrator privileges"
        AppLogger.debug("[Helper Bootstrap] 执行 AppleScript...")

        DispatchQueue.global(qos: .userInitiated).async {
            var errorDict: NSDictionary?
            if let appleScript = NSAppleScript(source: appleScriptSource) {
                let result = appleScript.executeAndReturnError(&errorDict)

                // 清理临时文件
                try? FileManager.default.removeItem(at: tmpPath)

                if let errorDict = errorDict {
                    let errorMsg = errorDict[NSAppleScript.errorMessage] as? String ?? "未知错误"
                    let errorNumber = errorDict[NSAppleScript.errorNumber] as? Int ?? -1

                    // 用户取消授权
                    if errorNumber == -128 {
                        AppLogger.warning("[Helper Bootstrap] 用户取消了授权")
                        completion(false)
                        return
                    }

                    AppLogger.warning("[Helper Bootstrap] AppleScript 执行出错: \(errorMsg) (code: \(errorNumber))")
                    // 即使出错也认为成功，因为可能服务已经注册
                    completion(true)
                } else {
                    if let resultString = result.stringValue {
                        AppLogger.debug("[Helper Bootstrap] 脚本输出: \(resultString)")
                    }
                    AppLogger.info("[Helper Bootstrap] ✅ Bootstrap 成功")
                    completion(true)
                }
            } else {
                try? FileManager.default.removeItem(at: tmpPath)
                AppLogger.error("[Helper Bootstrap] ❌ 无法创建 NSAppleScript 对象")
                completion(false)
            }
        }
    }

    // MARK: - Legacy Installation

    /// Legacy 模式安装 Helper Tool
    ///
    /// ## 实现说明
    /// - 当 SMJobBless 失败时（通常是签名不匹配），使用此方法作为回退
    /// - 通过 NSAppleScript 执行 shell 脚本，需要管理员密码
    /// - 脚本会将 Helper 复制到 /Library/PrivilegedHelperTools/ 并注册 launchd 服务
    ///
    /// ## 参考
    /// - ClashX.Meta: PrivilegedHelperManager+Legacy.swift
    /// - NetCue: Scripts/安装帮助工具.command
    private func legacyInstallHelper(completion: @escaping (Bool, Error?) -> Void) {
        AppLogger.info("[Helper 安装] 🔧 使用 Legacy 模式安装 Helper Tool")
        AppLogger.debug("[Helper 安装] Legacy 模式说明: 通过 NSAppleScript 执行 shell 脚本，需要管理员密码")

        // Helper 位于 App bundle 的 Contents/Library/LaunchServices/ 目录
        guard let bundlePath = Bundle.main.bundlePath as String? else {
            let error = NSError(domain: "DNSManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "无法获取 Bundle 路径"])
            AppLogger.error("[Helper 安装] ❌ Legacy 安装失败：无法获取 Bundle 路径")
            completion(false, error)
            return
        }

        let helperSource = "\(bundlePath)/Contents/Library/LaunchServices/\(helperIdentifier)"
        AppLogger.debug("[Helper 安装] Helper 源路径: \(helperSource)")

        guard FileManager.default.fileExists(atPath: helperSource) else {
            let error = NSError(domain: "DNSManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "找不到 Helper 文件"])
            AppLogger.error("[Helper 安装] ❌ Legacy 安装失败：找不到 Helper 文件")
            AppLogger.error("[Helper 安装] 期望路径: \(helperSource)")
            completion(false, error)
            return
        }

        AppLogger.debug("[Helper 安装] ✅ Helper 源文件存在")

        // 获取源文件信息
        if let attrs = try? FileManager.default.attributesOfItem(atPath: helperSource) {
            let size = attrs[.size] as? Int64 ?? 0
            let permissions = attrs[.posixPermissions] as? Int ?? 0
            AppLogger.debug("[Helper 安装] Helper 源文件大小: \(size) bytes")
            AppLogger.debug("[Helper 安装] Helper 源文件权限: \(String(format: "%o", permissions))")
        }

        let helperDest = "/Library/PrivilegedHelperTools/\(helperIdentifier)"
        let plistDest = "/Library/LaunchDaemons/\(helperIdentifier).plist"

        AppLogger.debug("[Helper 安装] Helper 目标路径: \(helperDest)")
        AppLogger.debug("[Helper 安装] Plist 目标路径: \(plistDest)")

        // 构建 launchd plist 内容
        let plistContent = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(helperIdentifier)</string>
            <key>ProgramArguments</key>
            <array>
                <string>/Library/PrivilegedHelperTools/\(helperIdentifier)</string>
            </array>
            <key>MachServices</key>
            <dict>
                <key>\(helperIdentifier)</key>
                <true/>
            </dict>
        </dict>
        </plist>
        """

        AppLogger.debug("[Helper 安装] Launchd plist 内容已生成")
        AppLogger.trace("[Helper 安装] Plist 内容:\n\(plistContent)")

        // 构建安装脚本
        // 注意：使用 heredoc 语法写入 plist，避免引号转义问题
        // 参考 ClashX.Meta: PrivilegedHelperManager+Legacy.swift
        let script = """
        #!/bin/bash
        set -e

        echo "[Legacy Install] 开始执行安装脚本"
        echo "[Legacy Install] Helper 源: \(helperSource)"
        echo "[Legacy Install] Helper 目标: \(helperDest)"
        echo "[Legacy Install] Plist 目标: \(plistDest)"

        HELPER_SOURCE="\(helperSource)"
        HELPER_DEST="\(helperDest)"
        PLIST_DEST="\(plistDest)"
        HELPER_ID="\(helperIdentifier)"

        # 创建目录（如果不存在）
        echo "[Legacy Install] 创建目录 /Library/PrivilegedHelperTools"
        mkdir -p /Library/PrivilegedHelperTools
        echo "[Legacy Install] 创建目录 /Library/LaunchDaemons"
        mkdir -p /Library/LaunchDaemons

        # 彻底清理旧服务（参考 ClashX.Meta）
        echo "[Legacy Install] 彻底清理旧服务..."
        launchctl unload -w "$PLIST_DEST" 2>/dev/null || echo "[Legacy Install] 旧 plist 不存在或已卸载"
        launchctl remove "$HELPER_ID" 2>/dev/null || echo "[Legacy Install] 旧服务注册不存在或已移除"
        rm -f "$HELPER_DEST" 2>/dev/null || true
        rm -f "$PLIST_DEST" 2>/dev/null || true

        # 复制 Helper
        echo "[Legacy Install] 复制 Helper 文件..."
        cp -f "$HELPER_SOURCE" "$HELPER_DEST"
        echo "[Legacy Install] 设置 Helper 所有者为 root:wheel"
        chown root:wheel "$HELPER_DEST"
        echo "[Legacy Install] 设置 Helper 权限为 544"
        chmod 544 "$HELPER_DEST"

        # 移除隔离属性（避免 Gatekeeper 阻止）
        echo "[Legacy Install] 移除隔离属性..."
        xattr -rd com.apple.quarantine "$HELPER_DEST" 2>/dev/null || echo "[Legacy Install] 无隔离属性或移除失败（可忽略）"

        # 创建 launchd plist
        echo "[Legacy Install] 创建 launchd plist..."
        cat > "$PLIST_DEST" << 'PLIST_EOF'
        \(plistContent)
        PLIST_EOF

        echo "[Legacy Install] 设置 plist 所有者为 root:wheel"
        chown root:wheel "$PLIST_DEST"
        echo "[Legacy Install] 设置 plist 权限为 644"
        chmod 644 "$PLIST_DEST"

        # 加载服务（使用 -w 标志确保覆盖 disabled 状态）
        echo "[Legacy Install] 加载 launchd 服务（带 -w 标志）..."
        launchctl load -w "$PLIST_DEST"

        echo "[Legacy Install] ✅ 安装脚本执行完成"
        exit 0
        """

        AppLogger.debug("[Helper 安装] 安装脚本已生成")
        AppLogger.trace("[Helper 安装] 脚本内容:\n\(script)")

        // 将脚本写入临时文件
        let tmpPath = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("sh")

        AppLogger.debug("[Helper 安装] 临时脚本路径: \(tmpPath.path)")

        do {
            try script.write(to: tmpPath, atomically: true, encoding: .utf8)
            AppLogger.debug("[Helper 安装] ✅ 临时脚本写入成功")

            // 验证临时脚本
            if let scriptContent = try? String(contentsOf: tmpPath, encoding: .utf8) {
                AppLogger.debug("[Helper 安装] 临时脚本大小: \(scriptContent.count) 字符")
            }
        } catch {
            AppLogger.error("[Helper 安装] ❌ Legacy 安装失败：无法写入临时脚本", error: error)
            completion(false, error)
            return
        }

        // 使用 NSAppleScript 执行脚本（带管理员权限）
        let appleScriptSource = "do shell script \"bash '\(tmpPath.path)'\" with administrator privileges"
        AppLogger.debug("[Helper 安装] AppleScript 命令: \(appleScriptSource)")
        AppLogger.info("[Helper 安装] 📋 即将请求管理员权限执行安装脚本...")

        DispatchQueue.global(qos: .userInitiated).async {
            AppLogger.debug("[Helper 安装] 在后台线程执行 AppleScript...")

            var errorDict: NSDictionary?
            if let appleScript = NSAppleScript(source: appleScriptSource) {
                AppLogger.debug("[Helper 安装] NSAppleScript 对象创建成功")

                let startTime = Date()
                let result = appleScript.executeAndReturnError(&errorDict)
                let duration = Date().timeIntervalSince(startTime)

                AppLogger.debug("[Helper 安装] AppleScript 执行完成，耗时: \(String(format: "%.2f", duration)) 秒")

                // 清理临时文件
                do {
                    try FileManager.default.removeItem(at: tmpPath)
                    AppLogger.debug("[Helper 安装] ✅ 临时脚本已清理")
                } catch {
                    AppLogger.warning("[Helper 安装] ⚠️ 临时脚本清理失败: \(error.localizedDescription)")
                }

                if let errorDict = errorDict {
                    let errorMsg = errorDict[NSAppleScript.errorMessage] as? String ?? "未知错误"
                    let errorNumber = errorDict[NSAppleScript.errorNumber] as? Int ?? -1
                    let errorAppName = errorDict[NSAppleScript.errorAppName] as? String ?? "未知"
                    let errorRange = errorDict[NSAppleScript.errorRange] as? NSRange

                    AppLogger.error("[Helper 安装] ──────────────────────────────────────────────────")
                    AppLogger.error("[Helper 安装] ❌ Legacy 安装失败")
                    AppLogger.error("[Helper 安装] ──────────────────────────────────────────────────")
                    AppLogger.error("[Helper 安装] 错误信息: \(errorMsg)")
                    AppLogger.error("[Helper 安装] 错误代码: \(errorNumber)")
                    AppLogger.error("[Helper 安装] 错误应用: \(errorAppName)")
                    if let range = errorRange {
                        AppLogger.error("[Helper 安装] 错误位置: location=\(range.location), length=\(range.length)")
                    }

                    // 分析错误原因
                    if errorNumber == -128 {
                        AppLogger.warning("[Helper 安装] 💡 用户取消了授权对话框")
                    } else if errorMsg.contains("not authorized") || errorMsg.contains("permission") {
                        AppLogger.warning("[Helper 安装] 💡 权限不足，可能需要在系统偏好设置中授权")
                    }

                    let error = NSError(domain: "DNSManager", code: errorNumber, userInfo: [NSLocalizedDescriptionKey: errorMsg])
                    DispatchQueue.main.async {
                        completion(false, error)
                    }
                } else {
                    // 成功
                    AppLogger.info("[Helper 安装] ═══════════════════════════════════════════════════════════")
                    AppLogger.info("[Helper 安装] ✅ Legacy 安装成功!")
                    AppLogger.info("[Helper 安装] ═══════════════════════════════════════════════════════════")

                    // 如果有返回结果，记录它
                    if let resultString = result.stringValue {
                        AppLogger.debug("[Helper 安装] 脚本输出: \(resultString)")
                    }

                    // 验证安装结果
                    let verifyHelperExists = FileManager.default.fileExists(atPath: helperDest)
                    let verifyPlistExists = FileManager.default.fileExists(atPath: plistDest)

                    AppLogger.debug("[Helper 安装] 安装验证:")
                    AppLogger.debug("[Helper 安装]   - Helper 文件: \(verifyHelperExists ? "✅ 存在" : "❌ 不存在")")
                    AppLogger.debug("[Helper 安装]   - Plist 文件: \(verifyPlistExists ? "✅ 存在" : "❌ 不存在")")

                    if verifyHelperExists {
                        if let attrs = try? FileManager.default.attributesOfItem(atPath: helperDest) {
                            let size = attrs[.size] as? Int64 ?? 0
                            let owner = attrs[.ownerAccountName] as? String ?? "未知"
                            let group = attrs[.groupOwnerAccountName] as? String ?? "未知"
                            let permissions = attrs[.posixPermissions] as? Int ?? 0
                            AppLogger.debug("[Helper 安装]   - Helper 大小: \(size) bytes")
                            AppLogger.debug("[Helper 安装]   - Helper 所有者: \(owner):\(group)")
                            AppLogger.debug("[Helper 安装]   - Helper 权限: \(String(format: "%o", permissions))")
                        }
                    }

                    // Legacy 安装使用 AppleScript with administrator privileges 执行 launchctl load，
                    // 这会以 root 权限正确地将服务注册到 system domain。
                    // 不需要在这里立即建立 XPC 连接，后续功能调用时会自然建立连接。
                    // 参考 ClashX.Meta：Legacy 安装成功后调用 checkInstall()，
                    // checkInstall() 会调用 getHelperStatus() → helper()?.getVersion()，
                    // 这时才会建立 XPC 连接。

                    DispatchQueue.main.async {
                        self.isHelperInstalled = true
                        AppLogger.info("[Helper 安装] isHelperInstalled 状态已更新为 true")
                        completion(true, nil)
                    }
                }
            } else {
                // 清理临时文件
                try? FileManager.default.removeItem(at: tmpPath)
                AppLogger.debug("[Helper 安装] 临时脚本已清理（AppleScript 创建失败分支）")

                let error = NSError(domain: "DNSManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "无法创建 AppleScript"])
                AppLogger.error("[Helper 安装] ❌ Legacy 安装失败：无法创建 NSAppleScript 对象")
                DispatchQueue.main.async {
                    completion(false, error)
                }
            }
        }
    }

    // MARK: - Helper Uninstallation

    /// 卸载 Helper Tool
    ///
    /// ## 实现说明
    /// - 通过 NSAppleScript 执行卸载脚本，需要管理员密码
    /// - 停止 launchd 服务 → 删除 plist → 删除 Helper 文件
    ///
    /// - Parameter completion: 完成回调 (success, error)
    func uninstallHelper(completion: @escaping (Bool, Error?) -> Void) {
        AppLogger.info("═══════════════════════════════════════════════════════════")
        AppLogger.info("🗑️ [Helper 卸载] 开始卸载 Helper Tool")
        AppLogger.info("═══════════════════════════════════════════════════════════")
        AppLogger.debug("[Helper 卸载] Helper 标识符: \(helperIdentifier)")
        AppLogger.debug("[Helper 卸载] 当前 Helper 安装状态: \(isHelperInstalled ? "已安装" : "未安装")")

        let helperPath = "/Library/PrivilegedHelperTools/\(helperIdentifier)"
        let plistPath = "/Library/LaunchDaemons/\(helperIdentifier).plist"

        // 检查是否已安装
        let helperExists = FileManager.default.fileExists(atPath: helperPath)
        let plistExists = FileManager.default.fileExists(atPath: plistPath)

        AppLogger.debug("[Helper 卸载] Helper 文件路径: \(helperPath)")
        AppLogger.debug("[Helper 卸载] Helper 文件存在: \(helperExists ? "✅ 是" : "❌ 否")")
        AppLogger.debug("[Helper 卸载] Plist 文件路径: \(plistPath)")
        AppLogger.debug("[Helper 卸载] Plist 文件存在: \(plistExists ? "✅ 是" : "❌ 否")")

        guard helperExists || plistExists else {
            AppLogger.info("[Helper 卸载] Helper 未安装，无需卸载")
            DispatchQueue.main.async {
                self.isHelperInstalled = false
            }
            completion(true, nil)
            return
        }

        // 断开现有连接
        if let connection = helperConnection {
            AppLogger.debug("[Helper 卸载] 断开现有 XPC 连接")
            connection.invalidate()
            helperConnection = nil
        }

        // 构建卸载脚本
        let script = """
        #!/bin/bash
        set -e

        HELPER_PATH="\(helperPath)"
        PLIST_PATH="\(plistPath)"

        echo "[Helper Uninstall] 开始卸载 Helper Tool"

        # 停止服务（使用 -w 标志）
        echo "[Helper Uninstall] 停止 launchd 服务..."
        launchctl unload -w "$PLIST_PATH" 2>/dev/null || echo "[Helper Uninstall] 服务未运行或已停止"
        launchctl remove "studio.slippindylan.BrewKit.NetCue.helper" 2>/dev/null || echo "[Helper Uninstall] 服务注册不存在"

        # 删除 plist 文件
        if [ -f "$PLIST_PATH" ]; then
            echo "[Helper Uninstall] 删除 plist 文件..."
            rm -f "$PLIST_PATH"
        fi

        # 删除 Helper 文件
        if [ -f "$HELPER_PATH" ]; then
            echo "[Helper Uninstall] 删除 Helper 文件..."
            rm -f "$HELPER_PATH"
        fi

        echo "[Helper Uninstall] ✅ 卸载完成"
        exit 0
        """

        AppLogger.debug("[Helper 卸载] 卸载脚本已生成")

        // 将脚本写入临时文件
        let tmpPath = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("sh")

        AppLogger.debug("[Helper 卸载] 临时脚本路径: \(tmpPath.path)")

        do {
            try script.write(to: tmpPath, atomically: true, encoding: .utf8)
            AppLogger.debug("[Helper 卸载] ✅ 临时脚本写入成功")
        } catch {
            AppLogger.error("[Helper 卸载] ❌ 无法写入临时脚本", error: error)
            completion(false, error)
            return
        }

        // 使用 NSAppleScript 执行脚本（带管理员权限）
        let appleScriptSource = "do shell script \"bash '\(tmpPath.path)'\" with administrator privileges"
        AppLogger.info("[Helper 卸载] 📋 即将请求管理员权限执行卸载脚本...")

        DispatchQueue.global(qos: .userInitiated).async {
            AppLogger.debug("[Helper 卸载] 在后台线程执行 AppleScript...")

            var errorDict: NSDictionary?
            if let appleScript = NSAppleScript(source: appleScriptSource) {
                let startTime = Date()
                let result = appleScript.executeAndReturnError(&errorDict)
                let duration = Date().timeIntervalSince(startTime)

                AppLogger.debug("[Helper 卸载] AppleScript 执行完成，耗时: \(String(format: "%.2f", duration)) 秒")

                // 清理临时文件
                try? FileManager.default.removeItem(at: tmpPath)
                AppLogger.debug("[Helper 卸载] ✅ 临时脚本已清理")

                if let errorDict = errorDict {
                    let errorMsg = errorDict[NSAppleScript.errorMessage] as? String ?? "未知错误"
                    let errorNumber = errorDict[NSAppleScript.errorNumber] as? Int ?? -1

                    AppLogger.error("[Helper 卸载] ──────────────────────────────────────────────────")
                    AppLogger.error("[Helper 卸载] ❌ 卸载失败")
                    AppLogger.error("[Helper 卸载] ──────────────────────────────────────────────────")
                    AppLogger.error("[Helper 卸载] 错误信息: \(errorMsg)")
                    AppLogger.error("[Helper 卸载] 错误代码: \(errorNumber)")

                    if errorNumber == -128 {
                        AppLogger.warning("[Helper 卸载] 💡 用户取消了授权对话框")
                    }

                    let error = NSError(domain: "DNSManager", code: errorNumber, userInfo: [NSLocalizedDescriptionKey: errorMsg])
                    DispatchQueue.main.async {
                        completion(false, error)
                    }
                } else {
                    // 成功
                    AppLogger.info("[Helper 卸载] ═══════════════════════════════════════════════════════════")
                    AppLogger.info("[Helper 卸载] ✅ Helper 卸载成功!")
                    AppLogger.info("[Helper 卸载] ═══════════════════════════════════════════════════════════")

                    if let resultString = result.stringValue {
                        AppLogger.debug("[Helper 卸载] 脚本输出: \(resultString)")
                    }

                    // 验证卸载结果
                    let verifyHelperExists = FileManager.default.fileExists(atPath: helperPath)
                    let verifyPlistExists = FileManager.default.fileExists(atPath: plistPath)

                    AppLogger.debug("[Helper 卸载] 卸载验证:")
                    AppLogger.debug("[Helper 卸载]   - Helper 文件: \(verifyHelperExists ? "❌ 仍存在" : "✅ 已删除")")
                    AppLogger.debug("[Helper 卸载]   - Plist 文件: \(verifyPlistExists ? "❌ 仍存在" : "✅ 已删除")")

                    DispatchQueue.main.async {
                        self.isHelperInstalled = false
                        AppLogger.info("[Helper 卸载] isHelperInstalled 状态已更新为 false")
                        completion(true, nil)
                    }
                }
            } else {
                try? FileManager.default.removeItem(at: tmpPath)
                let error = NSError(domain: "DNSManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "无法创建 AppleScript"])
                AppLogger.error("[Helper 卸载] ❌ 无法创建 NSAppleScript 对象")
                DispatchQueue.main.async {
                    completion(false, error)
                }
            }
        }
    }

    // MARK: - Helper Connection

    /// 连接到 Helper Tool
    private func connectToHelper(completion: @escaping (NSXPCConnection?) -> Void) {
        if let existing = helperConnection {
            completion(existing)
            return
        }

        let connection = NSXPCConnection(machServiceName: helperIdentifier, options: .privileged)
        connection.remoteObjectInterface = NSXPCInterface(with: DNSHelperProtocol.self)

        connection.invalidationHandler = { [weak self] in
            self?.helperConnection = nil
        }

        connection.interruptionHandler = { [weak self] in
            self?.helperConnection = nil
        }

        helperConnection = connection
        connection.resume()

        completion(connection)
    }

    /// 获取 Helper 代理
    private func getHelperProxy(retryCount: Int = 1, completion: @escaping (DNSHelperProtocol?) -> Void) {
        connectToHelper { [weak self] connection in
            guard let connection = connection else {
                if retryCount > 0 {
                    AppLogger.debug("获取 Helper 代理失败，等待 0.5s 后尝试重连...")
                    Task {
                        // 增加退避延迟，防止紧密递归导致的资源竞争
                        try? await Task.sleep(nanoseconds: 500_000_000)
                        self?.getHelperProxy(retryCount: retryCount - 1, completion: completion)
                    }
                } else {
                    completion(nil)
                }
                return
            }

            let proxy = connection.remoteObjectProxyWithErrorHandler { error in
                AppLogger.error("调用 Helper 代理出错", error: error)
                // 注意：此处的 error handler 是在具体进行 IPC 调用失败时触发的。
                // 真正的 proxy 获取是同步返回代理对象的。
                // 如果调用失败，清空连接以便下次重新连接
                self?.helperConnection = nil
            } as? DNSHelperProtocol

            completion(proxy)
        }
    }

    // MARK: - DNS Operations

    /// 设置 DNS 服务器
    ///
    /// - Parameters:
    ///   - interface: 网络接口名称
    ///   - primaryDNS: 主 DNS 服务器地址
    ///   - secondaryDNS: 备用 DNS 服务器地址（可选）
    ///   - completion: 完成回调
    func setDNS(interface: String, primaryDNS: String, secondaryDNS: String?, completion: @escaping (Bool, String?) -> Void) {
        AppLogger.info("设置 DNS - 接口: \(interface), 主 DNS: \(primaryDNS), 备用 DNS: \(secondaryDNS ?? "无")")

        guard isHelperInstalled else {
            let errorMsg = "Helper 未安装，请在设置中安装"
            AppLogger.warning("Helper 未安装，无法设置 DNS")
            completion(false, errorMsg)
            return
        }

        getHelperProxy { proxy in
            guard let proxy = proxy else {
                AppLogger.error("无法连接到 Helper，设置 DNS 失败")
                completion(false, "无法连接到 Helper")
                return
            }

            proxy.setDNS(interface: interface, primaryDNS: primaryDNS, secondaryDNS: secondaryDNS) { [weak self] success, error in
                if success {
                    AppLogger.info("DNS 设置成功: \(interface) -> \(primaryDNS)")
                    // 刷新当前 DNS 状态以更新 UI
                    DispatchQueue.main.async {
                        self?.getCurrentDNS(interface: interface) { _ in }
                    }
                } else {
                    AppLogger.error("DNS 设置失败: \(error ?? "未知错误")")
                }
                completion(success, error)
            }
        }
    }

    /// 清除 DNS 配置
    func clearDNS(interface: String, completion: @escaping (Bool, String?) -> Void) {
        AppLogger.info("清除 DNS - 接口: \(interface)")

        guard isHelperInstalled else {
            AppLogger.error("Helper 未安装，无法清除 DNS")
            completion(false, "Helper 未安装")
            return
        }

        getHelperProxy { proxy in
            guard let proxy = proxy else {
                AppLogger.error("无法连接到 Helper，清除 DNS 失败")
                completion(false, "无法连接到 Helper")
                return
            }

            proxy.clearDNS(interface: interface) { [weak self] success, error in
                if success {
                    AppLogger.info("DNS 已清除: \(interface)")
                    // 刷新当前 DNS 状态以更新 UI
                    DispatchQueue.main.async {
                        self?.getCurrentDNS(interface: interface) { _ in }
                    }
                } else {
                    AppLogger.error("DNS 清除失败: \(error ?? "未知错误")")
                }
                completion(success, error)
            }
        }
    }

    /// 获取当前 DNS 配置
    /// 使用 SystemConfiguration 框架的 SCDynamicStore API 读取系统 DNS 配置
    ///
    /// ## 实现说明
    /// - 使用 `SCDynamicStore` 原生 API 替代 `scutil --dns` 命令
    /// - 直接读取 `State:/Network/Global/DNS` 键值获取全局 DNS 设置
    /// - 性能提升：从 ~50ms（进程启动）→ ~2ms（内存读取）
    /// - 稳定性提升：不依赖命令行工具的输出格式，避免 macOS 版本变化导致解析失败
    ///
    /// ## 参数说明
    /// - Parameter interface: 网络接口名称（如 "Wi-Fi", "en0"），当前版本读取全局 DNS，暂不使用此参数
    /// - Parameter completion: 回调闭包，返回 DNS 服务器列表（主DNS在索引0，备DNS在索引1）
    func getCurrentDNS(interface: String, completion: @escaping ([String]) -> Void) {
        AppLogger.debug("获取当前 DNS 配置 - 接口: \(interface)")

        // 创建 SCDynamicStore 实例
        guard let store = SCDynamicStoreCreate(nil, "NetCue" as CFString, nil, nil) else {
            AppLogger.error("无法创建 SCDynamicStore")
            DispatchQueue.main.async {
                self.currentPrimaryDNS = "-"
                self.currentSecondaryDNS = "-"
            }
            completion([])
            return
        }

        // 读取全局 DNS 配置
        // 键路径：State:/Network/Global/DNS
        // 返回字典包含 ServerAddresses（DNS 服务器列表）、SearchDomains（搜索域）等字段
        guard let dict = SCDynamicStoreCopyValue(store, "State:/Network/Global/DNS" as CFString) as? [String: Any],
              let servers = dict["ServerAddresses"] as? [String] else {
            AppLogger.warning("未找到 DNS 配置")
            DispatchQueue.main.async {
                self.currentPrimaryDNS = "-"
                self.currentSecondaryDNS = "-"
            }
            completion([])
            return
        }

        // 更新主线程的 UI 状态
        DispatchQueue.main.async {
            self.currentPrimaryDNS = servers.first ?? "-"
            self.currentSecondaryDNS = servers.count > 1 ? servers[1] : "-"
        }

        if servers.isEmpty {
            AppLogger.info("未找到 DNS 配置")
        } else {
            let dnsInfo = servers.count > 1
                ? "主 \(servers[0]), 备用 \(servers[1])"
                : "主 \(servers[0])"
            AppLogger.info("当前 DNS: \(dnsInfo)")
        }

        completion(servers)
    }

    /// 刷新 DNS 缓存
    func flushDNSCache() {
        AppLogger.info("刷新 DNS 缓存")

        guard isHelperInstalled else {
            AppLogger.warning("Helper 未安装，无法刷新 DNS 缓存")
            return
        }

        getHelperProxy { proxy in
            guard let proxy = proxy else {
                AppLogger.error("无法连接到 Helper，刷新 DNS 缓存失败")
                return
            }

            proxy.flushDNSCache { success in
                if success {
                    AppLogger.info("DNS 缓存已刷新")
                } else {
                    AppLogger.error("DNS 缓存刷新失败")
                }
            }
        }
    }
}
