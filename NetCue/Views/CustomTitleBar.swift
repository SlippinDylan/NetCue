//
//  CustomTitleBar.swift
//  NetCue
//
//  Created by SlippinDylan on 2025/12/25.
//

import SwiftUI

struct CustomTitleBar: View {
    @Binding var selectedTab: Int

    var body: some View {
        HStack(spacing: 0) {
            // 左侧占位（为系统按钮留空间：68px）
            Color.clear
                .frame(width: 68)

            // 中间 Tab 组
            HStack(spacing: 0) {
                Spacer()
                TabGroupPicker(selectedTab: $selectedTab)
                    .padding(.top, 8)
                Spacer()
            }

            // 右侧应用名称
            Text("NetCue")
                .font(.headline)
                .foregroundStyle(.secondary)
                .padding(.trailing, 16)
        }
        .frame(height: 52)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
