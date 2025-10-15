//
//  TimeLineView.swift
//  WeddingTimeline
//
//  Created by 田口友暉 on 2025/07/13.
//

import SwiftUI

// Scroll offset probe for top detection
private struct TLScrollTopKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct TimeLineView: View {
    @Environment(Session.self) private var session
    @State private var model = TimeLineViewModel()
    @State private var isShowingCreateView = false
    
    var body: some View {
        ScrollViewReader { proxy in
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
                                    value: geo.frame(in: .named("timelineScroll")).minY
                                )
                            }
                        )
                    ForEach(model.posts, id: \.id) { post in
                        TimeLinePostView(model: post)
                            .padding(.horizontal, 10)
                            .onAppear {
                                if post.id == model.posts.last?.id {
                                    Task { await model.fetchPosts(roomId: session.currentRoomId) }
                                }
                            }
                    }
                }
            }
            .coordinateSpace(name: "timelineScroll")
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
        .refreshable {
            await model.refreshHead(roomId: session.currentRoomId)
        }
        // 画面表示で購読開始
        .onAppear {
            Task {
                await model.fetchPosts(roomId: session.currentRoomId, reset: true)
                model.startListening(roomId: session.currentRoomId)
            }
        }
        // 画面離脱で購読停止
        .onDisappear {
            Task { model.stopListening() }
        }
        .overlay(alignment: .bottomTrailing) {
            if !isShowingCreateView {
                Button {
                    isShowingCreateView = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .resizable()
                        .frame(width: 50, height: 50)
                        .padding(.trailing, 20)
                        .padding(.bottom)
                }
            }
        }
        .fullScreenCover(isPresented: $isShowingCreateView) {
            PostCreateView()
                .toolbar(.hidden, for: .tabBar) // Hide tab bar while the full-screen cover is shown
        }
        .toolbar(isShowingCreateView ? .hidden : .visible, for: .tabBar)
        // Top-of-list detection updates VM state
        .onPreferenceChange(TLScrollTopKey.self) { y in
            let atTop = y >= 0
            Task { model.markAtTop(atTop) }
        }
    }
}

#Preview {
    TimeLineView()
}
