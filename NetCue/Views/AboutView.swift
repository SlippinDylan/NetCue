//
//  AboutView.swift
//  NetCue
//
//  Created by SlippinDylan on 2026/03/09.
//  关于页面 - 适配 Cleanroom 设计风格
//

import SwiftUI

struct AboutView: View {
    /// 从 Bundle 中获取应用版本号
    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: DesignSystem.Spacing.extraLarge) {
                // 应用图标
                if let appIcon = NSImage(named: "AppIcon") {
                    Image(nsImage: appIcon)
                        .resizable()
                        .frame(width: 128, height: 128)
                        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large))
                        .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 4)
                } else {
                    // 兜底图标
                    ZStack {
                        RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large)
                            .fill(LinearGradient(colors: [.blue, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 128, height: 128)
                        
                        Image(systemName: "wifi.router.fill")
                            .font(.system(size: 64))
                            .foregroundStyle(.white)
                    }
                    .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 4)
                }

                VStack(spacing: DesignSystem.Spacing.small) {
                    Text("NetCue")
                        .font(.system(size: 32, weight: .bold))
                        .tracking(1.0)

                    Text("版本 \(appVersion)")
                        .font(.system(size: DesignSystem.FontSize.body))
                        .foregroundStyle(.secondary)
                }

                VStack(spacing: DesignSystem.Spacing.medium) {
                    Text("极简、高效、智能的网络自动化工具")
                        .font(.system(size: DesignSystem.FontSize.body))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, DesignSystem.Spacing.large)

                    Divider()
                        .frame(width: 200)
                        .padding(.vertical, DesignSystem.Spacing.small)

                    VStack(spacing: DesignSystem.Spacing.extraSmall) {
                        Text("Copyright © 2025-2026 SlippinDylan Studio")
                            .font(.system(size: DesignSystem.FontSize.caption))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .padding(.bottom, DesignSystem.Spacing.extraLarge * 2)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    AboutView()
}
