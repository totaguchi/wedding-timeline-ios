//
//  TagChip.swift
//  WeddingTimeline
//
//  Created by 田口友暉 on 2025/11/17.
//

import SwiftUI

struct TagChip: View {
    let tag: PostTag
    let isSelected: Bool
    let onTap: () -> Void
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                Image(systemName: tag.icon)
                Text(tag.displayName)
            }
            .font(.system(size: 15, weight: .semibold))
            .padding(.vertical, 10)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity)
            .background(isSelected ? Color.pink.opacity(0.15) : Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isSelected ? Color.clear : Color.secondary.opacity(0.25), lineWidth: 1)
            )
            .foregroundStyle(isSelected ? Color.pink : Color.primary)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}


#Preview {
    TagChip(tag: .ceremony, isSelected: true, onTap: {})
}
