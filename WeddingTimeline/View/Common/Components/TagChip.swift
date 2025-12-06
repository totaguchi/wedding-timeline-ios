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
            .background {
                if isSelected {
                    LinearGradient(
                        colors: [TLColor.btnCategorySelFrom, TLColor.btnCategorySelTo],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                } else {
                    TLColor.btnCategoryUnselBg
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isSelected ? Color.clear : TLColor.btnCategoryUnselBorder, lineWidth: 1)
            )
            .foregroundStyle(isSelected ? TLColor.btnCategorySelText : TLColor.btnCategoryUnselText)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}


#Preview {
    TagChip(tag: .ceremony, isSelected: true, onTap: {})
}
