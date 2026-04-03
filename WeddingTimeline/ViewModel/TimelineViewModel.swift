//
//  TimelineModel.swift
//  WeddingTimeline
//
//  Created by 田口友暉 on 2025/08/17.
//

import Foundation
import SwiftUI

@Observable
class TimelineViewModel {
    private enum TrimSide {
        case head
        case tail
    }

    var posts: [TimelinePost] = []
    private(set) var filteredPosts: [TimelinePost] = []
    private let postRepo: PostRepository
    private var mutedUids = Set<String>()
    /// Firestore リスナーを Task に置き換え（FirebaseFirestore 型を ViewModel から除去）
    private var muteListenTask: Task<Void, Never>? = nil
    private var listenTask: Task<Void, Never>? = nil
    private var knownIds = Set<String>()
    private var isFetching = false
    private var isRefreshing = false
    private var likeInFlight: Set<String> = []

    // UseCases
    private let fetchUseCase: FetchTimelineUseCase
    private let toggleLikeUseCase: ToggleLikeUseCase
    private let deletePostUseCase: DeletePostUseCase
    private let muteUserUseCase: MuteUserUseCase
    private let reportPostUseCase: ReportPostUseCase

    /// Session は View の onAppear で configure(session:) を通じて注入する
    private var session: SessionStore?

    /// UID を SessionStore から取得（Auth.auth() を ViewModel から除去）
    private var currentUID: String? { session?.cachedMember?.uid }

    // Phase 3-A: メモリ上限（300件）
    private let maxPostsInMemory = 300

    // 新着のバッジ表示用（X っぽい動作）
    var newBadgeCount: Int = 0
    private var pendingNew: [TimelinePost] = []
    var isAtTop: Bool = true

    // フィルター（上部チップ/タブ）
    private(set) var selectedFilter: TimelineFilter = .all {
        didSet { rebuildFilteredPosts() }
    }
    let availableFilters: [TimelineFilter] = TimelineFilter.allCases

    init() {
        let repo = PostRepository()
        postRepo = repo
        fetchUseCase = FetchTimelineUseCase(postRepo: repo)
        toggleLikeUseCase = ToggleLikeUseCase(postRepo: repo)
        deletePostUseCase = DeletePostUseCase(postRepo: repo)
        muteUserUseCase = MuteUserUseCase(postRepo: repo)
        reportPostUseCase = ReportPostUseCase(postRepo: repo)
    }

    // MARK: - Session 注入

    /// View の onAppear で必ず呼ぶ。UID の取得元として使用する。
    @MainActor
    func configure(session: SessionStore) {
        self.session = session
    }

    // MARK: - Helpers

    /// `posts` と `pendingNew` を合わせた ID セットを再構築する
    private func rebuildKnownIds() {
        knownIds = Set(posts.map(\.id))
        knownIds.formUnion(pendingNew.map(\.id))
    }

    /// メモリ上限（maxPostsInMemory）を超えた場合に指定方向から投稿を削除する
    private func trimPostsIfNeeded(removingFrom side: TrimSide) {
        guard posts.count > maxPostsInMemory else { return }
        let removeCount = posts.count - maxPostsInMemory
        switch side {
        case .head:
            posts.removeFirst(removeCount)
        case .tail:
            posts.removeLast(removeCount)
        }
        rebuildKnownIds()
    }

    /// `posts` と `pendingNew` の合計件数が上限を超えたら間引く
    private func trimMemoryIfNeeded(preferredPostTrimSide: TrimSide) {
        let overflow = posts.count + pendingNew.count - maxPostsInMemory
        guard overflow > 0 else { return }

        let removablePosts = min(overflow, posts.count)
        if removablePosts > 0 {
            switch preferredPostTrimSide {
            case .head:
                posts.removeFirst(removablePosts)
            case .tail:
                posts.removeLast(removablePosts)
            }
        }

        let pendingOverflow = posts.count + pendingNew.count - maxPostsInMemory
        if pendingOverflow > 0 {
            pendingNew.removeLast(min(pendingOverflow, pendingNew.count))
            newBadgeCount = min(99, pendingNew.count)
        }

        rebuildKnownIds()
    }

    /// posts・mutedUids・selectedFilter の変更後に呼び出してキャッシュを更新する
    private func rebuildFilteredPosts() {
        let base = mutedUids.isEmpty
            ? posts
            : posts.filter { !mutedUids.contains($0.authorId) }
        if selectedFilter == .all {
            filteredPosts = base
        } else {
            filteredPosts = base.filter { matchesFilter($0, selectedFilter) }
        }
    }

    // MARK: - Fetch

    @MainActor
    func fetchPosts(roomId: String, reset: Bool = false) async {
        if isFetching { return }
        isFetching = true
        defer { isFetching = false }

        do {
            if reset {
                posts.removeAll()
                pendingNew.removeAll()
                newBadgeCount = 0
                knownIds.removeAll()
                rebuildFilteredPosts()
            }
            let newPosts = try await fetchUseCase.execute(roomId: roomId, reset: reset)
            let newOnes = newPosts.filter { !knownIds.contains($0.id) && !mutedUids.contains($0.authorId) }
            posts.append(contentsOf: newOnes)
            knownIds.formUnion(newOnes.map { $0.id })
            trimPostsIfNeeded(removingFrom: .head)
            rebuildFilteredPosts()
        } catch {
            print("[TimelineViewModel] Error fetching posts: \(error)")
        }
    }

    // MARK: - Refresh

