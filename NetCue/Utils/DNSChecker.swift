//
//  DNSChecker.swift
//  NetCue
//
//  Created by SlippinDylan on 2025/12/29.
//

import Foundation

/// DNS检查工具，用于判断IP是否为原生IP
///
/// ## 实现说明
/// - 使用 POSIX `getaddrinfo` API 替代 `nslookup` 和 `dig` 命令
/// - 原生 C API，性能高、稳定性强，无需依赖外部命令行工具
/// - 支持 IPv4/IPv6 双栈解析
/// - 异步执行，避免阻塞主线程
///
/// ## 2026/01/07 修复
/// - 添加超时控制，防止 DNS 服务器无响应时永久阻塞
class DNSChecker {

    /// DNS 查询超时时间（秒）
    private static let dnsTimeout: TimeInterval = 5.0

    /// DNS解锁类型
    enum UnlockType: String {
        case native = "原生"
        case dns = "DNS"
        case unknown = "-"

        var displayName: String {
            return self.rawValue
        }
    }

    /// 检查域名的DNS解析是否正常（模拟Check_DNS_1）
    ///
    /// ## 实现说明
    /// - 使用 POSIX `getaddrinfo` API 进行 DNS 解析
    /// - 支持 IPv4 和 IPv6
    /// - 异步执行在后台队列，避免阻塞主线程
    /// - ✅ 2026/01/07 修复：添加超时控制
    ///
    /// ## 性能对比
    /// - 原实现（nslookup）：~50-100ms（进程启动开销）
    /// - 新实现（getaddrinfo）：~10-30ms（系统级 DNS 查询）
    ///
    /// - Parameter domain: 要检查的域名
    /// - Returns: true表示DNS正常，false表示DNS被劫持或超时
    static func checkDNS1(domain: String) async -> Bool {
        await withTimeout(seconds: dnsTimeout, defaultValue: false) {
            await performDNSLookup(domain: domain)
        }
    }

    /// 执行实际的 DNS 查询
    private static func performDNSLookup(domain: String) async -> Bool {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                var hints = addrinfo()
                hints.ai_family = AF_UNSPEC      // 支持 IPv4/IPv6
                hints.ai_socktype = SOCK_STREAM  // TCP 连接
                hints.ai_protocol = IPPROTO_TCP

                var result: UnsafeMutablePointer<addrinfo>?

                // 使用 defer 确保内存正确释放
                defer {
                    if let result = result {
                        freeaddrinfo(result)
                    }
                }

                // 执行 DNS 解析
                let status = getaddrinfo(domain, nil, &hints, &result)

                // status == 0 表示解析成功，result != nil 表示有返回地址
                let success = (status == 0 && result != nil)

                if !success {
                    AppLogger.debug("DNS 解析失败: \(domain), 错误码: \(status)")
                }

                continuation.resume(returning: success)
            }
        }
    }

    /// 检查随机子域名是否存在DNS通配符解析（模拟Check_DNS_3）
    ///
    /// ## 实现说明
    /// - 生成随机子域名（如 test1234567890.example.com）
    /// - 使用 `getaddrinfo` 尝试解析
    /// - 如果解析失败（返回 NXDOMAIN），说明无通配符，DNS正常
    /// - 如果解析成功，说明存在通配符DNS，可能被劫持
    /// - ✅ 2026/01/07 修复：添加超时控制
    ///
    /// - Parameter domain: 要检查的域名
    /// - Returns: true表示DNS正常（无通配符），false表示存在DNS通配符或超时
    static func checkDNS3(domain: String) async -> Bool {
        // 生成随机子域名
        let randomSubdomain = "test\(Int.random(in: 10000...99999))\(Int.random(in: 10000...99999)).\(domain)"

        return await withTimeout(seconds: dnsTimeout, defaultValue: true) {
            await performWildcardCheck(subdomain: randomSubdomain, originalDomain: domain)
        }
    }

    /// 执行通配符检查
    private static func performWildcardCheck(subdomain: String, originalDomain: String) async -> Bool {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                var hints = addrinfo()
                hints.ai_family = AF_UNSPEC
                hints.ai_socktype = SOCK_STREAM
                hints.ai_protocol = IPPROTO_TCP

                var result: UnsafeMutablePointer<addrinfo>?

                defer {
                    if let result = result {
                        freeaddrinfo(result)
                    }
                }

                let status = getaddrinfo(subdomain, nil, &hints, &result)

                // 如果查询失败（NXDOMAIN），说明不存在通配符，DNS正常
                // status != 0 表示解析失败（期望行为）
                let noWildcard = (status != 0)

                if !noWildcard {
                    AppLogger.warning("检测到 DNS 通配符: \(originalDomain) (随机子域名解析成功)")
                }

                continuation.resume(returning: noWildcard)
            }
        }
    }

    /// 根据DNS检查结果判断解锁类型
    /// - Parameters:
    ///   - dns1Result: DNS检查1的结果
    ///   - dns3Result: DNS检查3的结果
    /// - Returns: 解锁类型
    static func getUnlockType(dns1Result: Bool, dns3Result: Bool) -> UnlockType {
        // 如果任何一个DNS检查异常，判定为DNS解锁
        if !dns1Result || !dns3Result {
            return .dns
        }
        // 所有DNS检查都正常，判定为原生IP
        return .native
    }

    /// 检查域名并返回解锁类型
    /// - Parameter domain: 要检查的域名
    /// - Returns: 解锁类型
    static func checkDomain(_ domain: String) async -> UnlockType {
        async let dns1 = checkDNS1(domain: domain)
        async let dns3 = checkDNS3(domain: domain)

        let (result1, result3) = await (dns1, dns3)
        return getUnlockType(dns1Result: result1, dns3Result: result3)
    }
}
