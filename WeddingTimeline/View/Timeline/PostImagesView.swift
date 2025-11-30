//
//  PostImagesView.swift
//  WeddingTimeline
//
//  Created by 田口友暉 on 2025/10/15.
//

import SwiftUI
import Nuke
import NukeUI

// MARK: - Split: Images only (single / grid)
struct PostImagesView: View {
    let urls: [URL]
    var onTapImageAt: ((Int) -> Void)? = nil

    private let grid = [GridItem(), GridItem()]

    var body: some View {
        if let url = urls.first, urls.count == 1 {
            LazyImage(url: url) { state in
                if let image = state.image {
                    image
                        .resizable()
                        .scaledToFill()
                } else if state.error != nil {
                    Image(systemName: "photo")
                        .resizable()
                        .scaledToFit()
                        .foregroundStyle(.secondary)
                        .background(Color.gray.opacity(0.2))
                } else {
                    ShimmerPlaceholder(cornerRadius: 10)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 180)
            .clipped()
            .cornerRadius(10)
            .transition(.opacity)
            .contentShape(Rectangle())
            .onTapGesture { onTapImageAt?(0) }
        } else {
            LazyVGrid(columns: grid, spacing: 4) {
                ForEach(Array(urls.enumerated()), id: \.offset) { idx, url in
                    LazyImage(url: url) { state in
                        if let image = state.image {
                            image
                                .resizable()
                                .scaledToFill()
                        } else if state.error != nil {
                            Image(systemName: "photo")
                                .resizable()
                                .scaledToFit()
                                .foregroundStyle(.secondary)
                                .background(Color.gray.opacity(0.2))
                        } else {
                            ShimmerPlaceholder(cornerRadius: 6)
                        }
                    }
                    .frame(height: 100)
                    .clipped()
                    .cornerRadius(6)
                    .transition(.opacity)
                    .contentShape(Rectangle())
                    .onTapGesture { onTapImageAt?(idx) }
                }
            }
        }
    }
}

#Preview {
    // PostImagesView()
}
