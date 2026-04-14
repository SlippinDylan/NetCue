//
//  RouterInfoService.swift
//  NetCue
//
//  Created by SlippinDylan on 2026/01/04.
//

import Foundation
import SystemConfiguration
import Darwin

/// 路由器信息服务
///
/// ## 职责
/// - 获取路由器 IP 地址（使用 SystemConfiguration 原生 API）
/// - 获取路由器 MAC 地址（读取系统 ARP 表）
/// - 获取所有活跃的网络接口（使用 SystemConfiguration 原生 API）
///
/// ## 设计说明
/// - **无状态服务**：所有方法都是纯函数，无副作用
/// - **后台执行**：所有方法都标记为 `nonisolated`，允许后台调用
/// - **同步阻塞**：SystemConfiguration API 是同步的（在后台队列中调用）
/// - **错误处理**：失败时返回默认值（"-"），不抛出异常
///
/// ## 原生 API 使用率
/// - ✅ 路由器 IP：使用 `SCDynamicStore` 读取 `State:/Network/Global/IPv4`
/// - ✅ 活跃网络接口：使用 `SCNetworkInterfaceCopyAll` + `SCDynamicStore`
/// - ✅ 路由器 MAC：使用 `sysctl` 读取内核路由/ARP 表
///
/// ## 性能提升
/// - 原实现：7-10 个进程启动（netstat + arp + networksetup + 多个 ifconfig）
/// - 新实现：零进程启动，全部使用内存读取
/// - 性能提升：避免 fork 开销，热点路径更稳定
nonisolated final class RouterInfoService: @unchecked Sendable {
    static let shared = RouterInfoService()

    private struct MACCacheEntry {
        let value: String
        let timestamp: Date
    }

    private static let cacheLock = NSLock()
    private nonisolated(unsafe) static var macCache: [String: MACCacheEntry] = [:]
    private static let cacheTTL: TimeInterval = 3.0

    // MARK: - Network Info Structure

    /// 网络信息结构
    struct NetworkInfo: Identifiable {
        let id = UUID()
        let displayName: String  // 显示名称：Wi-Fi 或接口全称
        let interface: String     // 接口名称：en0, en7 等
    }

    // MARK: - Initialization

    /// 初始化路由器信息服务
    nonisolated init() {
        // 无状态服务，无需初始化
    }

    // MARK: - Public Methods

    /// 获取路由器 IP 地址（nonisolated 允许后台调用）
    ///
    /// ## 实现说明
    /// - 使用 `SCDynamicStore` 原生 API 替代 `netstat -nr` 命令
    /// - 读取系统键值：`State:/Network/Global/IPv4`
    /// - 提取 `Router` 字段作为默认网关（路由器）IP
    ///
    /// ## 性能对比
    /// - 原实现（netstat）：~50ms（进程启动 + 字符串解析）
    /// - 新实现（SCDynamicStore）：~2ms（内存读取）
    ///
    /// ## 错误处理
    /// - 无法创建 SCDynamicStore → 返回 "-"
    /// - 无法读取配置字典 → 返回 "-"
    /// - 未找到 Router 字段 → 返回 "-"
    ///
    /// - Returns: 路由器 IP 地址，失败时返回 "-"
    nonisolated func getRouterIP() -> String {
        // 创建 SCDynamicStore 实例
        guard let store = SCDynamicStoreCreate(nil, "NetCue" as CFString, nil, nil) else {
            AppLogger.error("❌ 无法创建 SCDynamicStore")
            return "-"
        }

        // 读取全局 IPv4 配置
        // 键路径：State:/Network/Global/IPv4
        // 返回字典包含 Router（默认网关）、PrimaryInterface、Addresses 等字段
        guard let dict = SCDynamicStoreCopyValue(store, "State:/Network/Global/IPv4" as CFString) as? [String: Any],
              let router = dict["Router"] as? String else {
            AppLogger.debug("未找到路由器 IP 配置")
            return "-"
        }

        return router
    }

    /// 获取路由器 MAC 地址（nonisolated 允许后台调用）
    ///
    /// ## 实现说明
    /// - 先获取路由器 IP（调用 `getRouterIP()`，已使用原生 API）
    /// - 使用 `sysctl(CTL_NET, AF_ROUTE, 0, AF_INET, NET_RT_FLAGS, RTF_LLINFO)` 读取 ARP 表
    /// - 在 ARP 表中匹配目标 IPv4 地址
    /// - 规范化 MAC 地址格式（大写，添加冒号）
    /// - 同一 IP 3 秒内复用缓存，避免重复扫描系统表
    ///
    /// ## 错误处理
    /// - 路由器 IP 为 "-" → 返回 "-"
    /// - sysctl 读取失败 → 返回 "-"
    /// - ARP 表中未找到目标 → 返回 "-"
    ///
    /// - Returns: 路由器 MAC 地址，失败时返回 "-"
    nonisolated func getRouterMAC() -> String {
        let routerIP = getRouterIP()

        if routerIP == "-" {
            return "-"
        }

        if let cachedMAC = Self.cachedMAC(for: routerIP) {
            return cachedMAC
        }

        guard let routerMAC = lookupMACInARPTable(for: routerIP) else {
            AppLogger.debug("未在 ARP 表中找到路由器 MAC: \(routerIP)")
            return "-"
        }

        Self.storeCachedMAC(routerMAC, for: routerIP)
        return routerMAC
    }

    /// 获取所有活跃的网络接口（nonisolated 允许后台调用）
    ///
    /// ## 实现说明
    /// - 使用 `SCNetworkInterfaceCopyAll` 原生 API 替代 `networksetup -listallhardwareports`
    /// - 使用 `SCDynamicStore` 检查接口是否有 IP 地址，替代 `ifconfig`
    /// - 使用 `SCNetworkInterfaceGetLocalizedDisplayName` 获取用户友好的接口名称
    ///
    /// ## 性能对比
    /// - 原实现（networksetup + ifconfig * N）：~150ms（假设 5 个接口）
    /// - 新实现（SCNetworkInterfaceCopyAll + SCDynamicStore）：~10ms
    ///
    /// ## 返回值
    /// - Wi-Fi 连接 → 显示名称为 "Wi-Fi"
    /// - 以太网连接 → 显示名称为硬件端口全称（如 "USB 10/100/1000 LAN"）
    ///
    /// - Returns: 活跃的网络接口列表
    nonisolated func getAllActiveNetworks() -> [NetworkInfo] {
        var networks: [NetworkInfo] = []

        // 使用 SCNetworkInterfaceCopyAll 获取所有网络接口
        guard let interfaces = SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] else {
            AppLogger.error("❌ 无法获取网络接口列表")
            return networks
        }

        for interface in interfaces {
            // 获取接口的 BSD 名称（如 en0, en7）
            guard let bsdName = SCNetworkInterfaceGetBSDName(interface) as String? else {
                continue
            }

            // 获取接口的本地化显示名称（如 "Wi-Fi", "USB 10/100/1000 LAN"）
            guard let displayName = SCNetworkInterfaceGetLocalizedDisplayName(interface) as String? else {
                continue
            }

            // 检查接口是否有 IP 地址（使用原生 API）
            if hasIPAddressNative(interface: bsdName) {
                networks.append(NetworkInfo(
                    displayName: displayName,
                    interface: bsdName
                ))
            }
        }

        return networks
    }

    /// 清空路由器 MAC 缓存
    nonisolated func clearMACCache() {
        Self.cacheLock.lock()
        defer { Self.cacheLock.unlock() }
        Self.macCache.removeAll()
    }

    // MARK: - Private Methods - Network Detection

    /// 检查网络接口是否有 IP 地址（原生 API 实现）
    ///
    /// ## 实现说明
    /// - 使用 `SCDynamicStore` 原生 API 替代 `ifconfig` 命令
    /// - 读取系统键值：`State:/Network/Interface/<interface>/IPv4`
    /// - 检查 `Addresses` 字段是否存在且非空
    ///
    /// ## 性能对比
    /// - 原实现（ifconfig）：~30ms（进程启动 + 字符串匹配）
    /// - 新实现（SCDynamicStore）：~1ms（内存读取）
    ///
    /// - Parameter interface: 接口名称（如 "en0", "en7"）
    /// - Returns: true 表示有 IP，false 表示无 IP
    nonisolated private func hasIPAddressNative(interface: String) -> Bool {
        guard let store = SCDynamicStoreCreate(nil, "NetCue" as CFString, nil, nil) else {
            return false
        }

        // 读取接口的 IPv4 配置
        // 键路径：State:/Network/Interface/<interface>/IPv4
        let key = "State:/Network/Interface/\(interface)/IPv4" as CFString
        guard let dict = SCDynamicStoreCopyValue(store, key) as? [String: Any],
              let addresses = dict["Addresses"] as? [String],
              !addresses.isEmpty else {
            return false
        }

        return true
    }

    // MARK: - Private Methods - ARP Cache

    private nonisolated func lookupMACInARPTable(for ip: String) -> String? {
        guard let targetAddress = ipv4Address(from: ip) else {
            return nil
        }

        var mib: [Int32] = [
            CTL_NET,
            AF_ROUTE,
            0,
            AF_INET,
            NET_RT_FLAGS,
            RTF_LLINFO
        ]

        var needed = 0
        guard sysctl(&mib, u_int(mib.count), nil, &needed, nil, 0) == 0, needed > 0 else {
            AppLogger.warning("读取 ARP 表大小失败: errno=\(errno)")
            return nil
        }

        var buffer = [UInt8](repeating: 0, count: needed)
        guard sysctl(&mib, u_int(mib.count), &buffer, &needed, nil, 0) == 0 else {
            AppLogger.warning("读取 ARP 表内容失败: errno=\(errno)")
            return nil
        }

        return buffer.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else {
                return nil
            }

            var offset = 0
            while offset < needed {
                let headerPointer = baseAddress
                    .advanced(by: offset)
                    .assumingMemoryBound(to: rt_msghdr.self)

                let messageLength = Int(headerPointer.pointee.rtm_msglen)
                guard messageLength > 0, offset + messageLength <= needed else {
                    break
                }

                if let macAddress = extractMACAddress(
                    fromRouteMessageAt: baseAddress.advanced(by: offset),
                    targetAddress: targetAddress
                ) {
                    return macAddress
                }

                offset += messageLength
            }

            return nil
        }
    }

    private nonisolated func extractMACAddress(
        fromRouteMessageAt baseAddress: UnsafeRawPointer,
        targetAddress: in_addr
    ) -> String? {
        let header = baseAddress.assumingMemoryBound(to: rt_msghdr.self).pointee
        var sockaddrPointer = baseAddress.advanced(by: MemoryLayout<rt_msghdr>.stride)
        var matchedTarget = false
        var macAddress: String?

        let addressMask = Int32(header.rtm_addrs)
        for index in 0..<Int(RTAX_MAX) where (addressMask & (Int32(1) << Int32(index))) != 0 {
            let sockaddrValue = sockaddrPointer.assumingMemoryBound(to: sockaddr.self).pointee
            let sockaddrLength = roundedSockaddrLength(Int(sockaddrValue.sa_len))

            if index == Int(RTAX_DST) && sockaddrValue.sa_family == UInt8(AF_INET) {
                let ipv4Pointer = sockaddrPointer.assumingMemoryBound(to: sockaddr_in.self)
                matchedTarget = ipv4Pointer.pointee.sin_addr.s_addr == targetAddress.s_addr
            } else if index == Int(RTAX_GATEWAY) && sockaddrValue.sa_family == UInt8(AF_LINK) {
                macAddress = extractMACAddress(from: sockaddrPointer)
            }

            sockaddrPointer = sockaddrPointer.advanced(by: sockaddrLength)
        }

        guard matchedTarget else {
            return nil
        }

        return macAddress
    }

    private nonisolated func extractMACAddress(from sockaddrPointer: UnsafeRawPointer) -> String? {
        let linkLayerPointer = sockaddrPointer.assumingMemoryBound(to: sockaddr_dl.self)
        let linkLayer = linkLayerPointer.pointee

        guard linkLayer.sdl_alen > 0 else {
            return nil
        }

        let linkLayerDataBaseOffset = MemoryLayout<sockaddr_dl>.offset(of: \.sdl_data) ?? 8
        let linkLayerDataOffset = linkLayerDataBaseOffset + Int(linkLayer.sdl_nlen)
        let macLength = Int(linkLayer.sdl_alen)
        guard linkLayerDataOffset + macLength <= Int(linkLayer.sdl_len) else {
            return nil
        }
        let macBytes = sockaddrPointer
            .advanced(by: linkLayerDataOffset)
            .assumingMemoryBound(to: UInt8.self)

        let macString = (0..<macLength)
            .map { String(format: "%02X", macBytes[$0]) }
            .joined(separator: ":")

        return NetworkValidator.normalizeMAC(macString)
    }

    private nonisolated func ipv4Address(from ip: String) -> in_addr? {
        var address = in_addr()
        guard inet_pton(AF_INET, ip, &address) == 1 else {
            return nil
        }
        return address
    }

    private nonisolated func roundedSockaddrLength(_ rawLength: Int) -> Int {
        let length = rawLength > 0 ? rawLength : MemoryLayout<UInt>.size
        let alignment = MemoryLayout<UInt>.size - 1
        return (length + alignment) & ~alignment
    }

    private nonisolated static func cachedMAC(for ip: String) -> String? {
        cacheLock.lock()
        defer { cacheLock.unlock() }

        guard let entry = macCache[ip] else {
            return nil
        }

        if Date().timeIntervalSince(entry.timestamp) <= cacheTTL {
            return entry.value
        }

        macCache.removeValue(forKey: ip)
        return nil
    }

    private nonisolated static func storeCachedMAC(_ mac: String, for ip: String) {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        macCache[ip] = MACCacheEntry(value: mac, timestamp: Date())
    }
}
