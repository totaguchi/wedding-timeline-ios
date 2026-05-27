//
//  PostRepository.swift
//  WeddingTimeline
//
//  投稿の取得・更新・削除を担当する Repository。
//  Firestore / Auth の直接操作は DataSource に委譲し、
//  このクラスは orchestration と DTO→Entity マッピングに専念する。
//

import Foundation

final class PostRepository {

    // MARK: - Dependencies

    private let firestoreDS: FirestorePostDataSource
    private let authDS: FirebaseAuthDataSource

    init(
        firestoreDS: FirestorePostDataSource = FirestorePostDataSource(),
        authDS:      FirebaseAuthDataSource  = FirebaseAuthDataSource()
    ) {
        self.firestoreDS = firestoreDS
        self.authDS      = authDS
    }

    // MARK: - Fetch

    /// 投稿を一括取得する（ページング用にカーソルを返す）
    func fetchPosts(
        roomId: String,
        limit: Int = 20,
        startAfter cursor: PostPageCursor? = nil
    ) async throws -> (posts: [TimelinePost], lastSnapshot: PostPageCursor?) {
        let roomIdSan = roomId.trimmingCharacters(in: .whitespacesAndNewlines)

        // 投稿取得
        let (dtos, nextCursor) = try await firestoreDS.fetchPostDTOs(
            roomId: roomIdSan, limit: limit, cursor: cursor
        )

        // いいね済み集合の取得（未ログインはスキップ）
        var likedSet: Set<String> = []
        if let uid = authDS.currentUID() {
            likedSet = (try? await firestoreDS.fetchLikedPostIds(roomId: roomIdSan, uid: uid)) ?? []
        }

        let posts: [TimelinePost] = dtos.compactMap { dto in
            guard var post = TimelinePost(dto: dto) else { return nil }
            post.isLiked = likedSet.contains(dto.id ?? "")
            return post
        }
        return (posts, nextCursor)
    }

    /// いいね数トップの投稿を取得する（ランキング用）
    func fetchTopPosts(roomId: String, limit: Int = 3, tag: PostTag? = nil) async throws -> [TimelinePost] {
        let roomIdSan = roomId.trimmingCharacters(in: .whitespacesAndNewlines)
        let dtos = try await firestoreDS.fetchTopPostDTOs(roomId: roomIdSan, limit: limit, tag: tag)
        return dtos.compactMap { TimelinePost(dto: $0) }
    }

    // MARK: - Listeners

    /// 最新投稿をリアルタイム購読する（最新 N 件）
    func listenLatest(roomId: String, limit: Int = 20) -> AsyncThrowingStream<[TimelinePost], Error> {
        let roomIdSan = roomId.trimmingCharacters(in: .whitespacesAndNewlines)
        let stream = firestoreDS.listenLatestDTOs(roomId: roomIdSan, limit: limit)
        return AsyncThrowingStream { cont in
            let task = Task {
                do {
                    for try await dtos in stream {
                        cont.yield(dtos.compactMap { TimelinePost(dto: $0) })
                    }
                    cont.finish()
                } catch {
                    cont.finish(throwing: error)
                }
            }
            cont.onTermination = { _ in task.cancel() }
        }
    }

