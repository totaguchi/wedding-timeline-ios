//
//  TimelineModel.swift
//  WeddingTimeline
//
//  Created by 田口友暉 on 2025/08/17.
//

import FirebaseFirestore
import Foundation
import SwiftUI
import FirebaseAuth

@Observable
class TimelineViewModel {
    var posts: [TimelinePost] = []
    private let postRepo = PostRepository()
    private let db = Firestore.firestore()
    private var mutedUids = Set<String>()
    private var muteListener: ListenerRegistration? = nil
    private var lastSnapshot: DocumentSnapshot? = nil
    private var listenTask: Task<Void, Never>? = nil
    private var knownIds = Set<String>()
    private var isFetching = false
    private var isRefreshing = false
    private var likeInFlight: Set<String> = []
    
    // 新着のバッジ表示用（X っぽい動作）
    var newBadgeCount: Int = 0
    private var pendingNew: [TimelinePost] = []
    var isAtTop: Bool = true
    
    // フィルター（上部チップ/タブ）
    var selectedFilter: TimelineFilter = .all
    let availableFilters: [TimelineFilter] = TimelineFilter.allCases

    var filteredPosts: [TimelinePost] {
        // ミュート対象の投稿は常に除外
        let base = posts.filter { !mutedUids.contains($0.authorId) }
        guard selectedFilter != .all else { return base }
        return base.filter { matchesFilter($0, selectedFilter) }
    }

    init () {}
    
    @MainActor
    func fetchPosts(roomId: String, reset: Bool = false) async {
        if isFetching { return }
        isFetching = true
        defer { isFetching = false }

        do {
            if reset {
                lastSnapshot = nil
                posts.removeAll()
                knownIds.removeAll()
            }
            let (models, cursor) = try await postRepo.fetchPosts(
                roomId: roomId,
                limit: 50,
                startAfter: lastSnapshot
            )
            // 重複ID・ミュート対象を除外して追加
            let newOnes = models.filter { !knownIds.contains($0.id) && !mutedUids.contains($0.authorId) }
            posts.append(contentsOf: newOnes)
            knownIds.formUnion(newOnes.map { $0.id })
            lastSnapshot = cursor
        } catch {
            print("[TimelineViewModel] Error fetching posts: \(error)")
        }
    }

