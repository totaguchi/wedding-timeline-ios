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
    let enableNavigation: Bool
    let onToggleLike: (Bool) -> Void
    @State private var galleryStartIndex = 0
    @State private var isGalleryPresented = false
    @State private var likeBusy = false
    
    init(model: TimeLinePost, enableNavigation: Bool = true, onToggleLike: @escaping (Bool) -> Void) {
        self.model = model
        self.enableNavigation = enableNavigation
        self.onToggleLike = onToggleLike
    }
    
    var body: some View {
        HStack(alignment: .top) {
            Image(model.userIcon)
                .resizable()
                .frame(width: 40, height: 40)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 5) {
                if enableNavigation {
                    NavigationLink {
                        PostDetailView(model: model)
                    } label: {
                        headerAndContent
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                } else {
                    headerAndContent
                }
                
                if let mediaType = model.media.first?.type,
                   mediaType != .unknown {
                    // 画像URL配列は一度だけ計算し、MediaView と Gallery で同順を使う
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
                    Button {
                        guard !likeBusy else { return }
                        likeBusy = true
                        let newValue = !model.isLiked
                        Task { @MainActor in
                            onToggleLike(newValue)
                            likeBusy = false
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: model.isLiked ? "heart.fill" : "heart")
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(model.isLiked ? .red : .primary)
                            Text("\(model.likeCount)")
                        }
                    }
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())
                    .disabled(likeBusy)
                }
                .font(.subheadline)
            }
        }
    }

    @ViewBuilder
    private var headerAndContent: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(model.userName)
                    .font(.subheadline)
                Text(model.createdAt.description)
                    .font(.caption)
                Spacer()
            }
            if model.tag != .unknown {
                tagChip
            }
            Text(model.content)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var tagChip: some View {
        switch model.tag {
        case .ceremony:
            TagPill(systemName: "heart", text: "挙式", tint: .pink)
        case .reception:
            TagPill(systemName: "fork.knife", text: "披露宴", tint: Color.purple)
        default:
            EmptyView()
        }
    }

    private struct TagPill: View {
        let systemName: String
        let text: String
        let tint: Color
        var body: some View {
            HStack(spacing: 6) {
                Image(systemName: systemName)
                Text(text)
                    .font(.caption)
                    .fontWeight(.semibold)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(tint.opacity(0.12))
            .foregroundStyle(tint)
            .clipShape(Capsule())
        }
    }
}

#Preview {
//    let model = TimeLinePost(id: "1", userName: "山田太郎", userIcon: "person.fill", content: "投稿テキスト", createdAt: Date(), mediaType: "singleImage", mediaUrls:["sun.max.circle"], replyCount: 0, retweetCount: 0, likeCount: 0)
//    TimeLinePostView(model: model)
}
