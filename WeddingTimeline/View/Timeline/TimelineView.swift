//
//  Timeline.swift
//  WeddingTimeline
//
//  Created by 田口友暉 on 2025/07/13.
//

import SwiftUI
import Nuke

// Scroll offset probe for top detection
private struct TLScrollTopKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct TimelineView: View {
    @Environment(Session.self) private var session
    @State private var model = TimelineViewModel()
    @State private var isShowingCreateView = false
    @State private var prefetcher = ImagePrefetcher()
    
    private var activeRoomId: String? {
        let id = session.currentRoomId.trimmingCharacters(in: .whitespacesAndNewlines)
        return id.isEmpty ? nil : id
    }
    
    var body: some View {
        ScrollViewReader { proxy in
            NavigationStack {
                VStack(spacing: 0) {
                    CategoryFilterBar(vm: model)
                    
                    Rectangle()
                        .frame(height: 1)
                        .foregroundStyle(TLColor.borderCard.opacity(0.15))
                    
                    ScrollView {
                        LazyVStack {
                            // Top anchor & offset publisher
                            Color.clear
                                .frame(height: 0)
                                .id("tl-top")
                                .background(
                                    GeometryReader { geo in
                                        Color.clear.preference(
                                            key: TLScrollTopKey.self,
                                            value: geo.frame(in: .named("TimelineScroll")).minY
                                        )
                                    }
                                )
                            ForEach(Array(model.filteredPosts.enumerated()), id: \.element.id) { index, post in
                                TimelinePostView(
                                    model: post,
                                    activeVideoPostId: model.activeVideoPostId
                                ) { isLiked in
                                    guard let roomId = activeRoomId else { return }
                                    Task {
                                        await model.toggleLike(model: post, roomId: roomId, isLiked: isLiked)
                                    }
                                } onPostDelete: { postId in
                                    let roomId = await MainActor.run { activeRoomId }
                                    guard let roomId else { return false }
                                    return await model.deletePost(roomId: roomId, postId: postId)
                                } onMuteChanged: { targetUid, isMuted in
                                    Task { @MainActor in
                                        model.applyMuteChange(targetUid: targetUid, isMuted: isMuted)
                                    }
                                }
                                .padding(.horizontal, 10)
                                .onAppear {
                                    if index == model.filteredPosts.count - 1 {
                                        guard let roomId = activeRoomId else { return }
                                        Task { await model.fetchPosts(roomId: roomId) }
                                    }
                                    preheatAround(index: index, ahead: 12)
                                }
                                .onDisappear {
                                    cancelPreheatAround(index: index, ahead: 20)
                                }
                                if index < model.filteredPosts.count - 1 {
                                    Rectangle()
                                        .frame(height: 1)
                                        .foregroundStyle(TLColor.borderCard.opacity(0.15))
                                }
                            }
                        }
                    }
                    .coordinateSpace(name: "TimelineScroll")
                    .safeAreaInset(edge: .top) {
                        if model.newBadgeCount > 0 && !model.isAtTop {
                            Button {
                                withAnimation { proxy.scrollTo("tl-top", anchor: .top) }
                                Task { model.revealPending() }
                            } label: {
                                Text("— \(model.newBadgeCount) 件の新着ポスト —")
                                    .font(.footnote.bold())
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(.thinMaterial, in: Capsule())
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.top, 4)
                            .transition(.move(edge: .top).combined(with: .opacity))
                        }
                    }
                }
            }
            .fullScreenCover(isPresented: $isShowingCreateView, onDismiss: {
                // Sheet dismissed -> scroll to top
                withAnimation {
                    proxy.scrollTo("tl-top", anchor: .top)
                }
            }) {
                if let roomId = activeRoomId {
                    PostCreateView(roomId: roomId)
                        .toolbar(.hidden, for: .tabBar) // Hide tab bar while the full-screen cover is shown
                }
            }
        }
        .refreshable {
            guard let roomId = activeRoomId else { return }
            await model.refreshHead(roomId: roomId)
        }
        // 画面表示で購読開始
        .onAppear {
            guard let roomId = activeRoomId else { return }
            Task {
                await model.fetchPosts(roomId: roomId, reset: true)
                model.startListening(roomId: roomId)
            }
        }
        // 画面離脱で購読停止
        .onDisappear {
            Task { model.stopListening() }
        }
        .onChange(of: model.filteredPosts.count) {
            preheatInitialWindow()
        }
        .overlay(alignment: .bottomTrailing) {
            if !isShowingCreateView, activeRoomId != nil {
                Button {
                    isShowingCreateView = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .resizable()
                        .foregroundStyle(
                            LinearGradient(
                                colors: [TLColor.fabFrom, TLColor.fabTo],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: 50, height: 50)
                        .padding(.trailing, 20)
                        .padding(.bottom)
                }
            }
        }
        .toolbar(isShowingCreateView ? .hidden : .visible, for: .tabBar)
        // Top-of-list detection updates VM state
        .onPreferenceChange(TLScrollTopKey.self) { y in
            let atTop = y >= 0
            Task { model.markAtTop(atTop) }
        }
        .onPreferenceChange(VideoMidYKey.self) { values in
            updateActiveVideo(from: values)
        }
    }
    
    // MARK: - Video Playback
    private func updateActiveVideo(from values: [String: CGFloat]) {
        guard !values.isEmpty else {
            if model.activeVideoPostId != nil { model.activeVideoPostId = nil }
            return
        }

        let screenHeight = UIScreen.main.bounds.height
        let visible = values.filter { $0.value > -100 && $0.value < screenHeight + 100 }
        guard let best = visible.min(by: { abs($0.value - screenHeight / 2) < abs($1.value - screenHeight / 2) }) else {
            if model.activeVideoPostId != nil { model.activeVideoPostId = nil }
            return
        }

        if model.activeVideoPostId != best.key {
            model.activeVideoPostId = best.key
        }
    }

    // MARK: - Image Preheating (Nuke)
    private func preheatInitialWindow(size: Int = 24) {
        guard !model.filteredPosts.isEmpty else { return }
        let upper = min(size - 1, model.filteredPosts.count - 1)
        let urls = collectImageURLs(in: 0...upper)
        guard !urls.isEmpty else { return }
        prefetcher.startPrefetching(with: urls)
    }
    
    private func preheatAround(index: Int, ahead: Int) {
        let end = min(model.filteredPosts.count - 1, index + ahead)
        guard index <= end else { return }
        let urls = collectImageURLs(in: index...end)
        guard !urls.isEmpty else { return }
        prefetcher.startPrefetching(with: urls)
    }

    private func cancelPreheatAround(index: Int, ahead: Int) {
        let start = max(0, index - ahead)
        let end = min(model.filteredPosts.count - 1, index + ahead)
        guard start <= end else { return }
        let urls = collectImageURLs(in: start...end)
        guard !urls.isEmpty else { return }
        prefetcher.stopPrefetching(with: urls)
    }
    
    private func collectImageURLs(in range: ClosedRange<Int>) -> [URL] {
        var out: [URL] = []
        out.reserveCapacity((range.upperBound - range.lowerBound + 1) * 2)
        for i in range {
            guard i >= 0 && i < model.filteredPosts.count else { continue }
            let p = model.filteredPosts[i]
            // 画像系のみ対象（videoは除外）
            for m in p.media {
                if m.type == .image {
                    out.append(m.mediaUrl)
                }
            }
        }
        return out
    }
}

#Preview {
    TimelineView()
}
