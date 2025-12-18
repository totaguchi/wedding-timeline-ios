//
//  TimelinePostView.swift
//  WeddingTimeline
//
//  Created by 田口友暉 on 2025/07/13.
//

import SwiftUI
import AVKit
import CryptoKit

struct TimelinePostView: View {
    let model: TimelinePost
    let enableNavigation: Bool
    let onToggleLike: (Bool) -> Void
    let onPostDelete: (@Sendable (String) async -> Bool)
    let icons = [
        "oomimigitsune", "lesser_panda", "bear",
        "todo", "musasabi", "rakko"
    ]
    @State private var galleryStartIndex = 0
    @State private var isGalleryPresented = false
    @State private var likeBusy = false
    @Environment(Session.self) private var session
    
    // 表示タグ設定（常時 username の後ろに @xxxx を付ける）
    var useRoomScopedTag: Bool = true   // true: roomId + uid のハッシュでルームごとに変化
    var tagLength: Int = 4              // 既定は4文字（@abcd）
    
    init(model: TimelinePost, enableNavigation: Bool = true, onToggleLike: @escaping (Bool) -> Void, onPostDelete: @escaping (@Sendable (String) async -> Bool)) {
        self.model = model
        self.enableNavigation = enableNavigation
        self.onToggleLike = onToggleLike
        self.onPostDelete = onPostDelete
    }
    
    var body: some View {
        HStack(alignment: .top) {
            if model.userIcon.isEmpty || !icons.contains(model.userIcon) {
                Image(systemName: "person.crop.circle.fill")
                    .resizable()
                    .frame(width: 40, height: 40)
                    .clipShape(Circle())
            } else {
                Image(model.userIcon)
                    .resizable()
                    .frame(width: 40, height: 40)
                    .clipShape(Circle())
            }

            VStack(alignment: .leading, spacing: 5) {
                if enableNavigation {
                    NavigationLink {
                        PostDetailView(model: model, onToggleLike: onToggleLike, onPostDelete: onPostDelete)
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
                    // TODO: コメント機能は未定
//                    HStack(spacing: 4) {
//                        Image(systemName: "bubble.left")
//                        Text("\(model.replyCount)")
//                    }
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
                                .foregroundStyle(model.isLiked ? TLColor.fillPink500 : TLColor.icoAction)
                            Text("\(model.likeCount)")
                                .foregroundStyle(TLColor.textMeta)
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
                let tag = displayTag(for: model, roomId: session.currentRoomId)
                HStack(spacing: 0) {
                    Text(model.userName)
                        .font(.subheadline).fontWeight(.semibold)
                        .foregroundStyle(TLColor.textAuthor)
                    Text(" \(tag)").font(.caption).foregroundStyle(TLColor.textMeta)
                }
                Text(DateFormatter.appCreatedAt.string(from: model.createdAt))
                    .font(.caption)
                    .foregroundStyle(TLColor.textMeta)
                Spacer()
            }
            if model.tag != .unknown {
                tagChip
            }
            Text(model.content)
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(TLColor.textBody)
        }
    }

    @ViewBuilder
    private var tagChip: some View {
        switch model.tag {
        case .ceremony:
            TagPill(tag: .ceremony)
        case .reception:
            TagPill(tag: .reception)
        default:
            EmptyView()
        }
    }

    private struct TagPill: View {
        let tag: PostTag
        var body: some View {
            let isCeremony = tag == .ceremony
            let bgColor = isCeremony ? TLColor.badgeCeremonyBg : TLColor.badgeReceptionBg
            let textColor = isCeremony ? TLColor.badgeCeremonyText : TLColor.badgeReceptionText
            let borderColor = isCeremony ? TLColor.borderBadgeCeremony : TLColor.borderBadgeReception
            HStack(spacing: 6) {
                Image(systemName: tag.icon)
                Text(tag.displayName)
                    .font(.caption)
                    .fontWeight(.semibold)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(bgColor)
            .foregroundStyle(textColor)
            .overlay(
                Capsule().stroke(borderColor, lineWidth: 1)
            )
            .clipShape(Capsule())
        }
    }
        
    /// 投稿モデル用のタグ生成（ビューから呼びやすいヘルパー）
    func displayTag(for post: TimelinePost, roomId: String) -> String {
        DisplayTag.make(roomId: roomId, uid: post.authorId)
    }
}

#Preview("画像1枚") {
    NavigationStack {
        ScrollView {
            TimelinePostView(
                model: TimelinePost(
                    id: "preview-1",
                    authorId: "user-123",
                    userName: "田中太郎",
                    userIcon: "lesser_panda",
                    content: "結婚式の準備が着々と進んでいます！ドレスも決まりました✨",
                    createdAt: Date(),
                    replyCount: 3,
                    retweetCount: 0,
                    likeCount: 12,
                    media: [
                        Media(
                            id: "media-1",
                            type: .image,
                            mediaUrl: URL(string: "file:///lesser_panda")!,
                            pixelSize: CGSize(width: 800, height: 600),
                            duration: nil,
                            storagePath: nil
                        )
                    ],
                    isLiked: false,
                    tag: .ceremony
                ),
                onToggleLike: { _ in }, onPostDelete: { _ in false }
            )
            .padding()
        }
    }
}

#Preview("画像複数枚") {
    NavigationStack {
        ScrollView {
            TimelinePostView(
                model: TimelinePost(
                    id: "preview-2",
                    authorId: "user-456",
                    userName: "山田花子",
                    userIcon: "lesser_panda",
                    content: "披露宴の会場写真です🎉 テーブルコーディネートも完璧！",
                    createdAt: Date().addingTimeInterval(-3600),
                    replyCount: 8,
                    retweetCount: 2,
                    likeCount: 45,
                    media: [
                        Media(
                            id: "media-2",
                            type: .image,
                            mediaUrl: URL(string: "file:///lesser_panda")!,
                            pixelSize: CGSize(width: 800, height: 600),
                            duration: nil,
                            storagePath: nil
                        ),
                        Media(
                            id: "media-3",
                            type: .image,
                            mediaUrl: URL(string: "file:///lesser_panda")!,
                            pixelSize: CGSize(width: 600, height: 800),
                            duration: nil,
                            storagePath: nil
                        ),
                        Media(
                            id: "media-4",
                            type: .image,
                            mediaUrl: URL(string: "file:///lesser_panda")!,
                            pixelSize: CGSize(width: 800, height: 600),
                            duration: nil,
                            storagePath: nil
                        )
                    ],
                    isLiked: true,
                    tag: .reception
                ),
                onToggleLike: { _ in }, onPostDelete: { _ in false }
            )
            .padding()
        }
    }
}
