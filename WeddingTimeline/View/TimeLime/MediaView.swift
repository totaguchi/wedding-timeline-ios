//
//  MediaView.swift
//  WeddingTimeline
//
//  Created by 田口友暉 on 2025/07/13.
//

import AVKit
import SwiftUI

struct MediaView: View {
    let mediaType: MediaKind
    let mediaUrls: [URL]
    var onTapImageAt: ((Int) -> Void)? = nil

    var body: some View {
        switch mediaType {
        case .image:
            PostImagesView(urls: mediaUrls, onTapImageAt: onTapImageAt)
        case .video:
            if let remote = mediaUrls.first {
                AutoPlayVideoView(url: remote)
            }
        case .unknown:
            EmptyView()
        }
    }
}

#Preview {
//    let model1 = TimeLinePostModel(userName: "山田太郎", userIcon: "person.fill", content: "投稿テキスト", time: Date(), imageContents: ["sun.max.circle"], replyCount: 0, retweetCount: 0, likeCount: 0)
//    MediaView(media: .singleImage(name: model1.imageContents[0]))
//    let model2 = TimeLinePost(id: "1", authorId: "test", userName: "山田太郎", userIcon: "person.fill", content: "投稿テキスト", createdAt: Date(), replyCount: 0, retweetCount: 0,likeCount: 0, media: [])
//    MediaView(mediaType: .video, mediaUrls: ["sample001"])
}