    @MainActor
    func refreshHead(roomId: String) async {
        if isRefreshing { return }
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            let (head, _) = try await postRepo.fetchPosts(
                roomId: roomId, limit: 20, startAfter: nil
            )

            var toInsert: [TimelinePost] = []
            for item in head {
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
                    trimPostsIfNeeded(removingFrom: .tail)
                } else {
                    pendingNew.append(contentsOf: sorted)
                    newBadgeCount = min(99, newBadgeCount + sorted.count)
                    trimMemoryIfNeeded(preferredPostTrimSide: .head)
                }
            }
            rebuildFilteredPosts()
        } catch {
            print("[TimelineViewModel] Error refreshing head: \(error)")
        }
    }

    // MARK: - Listen

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
        trimPostsIfNeeded(removingFrom: .tail)
        rebuildFilteredPosts()
    }

    @MainActor
    func startListening(roomId: String, limit: Int = 20) {
        listenTask?.cancel()
        listenTask = nil
        startMuteListening(roomId: roomId)

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

                        for item in items {
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
                                self.trimPostsIfNeeded(removingFrom: .tail)
                            } else {
                                self.pendingNew.append(contentsOf: sorted)
                                self.newBadgeCount = min(99, self.newBadgeCount + sorted.count)
                                self.trimMemoryIfNeeded(preferredPostTrimSide: .head)
                            }
                        }
                        self.rebuildFilteredPosts()
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
        muteListenTask?.cancel()
        muteListenTask = nil
    }

    @MainActor
    func revealPending() {
        consumePending()
    }

    @MainActor
    func setSelectedFilter(_ filter: TimelineFilter) {
        selectedFilter = filter
    }

    @MainActor
    func isMuted(authorId: String) -> Bool {
        mutedUids.contains(authorId)
    }

    // MARK: - Like

    @MainActor
    func toggleLike(model: TimelinePost, roomId: String, isLiked: Bool) async {
        guard let uid = currentUID else { return }
        let postId = model.id

        if likeInFlight.contains(postId) { return }
        likeInFlight.insert(postId)
        defer { likeInFlight.remove(postId) }

        guard let idx = posts.firstIndex(where: { $0.id == postId }) else { return }

        let old = posts[idx]
        posts[idx].isLiked = isLiked
        posts[idx].likeCount = max(0, posts[idx].likeCount + (isLiked ? 1 : -1))
        rebuildFilteredPosts()

        do {
            let newCount = try await toggleLikeUseCase.execute(
                roomId: roomId, postId: postId, uid: uid, isLiked: isLiked
            )
            if let j = posts.firstIndex(where: { $0.id == postId }) {
                posts[j].likeCount = newCount
                posts[j].isLiked = isLiked
                rebuildFilteredPosts()
            }
        } catch {
            if let j = posts.firstIndex(where: { $0.id == postId }) {
                posts[j] = old
                rebuildFilteredPosts()
            }
            print("[Like] toggle failed:", error)
        }
    }

    // MARK: - Delete

    @MainActor
    func deletePost(roomId: String, postId: String) async -> Bool {
        guard let uid = currentUID else {
            print("[Delete] not signed in")
            return false
        }
        do {
            try await deletePostUseCase.execute(roomId: roomId, postId: postId, uid: uid)
            if let idx = posts.firstIndex(where: { $0.id == postId }) {
                posts.remove(at: idx)
            }
            pendingNew.removeAll(where: { $0.id == postId })
            newBadgeCount = min(99, pendingNew.count)
            rebuildKnownIds()
            rebuildFilteredPosts()
            return true
        } catch {
            print("[Delete] failed:", error)
            return false
        }
    }

    // MARK: - Report

    @MainActor
    func reportPost(postId: String, reason: String) async -> Bool {
        guard let uid = currentUID else {
            print("[Report] not signed in")
            return false
        }
        guard let roomId = session?.currentRoomId, !roomId.isEmpty else {
            print("[Report] roomId not found in session")
            return false
        }
        do {
            try await reportPostUseCase.execute(
                roomId: roomId, postId: postId, reason: reason, reporterUid: uid
            )
            return true
        } catch {
            print("[Report] failed:", error)
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
        pendingNew.removeAll(where: { mutedUids.contains($0.authorId) })
        newBadgeCount = min(99, pendingNew.count)
        rebuildKnownIds()
        rebuildFilteredPosts()
    }

    @MainActor
    func setMute(roomId: String, targetUid: String, mute: Bool) async -> Bool {
        guard let uid = currentUID else { return false }
        do {
            try await muteUserUseCase.execute(
                roomId: roomId, targetUid: targetUid, ownerUid: uid, mute: mute
            )
            applyMuteChange(targetUid: targetUid, isMuted: mute)
            return true
        } catch {
            print("[Mute] set failed:", error)
            return false
        }
    }

    // MARK: - Mute Listening

    @MainActor
    func startMuteListening(roomId: String) {
        muteListenTask?.cancel()
        muteListenTask = nil

        guard let uid = currentUID else { return }
        let stream = postRepo.listenMutedUserIds(roomId: roomId, ownerUid: uid)

        muteListenTask = Task {
            do {
                for try await mutedSet in stream {
                    self.mutedUids = mutedSet
                    self.posts.removeAll(where: { mutedSet.contains($0.authorId) })
                    self.pendingNew.removeAll(where: { mutedSet.contains($0.authorId) })
                    self.newBadgeCount = min(99, self.pendingNew.count)
                    self.rebuildKnownIds()
                    self.rebuildFilteredPosts()
                }
            } catch {
                print("[Mute] listen error:", error)
            }
        }
    }

    @MainActor
    func stopMuteListening() {
        muteListenTask?.cancel()
        muteListenTask = nil
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
