//
//  PostImagesView.swift
//  WeddingTimeline
//
//  Created by 田口友暉 on 2025/10/15.
//

import SwiftUI

// MARK: - Split: Images only (single / grid)
struct PostImagesView: View {
    let urls: [URL]
    var onTapImageAt: ((Int) -> Void)? = nil

    private let grid = [GridItem(), GridItem()]

    var body: some View {
        if let url = urls.first, urls.count == 1 {
            AsyncImage(url: url) { phase in
                switch phase {
                case .empty:
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .frame(height: 180)
                        .background(Color.gray.opacity(0.2))
                        .cornerRadius(10)
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity)
                        .frame(height: 180)
                        .clipped()
                        .cornerRadius(10)
                        .background(Color.gray.opacity(0.2))
                case .failure:
                    Image(systemName: "photo")
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                        .frame(height: 180)
                        .foregroundStyle(.secondary)
                        .background(Color.gray.opacity(0.2))
                        .cornerRadius(10)
                @unknown default:
                    EmptyView()
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { onTapImageAt?(0) }
        } else {
            LazyVGrid(columns: grid, spacing: 4) {
                ForEach(Array(urls.enumerated()), id: \ .offset) { idx, url in
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .empty:
                            ZStack { Color.gray.opacity(0.2); ProgressView() }
                                .frame(height: 100)
                                .cornerRadius(6)
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                                .frame(height: 100)
                                .clipped()
                                .cornerRadius(6)
                        case .failure:
                            Image(systemName: "photo")
                                .resizable()
                                .scaledToFit()
                                .frame(height: 100)
                                .foregroundStyle(.secondary)
                                .background(Color.gray.opacity(0.2))
                                .cornerRadius(6)
                        @unknown default:
                            EmptyView()
                        }
                    }
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
