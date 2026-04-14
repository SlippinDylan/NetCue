//
//  IPQualityCardIdleView.swift
//  NetCue
//
//  Created by SlippinDylan on 2026/01/07.
//  网络工具 - IP质量卡片 - 闲置状态
//

import SwiftUI

/// 网络工具卡片 - 闲置状态视图
///
/// ## 设计说明
/// - 整个 GroupBox 内容区域可点击
/// - 文字水平垂直居中显示
/// - 点击后开始检测
struct IPQualityCardIdleView: View {
    // MARK: - Properties

    let onStart: () -> Void

    // MARK: - Body

    var body: some View {
        HStack {
            Spacer()
            Label("开始检测", systemImage: "play.fill")
                .font(.headline)
                .foregroundStyle(.blue)
            Spacer()
        }
        .padding(.vertical, 16)
        .contentShape(Rectangle())
        .onTapGesture {
            onStart()
        }
    }
}

// MARK: - Preview

#Preview {
    GroupBox {
        IPQualityCardIdleView(onStart: {})
            .padding()
    } label: {
        Text("IP 质量")
    }
    .frame(width: 800)
}
