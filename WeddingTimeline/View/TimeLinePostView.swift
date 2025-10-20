//
//  TimeLinePostView.swift
//  WeddingTimeline
//
//  Created by 田口友暉 on 2025/07/13.
//

import SwiftUI
import AVKit

struct TimeLinePostView: View {
    let model: TimeLinePost
    @State private var galleryStartIndex = 0
    @State private var isGalleryPresented = false
    
    var body: some View {
        HStack(alignment: .top) {
            Image(model.userIcon)
                .resizable()
                .frame(width: 40, height: 40)
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(model.userName)
                        .font(.subheadline)
                    Text(model.createdAt.description)
                        .font(.caption)
                    Spacer()
                }
                Text(model.content)
                    .fixedSize(horizontal: false, vertical: true)
                // TODO: Mediaの表示系を整理する
                // 動画は1件表示
                // 画像は4件まで表示
                if let mediaType = model.media.first?.type,
                   mediaType != .unknown {
                    // 画像のURL配列を一度だけ確定し、MediaView と Gallery の両方で同じ順序で使う
                    let imageURLs: [URL] = model.media
                        .filter { $0.type == .image }
                        .compactMap { $0.mediaUrl }
                    let videoURL: URL? = model.media.first(where: { $0.type == .video })?.mediaUrl
                    let mediaURLsForView: [URL] = (mediaType == .video) ? (videoURL.map { [$0] } ?? []) : imageURLs

                    MediaView(
                        mediaType: mediaType,
                        mediaUrls: mediaURLsForView,
                        onTapImageAt: { idx in
                            galleryStartIndex = idx
                            isGalleryPresented = true
                            debugPrint(model.id)
                        }
                    )
                    .fullScreenCover(isPresented: $isGalleryPresented) {
                        ImageGalleryView(
                            urls: imageURLs,
                            startIndex: galleryStartIndex
                        )
                    }
                }
                HStack(spacing: 30) {
                    HStack(spacing: 4) {
                        Image(systemName: "bubble.left")
                        Text("\(model.replyCount)")
                    }
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.2.squarepath")
                        Text("\(model.retweetCount)")
                    }
                    HStack(spacing: 4) {
                        Image(systemName: "heart")
                        Text("\(model.likeCount)")
                    }
                }
                .font(.subheadline)
            }
        }
    }
}

#Preview {
//    let model = TimeLinePost(id: "1", userName: "山田太郎", userIcon: "person.fill", content: "投稿テキスト", createdAt: Date(), mediaType: "singleImage", mediaUrls:["sun.max.circle"], replyCount: 0, retweetCount: 0, likeCount: 0)
//    TimeLinePostView(model: model)
}
