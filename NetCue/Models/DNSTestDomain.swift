//
//  DNSTestDomain.swift
//  NetCue
//
//  Created by SlippinDylan on 2026/01/04.
//

import Foundation

// MARK: - Domain Models

/// DNS 测试结果
struct DNSTestResult: Identifiable, Equatable {
    let id = UUID()
    let domain: String
    let averageTime: Double  // 平均耗时（毫秒）
    let maxTime: Int         // 最大耗时（毫秒）
    let minTime: Int         // 最小耗时（毫秒）
    let successCount: Int    // 成功次数
    let totalCount: Int      // 总测试次数

    /// 成功率（0.0 ~ 1.0）
    var successRate: Double {
        guard totalCount > 0 else { return 0.0 }
        return Double(successCount) / Double(totalCount)
    }

    /// 格式化的平均时间（保留2位小数）
    var formattedAverageTime: String {
        String(format: "%.2f", averageTime)
    }
}

/// DNS 测试进度
struct DNSTestProgress {
    let currentDomain: String   // 当前测试的域名
    let currentRound: Int       // 当前轮次（1-10）
    let completedDomains: Int   // 已完成的域名数
    let totalDomains: Int       // 总域名数

    /// 总进度（0.0 ~ 1.0）
    var overallProgress: Double {
        guard totalDomains > 0 else { return 0.0 }
        let domainProgress = Double(completedDomains) / Double(totalDomains)
        let roundProgress = Double(currentRound) / 10.0 / Double(totalDomains)
        return domainProgress + roundProgress
    }

    /// 进度描述文本
    var description: String {
        "Testing \(currentDomain) (\(completedDomains + 1)/\(totalDomains), Round \(currentRound)/10)"
    }
}

// MARK: - Default Test Sites

/// 默认测试网站列表
///
/// ## 数据来源
/// 综合 Alexa/Chinaz/SimilarWeb 中国网站排名
/// 涵盖搜索、视频、电商、社交、技术等主流领域
///
/// ## 测试价值
/// - 代表性强：覆盖中国用户日常访问的主流网站
/// - CDN 多样：不同网站使用不同 CDN 服务商，测试更全面
/// - 节点分布：包含全国各地的关键节点（如 12306）
let defaultTestSites: [String] = [
    // --- 综合门户 & 搜索 (Search & Portals) ---
    "www.baidu.com",      // 百度
    "www.qq.com",         // 腾讯
    "www.163.com",        // 网易
    "www.sina.com.cn",    // 新浪
    "www.sohu.com",       // 搜狐
    "www.sogou.com",      // 搜狗
    "www.so.com",         // 360搜索
    "cn.bing.com",        // 必应中国
    "www.ifeng.com",      // 凤凰网
    "www.toutiao.com",    // 今日头条 (字节跳动核心资讯)

    // --- 视频 & 直播 (Video & Streaming) ---
    "www.bilibili.com",   // B站 (CDN极其重要)
    "www.douyin.com",     // 抖音网页版
    "www.iqiyi.com",      // 爱奇艺
    "www.youku.com",      // 优酷
    "www.mgtv.com",       // 芒果TV
    "www.kuaishou.com",   // 快手
    "v.qq.com",           // 腾讯视频
    "www.huya.com",       // 虎牙
    "www.douyu.com",      // 斗鱼

    // --- 电商 & 购物 (E-commerce) ---
    "www.taobao.com",     // 淘宝
    "www.jd.com",         // 京东
    "www.tmall.com",      // 天猫
    "www.pinduoduo.com",  // 拼多多
    "www.vip.com",        // 唯品会
    "www.suning.com",     // 苏宁易购
    "www.xianyu.com",     // 闲鱼
    "www.1688.com",       // 阿里巴巴批发
    "www.alipay.com",     // 支付宝 (测试金融类解析速度)
    "www.smzdm.com",      // 什么值得买 (导购第一)

    // --- 社交 & 社区 (Social & Community) ---
    "www.zhihu.com",      // 知乎
    "weibo.com",          // 微博
    "www.xiaohongshu.com",// 小红书
    "www.douban.com",     // 豆瓣
    "tieba.baidu.com",    // 百度贴吧
    "juejin.cn",          // 掘金
    "www.jianshu.com",    // 简书
    "www.autohome.com.cn",// 汽车之家 (垂直社区)
    "www.hupu.com",       // 虎扑 (体育社区)

    // --- 技术 & 开发 (Tech & Dev) ---
    "www.csdn.net",       // CSDN
    "gitee.com",          // Gitee
    "www.cnblogs.com",    // 博客园
    "www.oschina.net",    // 开源中国
    "www.aliyun.com",     // 阿里云
    "cloud.tencent.com",  // 腾讯云
    "www.cnki.net",       // 知网 (学术网络速度)

    // --- 生活 & 工具 (Life & Tools) ---
    "www.12306.cn",       // 铁路12306 (关键节点)
    "www.amap.com",       // 高德地图
    "map.baidu.com",      // 百度地图
    "www.ctrip.com",      // 携程
    "www.meituan.com",    // 美团
    "www.dianping.com",   // 大众点评
    "www.weather.com.cn", // 中国天气网

    // --- 官方 & 权威 (Gov & Official) ---
    "www.news.cn",        // 新华网
    "www.people.com.cn",  // 人民网
    "www.cctv.com"        // 央视网
]
