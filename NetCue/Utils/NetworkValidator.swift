//
//  NetworkValidator.swift
//  NetCue
//
//  Created by SlippinDylan on 2025/12/26.
//

import Foundation

/// 网络地址验证工具
///
/// ## 功能特性
/// - IPv4 地址格式验证
/// - MAC 地址格式验证（支持 `:` 和 `-` 分隔符）
///
/// ## 性能优化
/// - P2-1 修复：正则表达式定义为静态常量，避免每次调用都重新编译
struct NetworkValidator {

    // MARK: - Static Regex Patterns

    /// MAC 地址正则表达式（静态常量，编译期创建）
    ///
    /// **格式支持**：
    /// - `xx:xx:xx:xx:xx:xx` （冒号分隔）
    /// - `xx-xx-xx-xx-xx-xx` （连字符分隔）
    ///
    /// **性能优化**：
    /// - 使用 `static let` 避免每次调用都创建 NSRegularExpression 对象
    /// - 使用 `try!` 确保正则表达式在编译期检查（而非运行期静默失败）
    ///
    /// **P2-1 修复**：原代码使用 `try? NSRegularExpression(...)`，每次调用 `isValidMAC()` 都重新编译正则
    private static let macPattern = try! NSRegularExpression(
        pattern: "^([0-9A-Fa-f]{2}[:-]){5}([0-9A-Fa-f]{2})$"
    )

    // MARK: - Public API

    /// 验证 IP 地址格式（支持 IPv4 和 IPv6）
    ///
    /// - Parameter ip: 待验证的 IP 地址字符串
    /// - Returns: 是否为合法的 IP 地址
    ///
    /// ## 2026/01/07 修复
    /// - 添加 IPv6 支持
    /// - 使用 POSIX `inet_pton` 进行更准确的验证
    ///
    /// **示例**：
    /// ```swift
    /// NetworkValidator.isValidIP("192.168.1.1")      // true (IPv4)
    /// NetworkValidator.isValidIP("::1")              // true (IPv6)
    /// NetworkValidator.isValidIP("2001:db8::1")      // true (IPv6)
    /// NetworkValidator.isValidIP("256.1.1.1")        // false
    /// NetworkValidator.isValidIP("invalid")          // false
    /// ```
    static func isValidIP(_ ip: String) -> Bool {
        // 尝试 IPv4 验证
        if isValidIPv4(ip) {
            return true
        }

        // 尝试 IPv6 验证
        if isValidIPv6(ip) {
            return true
        }

        return false
    }

    /// 验证 IPv4 地址格式
    ///
    /// - Parameter ip: 待验证的 IP 地址字符串
    /// - Returns: 是否为合法的 IPv4 地址
    ///
    /// **验证规则**：
    /// - 必须包含 4 段，以 `.` 分隔
    /// - 每段必须是 0-255 之间的整数
    static func isValidIPv4(_ ip: String) -> Bool {
        var addr = in_addr()
        return inet_pton(AF_INET, ip, &addr) == 1
    }

    /// 验证 IPv6 地址格式
    ///
    /// - Parameter ip: 待验证的 IP 地址字符串
    /// - Returns: 是否为合法的 IPv6 地址
    ///
    /// **验证规则**：
    /// - 使用 POSIX `inet_pton` 进行标准验证
    /// - 支持压缩格式（如 `::1`、`2001:db8::1`）
    static func isValidIPv6(_ ip: String) -> Bool {
        var addr = in6_addr()
        return inet_pton(AF_INET6, ip, &addr) == 1
    }

    /// 验证 MAC 地址格式
    ///
    /// - Parameter mac: 待验证的 MAC 地址字符串
    /// - Returns: 是否为合法的 MAC 地址
    ///
    /// **支持格式**：
    /// - `00:1A:2B:3C:4D:5E` （冒号分隔，标准格式）
    /// - `00-1A-2B-3C-4D-5E` （连字符分隔）
    /// - `0:1a:2b:3c:4d:5e` （省略前导零，macOS arp 命令输出格式）
    ///
    /// **性能优化**：
    /// - 使用静态正则表达式常量（`macPattern`），避免每次调用都重新编译
    ///
    /// **示例**：
    /// ```swift
    /// NetworkValidator.isValidMAC("00:1A:2B:3C:4D:5E")  // true
    /// NetworkValidator.isValidMAC("00-1A-2B-3C-4D-5E")  // true
    /// NetworkValidator.isValidMAC("0:c:29:b9:65:61")    // true (省略前导零)
    /// NetworkValidator.isValidMAC("00:1A:2B:3C:4D")     // false
    /// ```
    static func isValidMAC(_ mac: String) -> Bool {
        // 先尝试规范化，如果能规范化成功则是有效的 MAC
        return normalizeMAC(mac) != nil
    }

    /// 规范化 MAC 地址格式
    ///
    /// ## 功能说明
    /// 将各种格式的 MAC 地址统一规范化为标准格式：`XX:XX:XX:XX:XX:XX`（大写，冒号分隔）
    ///
    /// ## 支持的输入格式
    /// - 省略前导零：`0:c:29:b9:65:61` → `00:0C:29:B9:65:61`
    /// - 标准格式：`a0:ce:c8:12:34:56` → `A0:CE:C8:12:34:56`
    /// - 横杠分隔：`a0-ce-c8-12-34-56` → `A0:CE:C8:12:34:56`
    /// - 无分隔符：`a0cec8123456` → `A0:CE:C8:12:34:56`
    ///
    /// ## 返回值
    /// - 成功：返回规范化后的 MAC 地址
    /// - 失败：返回 nil
    ///
    /// **示例**：
    /// ```swift
    /// NetworkValidator.normalizeMAC("0:c:29:b9:65:61")     // "00:0C:29:B9:65:61"
    /// NetworkValidator.normalizeMAC("a0:ce:c8:12:34:56")   // "A0:CE:C8:12:34:56"
    /// NetworkValidator.normalizeMAC("a0cec8123456")        // "A0:CE:C8:12:34:56"
    /// NetworkValidator.normalizeMAC("invalid")             // nil
    /// ```
    nonisolated static func normalizeMAC(_ mac: String) -> String? {
        // 尝试按冒号或横杠分割
        let separators = CharacterSet(charactersIn: ":-")
        let parts = mac.components(separatedBy: separators)

        if parts.count == 6 {
            // 有分隔符的格式：补齐每段的前导零
            let normalized = parts.map { part -> String in
                // 每段应该是 1-2 位十六进制，补齐到 2 位
                let trimmed = part.trimmingCharacters(in: .whitespaces)
                if trimmed.count == 1 {
                    return "0" + trimmed.uppercased()
                } else if trimmed.count == 2 {
                    return trimmed.uppercased()
                } else {
                    return trimmed.uppercased()
                }
            }

            // 验证每段都是有效的十六进制
            let isValid = normalized.allSatisfy { part in
                part.count == 2 && part.allSatisfy { $0.isHexDigit }
            }

            if isValid {
                return normalized.joined(separator: ":")
            }
        } else if parts.count == 1 {
            // 无分隔符格式：检查是否是 12 位十六进制
            let cleaned = mac.components(separatedBy: CharacterSet.alphanumerics.inverted).joined()
            if cleaned.count == 12 && cleaned.allSatisfy({ $0.isHexDigit }) {
                let upperCased = cleaned.uppercased()
                var result = ""
                for (index, char) in upperCased.enumerated() {
                    if index > 0 && index % 2 == 0 {
                        result.append(":")
                    }
                    result.append(char)
                }
                return result
            }
        }

        // 无法解析
        return nil
    }
}
