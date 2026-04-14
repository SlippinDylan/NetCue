//
//  TabBar.swift
//  NetCue
//
//  Created by SlippinDylan on 2025/12/25.
//

import SwiftUI

struct TabBar: View {
    @Binding var selectedTab: Int

    let tabs = [
        ("网络监控", "network", 0),
        ("DNS管理", "server.rack", 1),
        ("IP查询", "magnifyingglass", 2),
        ("隐私检测", "shield.checkered", 3),
        ("设置", "gearshape", 4)
    ]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(tabs, id: \.2) { tab in
                TabBarItem(
                    title: tab.0,
                    icon: tab.1,
                    isSelected: selectedTab == tab.2
                ) {
                    selectedTab = tab.2
                }
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

struct TabBarItem: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                Text(title)
                    .font(.system(size: 13))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
            .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
        }
        .buttonStyle(.plain)
    }
}
