//
//  SectionHeader.swift
//  NetCue
//
//  Created by SlippinDylan on 2025/12/25.
//

import SwiftUI

struct SectionHeader: View {
    let title: String
    let icon: String
    let iconColor: Color
    var description: String? = nil

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 18, height: 18)
                .background(iconColor)
                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small))

            Text(title)
                .font(.system(size: 15, weight: .semibold))

            if let description = description {
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.bottom, 8)
    }
}