    /// 最新投稿 + 自分の isLiked を同時反映してリアルタイム購読する
    ///
    /// 未ログインの場合は通常版の購読にフォールバック。
    func listenLatestWithIsLiked(roomId: String, limit: Int = 20) -> AsyncThrowingStream<[TimelinePost], Error> {
        let roomIdSan = roomId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let uid = authDS.currentUID() else {
            return listenLatest(roomId: roomIdSan, limit: limit)
        }

        let stream = firestoreDS.listenLatestDTOsWithLikedSet(
            roomId: roomIdSan, uid: uid, limit: limit
        )
        return AsyncThrowingStream { cont in
            let task = Task {
                do {
                    for try await (dtos, likedSet) in stream {
                        let posts: [TimelinePost] = dtos.compactMap { dto in
                            guard var post = TimelinePost(dto: dto) else { return nil }
                            post.isLiked = likedSet.contains(dto.id ?? "")
                            return post
                        }
                        cont.yield(posts)
                    }
                    cont.finish()
                } catch {
                    cont.finish(throwing: error)
                }
            }
            cont.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Likes

    /// 現在のユーザーがいいね済みかを単発取得する
    func fetchIsLiked(roomId: String, postId: String, uid: String) async throws -> Bool {
        try await firestoreDS.fetchIsLiked(roomId: roomId, postId: postId, uid: uid)
    }

    /// いいね状態をリアルタイム購読する
    func listenIsLiked(roomId: String, postId: String, uid: String) -> AsyncThrowingStream<Bool, Error> {
        firestoreDS.listenIsLiked(roomId: roomId, postId: postId, uid: uid)
    }

    /// いいねをトグルする
    ///
    /// - Returns: 更新後のいいね数
    func toggleLike(roomId: String, postId: String, uid: String, like: Bool) async throws -> Int {
        let roomIdSan = roomId.trimmingCharacters(in: .whitespacesAndNewlines)
        return try await firestoreDS.toggleLike(
            roomId: roomIdSan, postId: postId, uid: uid, like: like
        )
    }

    // MARK: - Mutes

    /// 指定ユーザーがミュートされているか（自分視点）
    func isMuted(roomId: String, targetUid: String, by ownerUid: String) async throws -> Bool {
        let roomIdSan = roomId.trimmingCharacters(in: .whitespacesAndNewlines)
        return try await firestoreDS.isMuted(
            roomId: roomIdSan, targetUid: targetUid, ownerUid: ownerUid
        )
    }

    /// ミュートを設定 / 解除する
    func setMute(roomId: String, targetUid: String, by ownerUid: String, mute: Bool) async throws {
        let roomIdSan = roomId.trimmingCharacters(in: .whitespacesAndNewlines)
        try await firestoreDS.setMute(
            roomId: roomIdSan, targetUid: targetUid, ownerUid: ownerUid, mute: mute
        )
    }

    /// ミュート中ユーザー ID 集合をリアルタイム購読する
    func listenMutedUserIds(roomId: String, ownerUid: String) -> AsyncThrowingStream<Set<String>, Error> {
        let roomIdSan = roomId.trimmingCharacters(in: .whitespacesAndNewlines)
        return firestoreDS.listenMutedUserIds(roomId: roomIdSan, ownerUid: ownerUid)
    }

    // MARK: - Create / Delete / Report

    /// 新規投稿用の DocumentID を事前発行する
    func generatePostId(roomId: String) -> String {
        let roomIdSan = roomId.trimmingCharacters(in: .whitespacesAndNewlines)
        return firestoreDS.generatePostId(roomId: roomIdSan)
    }

    /// 新規投稿を作成する（メディアは既にアップロード済み前提）
    func createPost(
        roomId: String,
        postId: String,
        content: String,
        authorId: String,
        authorName: String,
        userIcon: String,
        tag: String,
        media: [MediaDTO]
    ) async throws {
        let roomIdSan    = roomId.trimmingCharacters(in: .whitespacesAndNewlines)
        let contentSan   = content.trimmingCharacters(in: .whitespacesAndNewlines)
        let tagSan       = tag.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        guard !roomIdSan.isEmpty else {
            throw NSError(
                domain: "PostRepository", code: 400,
                userInfo: [NSLocalizedDescriptionKey: "ルーム情報が取得できませんでした"]
            )
        }
        guard Set(["ceremony", "reception"]).contains(tagSan) else {
            throw NSError(
                domain: "PostRepository", code: 400,
                userInfo: [NSLocalizedDescriptionKey: "タグは挙式/披露宴のみ選択可能です"]
            )
        }

        // ペイロード構築と FieldValue.serverTimestamp() の使用は DataSource に委譲
        try await firestoreDS.createPost(
            roomId:     roomIdSan,
            postId:     postId,
            content:    contentSan,
            authorId:   authorId,
            authorName: authorName,
            userIcon:   userIcon,
            tag:        tagSan,
            media:      media
        )
    }

    /// 投稿を削除する
    func deletePost(roomId: String, postId: String, authorUid: String) async throws {
        let roomIdSan = roomId.trimmingCharacters(in: .whitespacesAndNewlines)
        try await firestoreDS.deletePost(roomId: roomIdSan, postId: postId)
    }

    /// 投稿を通報する
    func reportPost(
        roomId: String,
        postId: String,
        reason: String,
        reporterUid: String
    ) async throws {
        let roomIdSan  = roomId.trimmingCharacters(in: .whitespacesAndNewlines)
        let reasonSan  = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        try await firestoreDS.reportPost(
            roomId: roomIdSan, postId: postId,
            reason: reasonSan, reporterUid: reporterUid
        )
    }
}
