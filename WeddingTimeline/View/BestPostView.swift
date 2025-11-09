//
//  BestPostView.swift
//  WeddingTimeline
//
//  Created by 田口友暉 on 2025/07/13.
//

import SwiftUI
import AVKit

struct BestPostView: View {
    @Environment(Session.self) private var session
    @State private var vm = BestPostViewModel()

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                header
                filterChips

                if vm.isLoading && vm.top3.isEmpty {
                    skeletonCard(rank: 1)
                    skeletonCard(rank: 2)
                    skeletonCard(rank: 3)
                } else if !vm.errorMessage.isNilOrEmpty {
                    Text(vm.errorMessage ?? "")
                        .foregroundStyle(.secondary)
                        .padding(.top, 24)
                } else {
                    ForEach(vm.top3.indices, id: \.self) { i in
                        RankCard(model: vm.top3[i], rank: i + 1)
                            .padding(.horizontal, 16)
                    }
                }
            }
            .padding(.vertical, 16)
        }
        .navigationTitle("ベストポスト")
        .task { await vm.loadTop3(roomId: session.currentRoomId) }
        .onChange(of: vm.selectedTag) { _, _ in
            Task { await vm.loadTop3(roomId: session.currentRoomId) }
        }
        .refreshable { await vm.loadTop3(roomId: session.currentRoomId) }
    }

    // MARK: - Header
    private var header: some View {
        VStack(spacing: 8) {
            Text("🎉 人気の投稿 🎉")
                .font(.title3).bold()
                .foregroundStyle(Color.pink)
            Text("みんなに愛されている投稿です")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(Color.pink.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, 16)
    }

    // MARK: - Filter Chips
    private var filterChips: some View {
        HStack(spacing: 12) {
            FilterChip(
                title: "すべて",
                systemName: "sparkles",
                isSelected: vm.selectedTag == nil
            ) { vm.selectedTag = nil }

            FilterChip(
                title: "挙式",
                systemName: "heart",
                isSelected: vm.selectedTag == .ceremony
            ) { vm.selectedTag = .ceremony }

            FilterChip(
                title: "披露宴",
                systemName: "fork.knife",
                isSelected: vm.selectedTag == .reception
            ) { vm.selectedTag = .reception }
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Skeleton
    private func skeletonCard(rank: Int) -> some View {
        RankCardSkeleton(rank: rank)
            .padding(.horizontal, 16)
    }
}

// MARK: - Components
private struct FilterChip: View {
    let title: String
    let systemName: String
    let isSelected: Bool
    let onTap: () -> Void
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                Image(systemName: systemName)
                Text(title)
            }
            .font(.system(size: 14, weight: .semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(isSelected ? Color.pink.opacity(0.15) : Color(.systemBackground))
            .overlay(
                Capsule().stroke(isSelected ? .clear : Color.secondary.opacity(0.2), lineWidth: 1)
            )
            .foregroundStyle(isSelected ? Color.pink : Color.primary)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

private struct RankCard: View {
    let model: TimeLinePost
    let rank: Int

    @State private var galleryStartIndex = 0
    @State private var isGalleryPresented = false

    // Gold / Silver / Bronze
    var accent: Color {
        switch rank {
        case 1: // Gold #FFD700
            return Color(red: 1.0, green: 0.843, blue: 0.0)
        case 2: // Silver #C0C0C0
            return Color(red: 0.753, green: 0.753, blue: 0.753)
        default: // Bronze #CD7F32
            return Color(red: 0.804, green: 0.498, blue: 0.196)
        }
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    AvatarView(userIcon: model.userIcon)
                        .frame(width: 44, height: 44)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(model.userName).font(.headline)
                        // ここに @handle / 時刻 等を足したければ追加
                    }
                    Spacer()
                }

                if model.tag != .unknown {
                    tagPill
                }

                Text(model.content)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)

                if let mediaType = model.media.first?.type, mediaType != .unknown {
                    // 画像URL配列と動画URLを抽出
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
                        }
                    )
                    .fullScreenCover(isPresented: $isGalleryPresented) {
                        ImageGalleryView(
                            urls: imageURLs,
                            startIndex: galleryStartIndex
                        )
                    }
                }

                HStack(spacing: 20) {
                    Label("\(model.likeCount)", systemImage: "heart")
                    Label("\(model.replyCount)", systemImage: "bubble.left")
                }
                .foregroundStyle(.secondary)
                .font(.subheadline)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
                    .shadow(color: .black.opacity(0.06), radius: 8, y: 4)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(accent.opacity(0.6), lineWidth: 1.5)
            )

            rankBadge
        }
    }

    private var rankBadge: some View {
        Text("#\(rank)位")
            .font(.footnote).bold()
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .foregroundStyle(accent)
            .background(accent.opacity(0.12))
            .clipShape(Capsule())
            .overlay(
                Capsule().stroke(accent.opacity(0.25), lineWidth: 1)
            )
            .padding(10)
    }

    private var tagPill: some View {
        HStack(spacing: 6) {
            Image(systemName: model.tag == .ceremony ? "heart" : "fork.knife")
            Text(model.tag == .ceremony ? "挙式" : "披露宴")
                .fontWeight(.semibold)
        }
        .font(.caption)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background((model.tag == .ceremony ? Color.pink : Color.purple).opacity(0.12))
        .foregroundStyle(model.tag == .ceremony ? Color.pink : Color.purple)
        .clipShape(Capsule())
    }
}

private struct RankCardSkeleton: View {
    let rank: Int
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 22).fill(.gray.opacity(0.25)).frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 8) {
                    RoundedRectangle(cornerRadius: 4).fill(.gray.opacity(0.25)).frame(width: 120, height: 12)
                    RoundedRectangle(cornerRadius: 4).fill(.gray.opacity(0.2)).frame(width: 80, height: 10)
                }
            }
            RoundedRectangle(cornerRadius: 4).fill(.gray.opacity(0.2)).frame(height: 12)
            RoundedRectangle(cornerRadius: 4).fill(.gray.opacity(0.2)).frame(height: 12)
            HStack { RoundedRectangle(cornerRadius: 4).fill(.gray.opacity(0.2)).frame(width: 80, height: 10); Spacer() }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay(alignment: .topTrailing) {
            Text("#\(rank)位").font(.footnote).bold().padding(.horizontal, 10).padding(.vertical, 6).background(.ultraThinMaterial).clipShape(Capsule()).padding(10)
        }
    }
}

private struct AvatarView: View {
    let userIcon: String
    var body: some View {
        if let url = URL(string: userIcon), userIcon.hasPrefix("http") {
            AsyncImage(url: url) { img in
                img.resizable().scaledToFill()
            } placeholder: {
                Circle().fill(.gray.opacity(0.2))
            }
            .clipShape(Circle())
        } else {
            Image(userIcon)
                .resizable()
                .scaledToFill()
                .clipShape(Circle())
        }
    }
}

private extension Optional where Wrapped == String {
    var isNilOrEmpty: Bool { self?.isEmpty ?? true }
}

#Preview {
    // BestPostView()
}
