//
//  CategoryFilterBar.swift
//  WeddingTimeline
//
//  Created by 田口友暉 on 2025/11/03.
//

import SwiftUI

struct CategoryFilterBar: View {
    @Bindable var vm: TimeLineViewModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(vm.availableFilters) { f in
                    let isSel = vm.selectedFilter == f
                    Button {
                        vm.selectedFilter = f
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: f.icon)
                            Text(f.rawValue)
                        }
                        .font(.system(size: 14, weight: .semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(isSel ? Color.pink.opacity(0.15) : Color(.systemBackground))
                        .overlay(
                            Capsule()
                                .stroke(isSel ? Color.pink : Color(.separator), lineWidth: isSel ? 0 : 1)
                        )
                        .foregroundStyle(isSel ? Color.pink : Color.primary)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }
}

#Preview {
    // CategoryFilterBar()
}
