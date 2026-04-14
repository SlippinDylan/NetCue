//
//  DNSHelperProtocol.swift
//  NetCue
//
//  Created by SlippinDylan on 2025/12/26.
//

import Foundation

/// XPC 协议：定义主应用和 Helper Tool 之间的通信接口
@objc(DNSHelperProtocol)
protocol DNSHelperProtocol {
    /// 设置 DNS 服务器
    /// - Parameters:
    ///   - interface: 网络接口名称（如 "Wi-Fi", "Thunderbolt Ethernet Slot 2"）
    ///   - primaryDNS: 主 DNS 服务器地址
    ///   - secondaryDNS: 备用 DNS 服务器地址（可选）
    ///   - reply: 回调，返回是否成功和错误信息
    func setDNS(interface: String, primaryDNS: String, secondaryDNS: String?, reply: @escaping (Bool, String?) -> Void)

    /// 清除 DNS 配置（恢复自动获取）
    /// - Parameters:
    ///   - interface: 网络接口名称
    ///   - reply: 回调，返回是否成功和错误信息
    func clearDNS(interface: String, reply: @escaping (Bool, String?) -> Void)

    /// 获取当前 DNS 配置
    /// - Parameters:
    ///   - interface: 网络接口名称
    ///   - reply: 回调，返回 DNS 服务器列表
    func getDNS(interface: String, reply: @escaping ([String]) -> Void)

    /// 刷新 DNS 缓存
    /// - Parameter reply: 回调，返回是否成功
    func flushDNSCache(reply: @escaping (Bool) -> Void)

    /// 获取 Helper 版本（用于验证）
    /// - Parameter reply: 回调，返回版本号
    func getVersion(reply: @escaping (String) -> Void)
}