    @MainActor
    func refreshHead(roomId: String) async {
        if isRefreshing { return }
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            // 最新ページのみ再取得（サーバー優先）
            let (head, _) = try await postRepo.fetchPosts(
                roomId: roomId,
                limit: 20,
                startAfter: nil
            )

            // 既存は更新、未知は先頭に追加（重複防止）
            var toInsert: [TimelinePost] = []
            for item in head {
                // ミュート対象はスキップ
                if mutedUids.contains(item.authorId) { continue }
                if let idx = posts.firstIndex(where: { $0.id == item.id }) {
                    posts[idx] = item
                } else if !knownIds.contains(item.id) {
                    knownIds.insert(item.id)
                    toInsert.append(item)
                }
            }
            if !toInsert.isEmpty {
                let sorted = toInsert.sorted { $0.createdAt > $1.createdAt }
                if isAtTop {
                    posts.insert(contentsOf: sorted, at: 0)
                } else {
                    pendingNew.append(contentsOf: sorted)
                    newBadgeCount = min(99, newBadgeCount + sorted.count)
                }
            }
        } catch {
            print("[TimelineViewModel] Error refreshing head: \(error)")
        }
    }
    
    @MainActor
    func markAtTop(_ atTop: Bool) {
        if atTop != isAtTop {
            isAtTop = atTop
            if atTop { consumePending() }
        } else {
            isAtTop = atTop
        }
    }

    @MainActor
    private func consumePending() {
        guard !pendingNew.isEmpty else { return }
        let sorted = pendingNew.sorted { $0.createdAt > $1.createdAt }
        posts.insert(contentsOf: sorted, at: 0)
        pendingNew.removeAll()
        newBadgeCount = 0
    }
    
    @MainActor
    func startListening(roomId: String, limit: Int = 20) {
        // 既存の購読があれば停止（posts/knownIds/lastSnapshot は維持）。isLiked も統合済みストリームを利用。
        listenTask?.cancel()
        listenTask = nil
        // ミュート購読を開始（ルーム切替時に更新）
        startMuteListening(roomId: roomId)

        // knownIds が空の場合は、既存 posts から初期化しておく（重複防止）
        if knownIds.isEmpty {
            knownIds.formUnion(posts.map { $0.id })
        }

        let stream = postRepo.listenLatestWithIsLiked(roomId: roomId, limit: limit)
        listenTask = Task {
            do {
                for try await items in stream {
                    await MainActor.run { [weak self] in
                        guard let self else { return }

                        var toInsert: [TimelinePost] = []

                        // 既存IDは更新・未知IDは先頭挿入 or バッファに収集
                        for item in items {
                            // ミュート対象はスキップ
                            if self.mutedUids.contains(item.authorId) { continue }
                            if let idx = self.posts.firstIndex(where: { $0.id == item.id }) {
                                self.posts[idx] = item
                            } else if !self.knownIds.contains(item.id) {
                                self.knownIds.insert(item.id)
                                toInsert.append(item)
                            }
                        }

                        if !toInsert.isEmpty {
                            let sorted = toInsert.sorted { $0.createdAt > $1.createdAt }
                            if self.isAtTop {
                                self.posts.insert(contentsOf: sorted, at: 0)
                            } else {
                                // 先頭にいない時はバッファに積んでバッジカウントを増やす
                                self.pendingNew.append(contentsOf: sorted)
                                self.newBadgeCount = min(99, self.newBadgeCount + sorted.count)
                            }
                        }
                    }
                }
            } catch {
                print("[TimelineViewModel] listen error: \(error)")
            }
        }
    }

    @MainActor
    func stopListening() {
        listenTask?.cancel()
        listenTask = nil
        muteListener?.remove()
        muteListener = nil
    }

    @MainActor
    func revealPending() {
        consumePending()
    }
    
    @MainActor
    func toggleLike(model: TimelinePost, roomId: String, isLiked: Bool) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let postId = model.id

        // 連打抑止（同一 postId の like/unlike を同時に走らせない）
        if likeInFlight.contains(postId) { return }
        likeInFlight.insert(postId)
        defer { likeInFlight.remove(postId) }

        // 対象ポストのインデックスを取得
        guard let idx = posts.firstIndex(where: { $0.id == postId }) else { return }

        // 楽観更新：UI は常にモデルの値を表示
        let old = posts[idx]
        posts[idx].isLiked = isLiked
        posts[idx].likeCount = max(0, posts[idx].likeCount + (isLiked ? 1 : -1))

        do {
            let newCount = try await postRepo.toggleLike(
                roomId: roomId,
                postId: postId,
                uid: uid,
                like: isLiked
            )
            // サーバーが返した確定値で補正
            if let j = posts.firstIndex(where: { $0.id == postId }) {
                posts[j].likeCount = newCount
                posts[j].isLiked = isLiked
            }
        } catch {
            // 失敗時はロールバック
            if let j = posts.firstIndex(where: { $0.id == postId }) {
                posts[j] = old
            }
            print("[Like] toggle failed:", error)
        }
    }
    
    
    @MainActor
    func deletePost(roomId: String, postId: String) async -> Bool {
        guard let uid = Auth.auth().currentUser?.uid else {
            print("[Delete] not signed in")
            return false
        }
        do {
            try await postRepo.deletePost(roomId: roomId, postId: postId, authorUid: uid)
            if let idx = posts.firstIndex(where: { $0.id == postId }) {
                posts.remove(at: idx)
            }
            return true
        } catch {
            print("[Delete] failed:", error)
            return false
        }
    }
    
    // MARK: - Mute
    @MainActor
    func applyMuteChange(targetUid: String, isMuted: Bool) {
        if isMuted {
            mutedUids.insert(targetUid)
        } else {
            mutedUids.remove(targetUid)
        }

        posts.removeAll(where: { mutedUids.contains($0.authorId) })
        knownIds = Set(posts.map { $0.id })
        pendingNew.removeAll(where: { mutedUids.contains($0.authorId) })
        newBadgeCount = min(99, pendingNew.count)
    }

    // MARK: - Mute Listening
    @MainActor
    func startMuteListening(roomId: String) {
        // 既存リスナー解除
        muteListener?.remove()
        muteListener = nil
        
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let roomIdSan = roomId.trimmingCharacters(in: .whitespacesAndNewlines)
        let ref = db.collection("rooms").document(roomIdSan)
            .collection("mutes").document(uid)
            .collection("users")
        
        muteListener = ref.addSnapshotListener { [weak self] snap, err in
            guard let self else { return }
            if let err {
                print("[Mute] listen error:", err)
                return
            }
            // 現在のミュート対象をセットで再構築
            var next = Set<String>()
            snap?.documents.forEach { next.insert($0.documentID) }
            // 反映（除外する）
            self.mutedUids = next
            // すでに保持している投稿からも除外・整合
            self.posts.removeAll(where: { self.mutedUids.contains($0.authorId) })
            self.knownIds = Set(self.posts.map { $0.id })
            // ペンディングも掃除してバッジ更新
            self.pendingNew.removeAll(where: { self.mutedUids.contains($0.authorId) })
            self.newBadgeCount = min(99, self.pendingNew.count)
        }
    }
    
    @MainActor
    func stopMuteListening() {
        muteListener?.remove()
        muteListener = nil
    }

    private func matchesFilter(_ post: TimelinePost, _ filter: TimelineFilter) -> Bool {
        switch filter {
        case .all:       return true
        case .ceremony:  return post.tag == .ceremony
        case .reception:  return post.tag == .reception
        }
    }

    @MainActor
    deinit {
        stopListening()
    }
}
