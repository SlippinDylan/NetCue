//
//  TabGroupPicker.swift
//  NetCue
//
//  Created by SlippinDylan on 2025/12/25.
//

import SwiftUI

struct TabGroupPicker: View {
    @Binding var selectedTab: Int

    let tabs = ["网络监控", "DNS管理", "IP查询", "隐私检测", "设置"]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<tabs.count, id: \.self) { index in
                if selectedTab == index {
                    Button(action: {
                        selectedTab = index
                    }) {
                        Text(tabs[index])
                            .font(.system(size: 13))
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                } else {
                    Button(action: {
                        selectedTab = index
                    }) {
                        Text(tabs[index])
                            .font(.system(size: 13))
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                }
            }
        }
    }
}
