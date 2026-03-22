//
//  ZoomableAsyncImage.swift
//  WeddingTimeline
//
//  Created by 田口友暉 on 2025/11/26.
//

import SwiftUI
import NukeUI

struct ZoomableAsyncImage: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var reloadToken = UUID()

    var body: some View {
        GeometryReader { geo in
            let doubleTap = TapGesture(count: 2).onEnded {
                withAnimation(.easeInOut) {
                    if scale > 1 {
                        scale = 1
                        offset = .zero
                        lastOffset = .zero
                    } else {
                        scale = 2
                        lastScale = 2
                    }
                }
            }

            LazyImage(url: url) { state in
                if let image = state.image {
                    image
                        .resizable()
                        .scaledToFit()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .scaleEffect(scale)
                        .offset(offset)
                        .gesture(
                            MagnificationGesture()
                                .onChanged { value in
                                    let newScale = lastScale * value
                                    scale = min(max(newScale, 1), 4)
                                }
                                .onEnded { _ in
                                    lastScale = scale
                                }
                        )
                        .overlay(
                            Group {
                                if scale > 1 {
                                    Color.clear
                                        .contentShape(Rectangle())
                                        .gesture(
                                            DragGesture()
                                                .onChanged { value in
                                                    let t = value.translation
                                                    offset = CGSize(width: lastOffset.width + t.width,
                                                                    height: lastOffset.height + t.height)
                                                }
                                                .onEnded { _ in
                                                    lastOffset = offset
                                                }
                                        )
                                }
                            }
                        )
                        .highPriorityGesture(
                            DragGesture(minimumDistance: 20)
                                .onEnded { value in
                                    let t = value.translation
                                    let isVertical = abs(t.height) > abs(t.width)
                                    if isVertical && t.height > 120 && scale <= 1.05 {
                                        dismiss()
                                    }
                                }
                        )
                        .gesture(doubleTap)
                } else if let error = state.error {
                    VStack(spacing: 12) {
                        Image(systemName: "photo")
                            .resizable()
                            .scaledToFit()
                            .foregroundStyle(TLColor.icoAction)
                            .frame(maxWidth: geo.size.width * 0.35)
                        Button("再読み込み") {
                            print("[Gallery] retry url=\(url)")
                            reloadToken = UUID()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .frame(width: geo.size.width, height: geo.size.height)
                    .onAppear {
                        print("[Gallery] image load failed url=\(url) error=\(error)")
                    }
                } else {
                    ZStack { Color.black; ProgressView() }
                        .frame(width: geo.size.width, height: geo.size.height)
                }
            }
            .id(reloadToken)
            .background(Color.black)
            .ignoresSafeArea()
        }
    }
}

#Preview {
    // ZoomableAsyncImage()
}
