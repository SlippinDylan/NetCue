//
//  MihomoDownloadService.swift
//  NetCue
//
//  Created by SlippinDylan on 2026/01/08.
//

import Foundation
import Compression

/// Mihomo 内核下载服务
///
/// ## 职责
/// - 从 GitHub Releases 获取最新预发布版本信息
/// - 下载匹配的内核文件（.gz 格式）
/// - 解压 gzip 文件
/// - 提供下载进度回调
///
/// ## 使用方式
/// ```swift
/// let service = MihomoDownloadService()
/// let kernelPath = try await service.downloadLatestKernel(
///     filenameTemplate: "mihomo-darwin-arm64-alpha-smart",
///     targetFilename: "com.metacubex.ClashX.ProxyConfigHelper.meta"
/// ) { progress in
///     print("下载进度: \(progress * 100)%")
/// }
/// ```
final class MihomoDownloadService: NSObject {

    // MARK: - Types

    /// 下载进度回调
    typealias ProgressHandler = @Sendable (Double) -> Void

    /// 下载状态
    enum DownloadState: Sendable {
        case idle
        case fetching          // 正在获取版本信息
        case downloading       // 正在下载
        case decompressing     // 正在解压
        case completed         // 完成
        case failed(Error)     // 失败
    }

    /// GitHub Release Asset 模型
    struct GitHubAsset: Codable, Sendable {
        let name: String
        let browserDownloadUrl: String
        let size: Int

        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadUrl = "browser_download_url"
            case size
        }
    }

    /// GitHub Release 模型
    struct GitHubRelease: Codable, Sendable {
        let tagName: String
        let name: String
        let prerelease: Bool
        let assets: [GitHubAsset]

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case name
            case prerelease
            case assets
        }
    }

    // MARK: - Properties

    /// GitHub API URL 前缀
    private let githubAPIBase = "https://api.github.com/repos"

    /// 最大重试次数
    private let maxRetryCount = 3

    /// 重试延迟（秒）
    private let retryDelay: UInt64 = 2_000_000_000  // 2秒

    /// 临时下载目录
    private var tempDirectory: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("netcue_mihomo_download")
    }

    // MARK: - Public Methods

    /// 从 GitHub Releases 下载最新预发布内核
    ///
    /// ## 流程
    /// 1. 获取最新预发布版本信息
    /// 2. 查找匹配的 asset（根据文件名模板）
    /// 3. 下载 .gz 文件
    /// 4. 解压到临时目录
    /// 5. 重命名为目标文件名
    ///
    /// - Parameters:
    ///   - releasesURL: GitHub Releases 页面 URL（例如：https://github.com/vernesong/mihomo/releases）
    ///   - filenameTemplate: 内核文件名模板（例如：mihomo-darwin-arm64-alpha-smart）
    ///   - targetFilename: 目标文件名（例如：com.metacubex.ClashX.ProxyConfigHelper.meta）
    ///   - progressHandler: 下载进度回调（0.0 ~ 1.0）
    /// - Returns: 下载并解压后的内核文件路径
    /// - Throws: MihomoDownloadError
    func downloadLatestKernel(
        releasesURL: String,
        filenameTemplate: String,
        targetFilename: String,
        progressHandler: ProgressHandler? = nil
    ) async throws -> String {
        AppLogger.info("开始下载最新 Mihomo 内核")
        AppLogger.debug("Releases URL: \(releasesURL)")
        AppLogger.debug("文件名模板: \(filenameTemplate)")

        // 1. 解析 GitHub 仓库信息
        let (owner, repo) = try parseGitHubURL(releasesURL)
        AppLogger.debug("解析仓库信息: owner=\(owner), repo=\(repo)")

        // 2. 获取最新预发布版本
        let release = try await fetchLatestPrerelease(owner: owner, repo: repo)
        AppLogger.info("找到预发布版本: \(release.tagName)")

        // 3. 查找匹配的 asset
        guard let asset = findMatchingAsset(release: release, filenameTemplate: filenameTemplate) else {
            throw MihomoDownloadError.assetNotFound(filenameTemplate)
        }
        AppLogger.info("找到匹配的文件: \(asset.name) (\(formatFileSize(asset.size)))")

        // 4. 准备临时目录
        try prepareTemporaryDirectory()

        // 5. 下载文件
        let downloadedPath = try await downloadAsset(asset: asset, progressHandler: progressHandler)
        AppLogger.info("文件下载完成: \(downloadedPath)")

        // 6. 解压 gzip 文件
        let decompressedPath = try decompressGzip(at: downloadedPath)
        AppLogger.info("文件解压完成: \(decompressedPath)")

        // 7. 重命名为目标文件名
        let finalPath = try renameFile(from: decompressedPath, to: targetFilename)
        AppLogger.info("内核文件准备完成: \(finalPath)")

        return finalPath
    }

    /// 清理临时文件
    func cleanupTemporaryFiles() {
        do {
            if FileManager.default.fileExists(atPath: tempDirectory.path) {
                try FileManager.default.removeItem(at: tempDirectory)
                AppLogger.debug("已清理临时目录")
            }
        } catch {
            AppLogger.warning("清理临时目录失败: \(error.localizedDescription)")
        }
    }

    // MARK: - Private Methods

    /// 解析 GitHub Releases URL
    ///
    /// 支持的格式:
    /// - https://github.com/owner/repo/releases
    /// - https://github.com/owner/repo
    ///
    /// - Parameter url: GitHub URL
    /// - Returns: (owner, repo) 元组
    private func parseGitHubURL(_ url: String) throws -> (owner: String, repo: String) {
        // 移除末尾的斜杠和 /releases
        var cleanURL = url.trimmingCharacters(in: .whitespaces)
        if cleanURL.hasSuffix("/") {
            cleanURL.removeLast()
        }
        if cleanURL.hasSuffix("/releases") {
            cleanURL = String(cleanURL.dropLast("/releases".count))
        }

        // 解析 owner 和 repo
        guard let urlObj = URL(string: cleanURL),
              urlObj.host == "github.com",
              urlObj.pathComponents.count >= 3 else {
            throw MihomoDownloadError.invalidGitHubURL(url)
        }

        let owner = urlObj.pathComponents[1]
        let repo = urlObj.pathComponents[2]

        return (owner, repo)
    }

    /// 获取最新预发布版本
    private func fetchLatestPrerelease(owner: String, repo: String) async throws -> GitHubRelease {
        let apiURL = "\(githubAPIBase)/\(owner)/\(repo)/releases"

        guard let url = URL(string: apiURL) else {
            throw MihomoDownloadError.invalidGitHubURL(apiURL)
        }

        AppLogger.debug("请求 GitHub API: \(apiURL)")

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        request.setValue("NetCue/1.0", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw MihomoDownloadError.networkError("无效的响应")
        }

        guard httpResponse.statusCode == 200 else {
            throw MihomoDownloadError.networkError("HTTP \(httpResponse.statusCode)")
        }

        let releases = try JSONDecoder().decode([GitHubRelease].self, from: data)

        // 查找最新的预发布版本
        guard let prerelease = releases.first(where: { $0.prerelease }) else {
            throw MihomoDownloadError.noPrerelease
        }

        return prerelease
    }

    /// 查找匹配的 asset
    private func findMatchingAsset(release: GitHubRelease, filenameTemplate: String) -> GitHubAsset? {
        // 查找以模板开头且以 .gz 结尾的文件
        return release.assets.first { asset in
            asset.name.hasPrefix(filenameTemplate) && asset.name.hasSuffix(".gz")
        }
    }

    /// 准备临时目录
    private func prepareTemporaryDirectory() throws {
        let fm = FileManager.default

        // 如果目录存在，先删除
        if fm.fileExists(atPath: tempDirectory.path) {
            try fm.removeItem(at: tempDirectory)
        }

        // 创建目录
        try fm.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        AppLogger.debug("已创建临时目录: \(tempDirectory.path)")
    }

    /// 下载 asset（带重试机制）
    private func downloadAsset(asset: GitHubAsset, progressHandler: ProgressHandler?) async throws -> String {
        guard let url = URL(string: asset.browserDownloadUrl) else {
            throw MihomoDownloadError.invalidDownloadURL(asset.browserDownloadUrl)
        }

        let destinationPath = tempDirectory.appendingPathComponent(asset.name)

        AppLogger.debug("开始下载: \(url.absoluteString)")
        AppLogger.debug("目标路径: \(destinationPath.path)")

        var lastError: Error?

        for attempt in 1...maxRetryCount {
            do {
                if attempt > 1 {
                    AppLogger.info("第 \(attempt) 次重试下载...")
                    try await Task.sleep(nanoseconds: retryDelay)
                }

                let result = try await performDownload(
                    url: url,
                    destinationPath: destinationPath,
                    progressHandler: progressHandler
                )
                return result
            } catch {
                lastError = error
                let errorMessage = (error as NSError).localizedDescription

                // 检查是否是可重试的网络错误
                if isRetryableError(error) {
                    AppLogger.warning("下载失败 (尝试 \(attempt)/\(maxRetryCount)): \(errorMessage)")
                    if attempt < maxRetryCount {
                        continue
                    }
                } else {
                    // 不可重试的错误，直接抛出
                    throw error
                }
            }
        }

        // 所有重试都失败
        throw MihomoDownloadError.downloadFailed("网络连接失败，已重试 \(maxRetryCount) 次: \(lastError?.localizedDescription ?? "未知错误")")
    }

    /// 判断错误是否可以重试
    private func isRetryableError(_ error: Error) -> Bool {
        let nsError = error as NSError

        // URLError 的可重试错误码
        let retryableURLErrorCodes: Set<Int> = [
            NSURLErrorNetworkConnectionLost,        // -1005: 网络连接丢失
            NSURLErrorNotConnectedToInternet,       // -1009: 未连接到互联网
            NSURLErrorTimedOut,                     // -1001: 请求超时
            NSURLErrorCannotConnectToHost,          // -1004: 无法连接到主机
            NSURLErrorCannotFindHost,               // -1003: 找不到主机
            NSURLErrorDNSLookupFailed,              // -1006: DNS 查找失败
            NSURLErrorSecureConnectionFailed,       // -1200: 安全连接失败
        ]

        return nsError.domain == NSURLErrorDomain && retryableURLErrorCodes.contains(nsError.code)
    }

    /// 执行实际的下载操作
    private func performDownload(
        url: URL,
        destinationPath: URL,
        progressHandler: ProgressHandler?
    ) async throws -> String {
        // 使用针对大文件优化的配置
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 300
        config.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
            "Accept": "*/*"
        ]
        
        // 增加并发连接数以提升速度（虽然单个下载可能效果有限，但有助于绕过限制）
        config.httpMaximumConnectionsPerHost = 8
        
        let session = URLSession(configuration: config, delegate: nil, delegateQueue: nil)
        
        // 使用 URLSession.shared.download 提升效率，减少内存占用
        let (tempURL, response) = try await session.download(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw MihomoDownloadError.downloadFailed("HTTP 请求失败，状态码: \((response as? HTTPURLResponse)?.statusCode ?? -1)")
        }

        // 下载完成后移动到目标路径
        if FileManager.default.fileExists(atPath: destinationPath.path) {
            try FileManager.default.removeItem(at: destinationPath)
        }
        try FileManager.default.moveItem(at: tempURL, to: destinationPath)

        progressHandler?(1.0)
        AppLogger.debug("下载并移动完成: \(destinationPath.lastPathComponent)")

        return destinationPath.path
    }

    /// 解压 gzip 文件
    ///
    /// 使用 Swift 原生 Compression 框架解压
    private func decompressGzip(at path: String) throws -> String {
        let sourceURL = URL(fileURLWithPath: path)
        let outputFilename = sourceURL.deletingPathExtension().lastPathComponent
        let outputURL = tempDirectory.appendingPathComponent(outputFilename)

        AppLogger.debug("开始解压: \(path)")

        // 读取 gzip 数据
        let compressedData = try Data(contentsOf: sourceURL)

        // 解压 gzip
        guard let decompressedData = decompressGzipData(compressedData) else {
            throw MihomoDownloadError.decompressionFailed
        }

        // 写入解压后的文件
        try decompressedData.write(to: outputURL)

        // 设置可执行权限
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: outputURL.path
        )

        AppLogger.debug("解压完成: \(outputURL.path)")

        return outputURL.path
    }

    /// 使用 Compression 框架解压 gzip 数据
    private func decompressGzipData(_ data: Data) -> Data? {
        // Gzip 文件头检查
        guard data.count >= 10,
              data[0] == 0x1f,
              data[1] == 0x8b else {
            AppLogger.error("无效的 gzip 文件头")
            return nil
        }

        // 跳过 gzip 头部（10 字节基本头 + 可选字段）
        var headerSize = 10
        let flags = data[3]

        // FEXTRA
        if flags & 0x04 != 0 {
            guard data.count > headerSize + 2 else { return nil }
            let extraLen = Int(data[headerSize]) | (Int(data[headerSize + 1]) << 8)
            headerSize += 2 + extraLen
        }

        // FNAME
        if flags & 0x08 != 0 {
            while headerSize < data.count && data[headerSize] != 0 {
                headerSize += 1
            }
            headerSize += 1  // 跳过 null 终止符
        }

        // FCOMMENT
        if flags & 0x10 != 0 {
            while headerSize < data.count && data[headerSize] != 0 {
                headerSize += 1
            }
            headerSize += 1
        }

        // FHCRC
        if flags & 0x02 != 0 {
            headerSize += 2
        }

        // 提取压缩数据（去掉头部和尾部 8 字节的 CRC32 + ISIZE）
        guard data.count > headerSize + 8 else { return nil }
        let compressedData = data.subdata(in: headerSize..<(data.count - 8))

        // 使用 Compression 框架解压 (DEFLATE)
        let decompressedSize = 50 * 1024 * 1024  // 50MB 缓冲区
        var decompressedData = Data(count: decompressedSize)

        let result = decompressedData.withUnsafeMutableBytes { destBuffer in
            compressedData.withUnsafeBytes { sourceBuffer in
                compression_decode_buffer(
                    destBuffer.bindMemory(to: UInt8.self).baseAddress!,
                    decompressedSize,
                    sourceBuffer.bindMemory(to: UInt8.self).baseAddress!,
                    compressedData.count,
                    nil,
                    COMPRESSION_ZLIB
                )
            }
        }

        guard result > 0 else {
            AppLogger.error("解压失败: compression_decode_buffer 返回 \(result)")
            return nil
        }

        return decompressedData.prefix(result)
    }

    /// 重命名文件
    private func renameFile(from sourcePath: String, to targetFilename: String) throws -> String {
        let sourceURL = URL(fileURLWithPath: sourcePath)
        let targetURL = tempDirectory.appendingPathComponent(targetFilename)

        // 如果目标文件已存在，先删除
        if FileManager.default.fileExists(atPath: targetURL.path) {
            try FileManager.default.removeItem(at: targetURL)
        }

        try FileManager.default.moveItem(at: sourceURL, to: targetURL)

        return targetURL.path
    }

    /// 格式化文件大小
    ///
    /// 使用 macOS 12+ 的 `.formatted(.byteCount())` API
    private func formatFileSize(_ bytes: Int) -> String {
        Int64(bytes).formatted(.byteCount(style: .file))
    }
}

// MARK: - Download Errors

/// Mihomo 下载错误
enum MihomoDownloadError: LocalizedError {
    case invalidGitHubURL(String)
    case networkError(String)
    case noPrerelease
    case assetNotFound(String)
    case invalidDownloadURL(String)
    case downloadFailed(String)
    case decompressionFailed
    case fileOperationFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidGitHubURL(let url):
            return "无效的 GitHub URL: \(url)"
        case .networkError(let reason):
            return "网络错误: \(reason)"
        case .noPrerelease:
            return "未找到预发布版本"
        case .assetNotFound(let template):
            return "未找到匹配的文件: \(template)"
        case .invalidDownloadURL(let url):
            return "无效的下载地址: \(url)"
        case .downloadFailed(let reason):
            return "下载失败: \(reason)"
        case .decompressionFailed:
            return "解压失败"
        case .fileOperationFailed(let reason):
            return "文件操作失败: \(reason)"
        }
    }
}
