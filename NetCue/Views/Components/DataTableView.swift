//
//  DataTableView.swift
//  NetCue
//
//  Created by SlippinDylan on 2025/12/29.
//

import SwiftUI

/// 通用数据表格组件
struct DataTableView: View {
    let headers: [String]
    let rows: [[String]]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 表头
            HStack(spacing: 0) {
                ForEach(Array(headers.enumerated()), id: \.offset) { index, header in
                    Text(header)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)

                    if index < headers.count - 1 {
                        Divider()
                            .frame(height: 20)
                    }
                }
            }
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // 表格内容
            ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, row in
                HStack(spacing: 0) {
                    ForEach(Array(row.enumerated()), id: \.offset) { colIndex, cell in
                        Text(cell.isEmpty ? "-" : cell)
                            .font(.system(size: 13))
                            .foregroundStyle(cell.isEmpty ? Color.secondary : Color.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)

                        if colIndex < row.count - 1 {
                            Divider()
                                .frame(height: 20)
                        }
                    }
                }
                .background(rowIndex % 2 == 0 ? Color.clear : Color(NSColor.controlBackgroundColor).opacity(0.3))

                if rowIndex < rows.count - 1 {
                    Divider()
                }
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium)
                .stroke(Color(NSColor.separatorColor), lineWidth: 1)
        )
    }
}
