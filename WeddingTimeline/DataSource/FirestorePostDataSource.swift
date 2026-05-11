//
//  FirestorePostDataSource.swift
//  WeddingTimeline
//
//  投稿関連の Firestore SDK 操作を集約する DataSource。
//  PostRepository は Firestore SDK を直接参照せず、このクラスを経由する。
//

@preconcurrency import FirebaseFirestore
import Foundation

// MARK: - PostPageCursor

/// ページング用のカーソル（内部実装は Firestore DocumentSnapshot）。
///
/// UseCase や Repository が `DocumentSnapshot` を直接保持しないよう隠蔽する。
/// 呼び出し側は内部の `snapshot` にアクセスしないこと。
struct PostPageCursor {
    let snapshot: DocumentSnapshot
}

// MARK: - FirestorePostDataSource

/// 投稿関連 Firestore SDK 呼び出しを集約する DataSource。
///
/// - 全メソッドは DTO を返し、Entity への変換は Repository が担う。
/// - Firestore に関する SDK 依存はすべてここに閉じる。
final class FirestorePostDataSource {

    private let db = Firestore.firestore()

    // MARK: - ListenerBox

    /// Snapshot listener の破棄を MainActor 上で安全に行うためのラッパー
    private final class ListenerBox {
        private let removeImpl: () -> Void
        init(_ removeImpl: @escaping () -> Void) { self.removeImpl = removeImpl }
        @MainActor func remove() { removeImpl() }
    }

    // MARK: - Fetch

    /// 投稿を一括取得する（ページング対応）
    ///
    /// - Parameters:
    ///   - roomId: ルーム ID（サニタイズ済み）
    ///   - limit: 取得件数
    ///   - cursor: ページングカーソル（初回は nil）
    /// - Returns: DTO 配列と次ページ用カーソル
    func fetchPostDTOs(
        roomId: String,
        limit: Int,
        cursor: PostPageCursor?
    ) async throws -> ([TimelinePostDTO], PostPageCursor?) {
        var q: Query = db.collection("rooms").document(roomId)
            .collection("posts")
            .order(by: "createdAt", descending: true)
            .order(by: FieldPath.documentID(), descending: true)
            .limit(to: limit)

        if let cursor { q = q.start(afterDocument: cursor.snapshot) }

        let snap = try await q.getDocuments(source: .server)
        let dtos: [TimelinePostDTO] = snap.documents.compactMap { doc in
            var dto = try? doc.data(as: TimelinePostDTO.self)
            dto?.id = doc.documentID
            return dto
        }
        let nextCursor = snap.documents.last.map { PostPageCursor(snapshot: $0) }
        return (dtos, nextCursor)
    }

    /// 指定ユーザーがいいねした投稿 ID 一覧を取得する
    func fetchLikedPostIds(roomId: String, uid: String) async throws -> Set<String> {
        let snap = try await db.collection("rooms").document(roomId)
            .collection("userLikes").document(uid)
            .collection("posts")
            .getDocuments(source: .server)
        return Set(snap.documents.map { $0.documentID })
    }

    /// いいね数トップの投稿 DTO を取得する（ランキング用）
    func fetchTopPostDTOs(roomId: String, limit: Int, tag: PostTag?) async throws -> [TimelinePostDTO] {
        var q: Query = db.collection("rooms").document(roomId).collection("posts")
        if let tag { q = q.whereField("tag", isEqualTo: tag.rawValue) }
        q = q.order(by: "likeCount", descending: true).limit(to: limit)

        let snap = try await q.getDocuments(source: .server)
        return snap.documents.compactMap { doc in
            var dto = try? doc.data(as: TimelinePostDTO.self)
            dto?.id = doc.documentID
            return dto
        }
    }

    /// いいね済みかを単発取得する
    func fetchIsLiked(roomId: String, postId: String, uid: String) async throws -> Bool {
        let snap = try await db.collection("rooms").document(roomId)
            .collection("posts").document(postId)
            .collection("likes").document(uid)
            .getDocument()
        return snap.exists
    }

    /// 指定ユーザーがミュートされているかを単発取得する
    func isMuted(roomId: String, targetUid: String, ownerUid: String) async throws -> Bool {
        let snap = try await db.collection("rooms").document(roomId)
            .collection("mutes").document(ownerUid)
            .collection("users").document(targetUid)
            .getDocument(source: .server)
        return snap.exists
    }

    // MARK: - Listeners

    /// 最新投稿 DTO をリアルタイム購読する（isLiked は含まない）
    func listenLatestDTOs(roomId: String, limit: Int) -> AsyncThrowingStream<[TimelinePostDTO], Error> {
        let q = db.collection("rooms").document(roomId)
            .collection("posts")
            .order(by: "createdAt", descending: true)
            .limit(to: limit)

        return AsyncThrowingStream { cont in
            let listener = q.addSnapshotListener { snap, err in
                if let err { cont.yield(with: .failure(err)); return }
                guard let snap else { return }
                let dtos: [TimelinePostDTO] = snap.documents.compactMap { doc in
                    var dto = try? doc.data(as: TimelinePostDTO.self)
                    dto?.id = doc.documentID
                    return dto
                }
                cont.yield(dtos)
            }
            let box = ListenerBox(listener.remove)
            cont.onTermination = { _ in Task { @MainActor in box.remove() } }
        }
    }

    /// 最新投稿 DTO + いいね済み ID セットをリアルタイム購読する
    ///
    /// - Returns: `(dtos, likedSet)` タプルのストリーム
    func listenLatestDTOsWithLikedSet(
        roomId: String,
        uid: String,
        limit: Int
    ) -> AsyncThrowingStream<([TimelinePostDTO], Set<String>), Error> {
        let postsQ = db.collection("rooms").document(roomId)
            .collection("posts")
            .order(by: "createdAt", descending: true)
            .limit(to: limit)

        let likesQ = db.collection("rooms").document(roomId)
            .collection("userLikes").document(uid)
            .collection("posts")

        return AsyncThrowingStream { cont in
            var latestDocs: [QueryDocumentSnapshot] = []
            var likedSet: Set<String> = []

            func emit() {
                let dtos: [TimelinePostDTO] = latestDocs.compactMap { doc in
                    var dto = try? doc.data(as: TimelinePostDTO.self)
                    dto?.id = doc.documentID
                    return dto
                }
                cont.yield((dtos, likedSet))
            }

            let postsListener = postsQ.addSnapshotListener { snap, err in
                if let err { cont.yield(with: .failure(err)); return }
                guard let snap else { return }
                latestDocs = snap.documents
                emit()
            }
            let likesListener = likesQ.addSnapshotListener { snap, err in
                if let err { cont.yield(with: .failure(err)); return }
                guard let snap else { return }
                likedSet = Set(snap.documents.map { $0.documentID })
                emit()
            }

            let postsBox = ListenerBox(postsListener.remove)
            let likesBox  = ListenerBox(likesListener.remove)
            cont.onTermination = { _ in
                Task { @MainActor in
                    postsBox.remove()
                    likesBox.remove()
                }
            }
        }
    }

    /// いいね状態をリアルタイム購読する
    func listenIsLiked(roomId: String, postId: String, uid: String) -> AsyncThrowingStream<Bool, Error> {
        let ref = db.collection("rooms").document(roomId)
            .collection("posts").document(postId)
            .collection("likes").document(uid)
        return AsyncThrowingStream { cont in
            let listener = ref.addSnapshotListener { snap, err in
                if let err { cont.yield(with: .failure(err)); return }
                cont.yield(snap?.exists == true)
            }
            let box = ListenerBox(listener.remove)
            cont.onTermination = { _ in Task { @MainActor in box.remove() } }
        }
    }

    /// ミュート中ユーザー ID 集合をリアルタイム購読する
    func listenMutedUserIds(roomId: String, ownerUid: String) -> AsyncThrowingStream<Set<String>, Error> {
        let ref = db.collection("rooms").document(roomId)
            .collection("mutes").document(ownerUid)
            .collection("users")
        return AsyncThrowingStream { cont in
            let listener = ref.addSnapshotListener { snap, err in
                if let err { cont.yield(with: .failure(err)); return }
                guard let snap else { return }
                cont.yield(Set(snap.documents.map { $0.documentID }))
            }
            let box = ListenerBox(listener.remove)
            cont.onTermination = { _ in Task { @MainActor in box.remove() } }
        }
    }

    // MARK: - Writes

    /// いいねをトグルする（トランザクション）
    ///
    /// - Returns: 更新後のいいね数
    func toggleLike(roomId: String, postId: String, uid: String, like: Bool) async throws -> Int {
        let postRef  = db.collection("rooms").document(roomId).collection("posts").document(postId)
        let likeRef  = postRef.collection("likes").document(uid)
        let mirrorRef = db.collection("rooms").document(roomId)
            .collection("userLikes").document(uid)
            .collection("posts").document(postId)

        let newCountNum: NSNumber = try await db.runTransactionAsync { txn throws -> NSNumber in
            let postSnap: DocumentSnapshot
            do {
                postSnap = try txn.getDocument(postRef)
            } catch {
                throw NSError(
                    domain: "FirestorePostDataSource",
                    code: -20,
                    userInfo: [
                        NSLocalizedDescriptionKey: "failed to get post doc (rules or path?)",
                        "roomId": roomId,
                        "postId": postId
                    ]
                )
            }
            guard postSnap.exists else {
                throw NSError(
                    domain: "FirestorePostDataSource",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Post does not exist"]
                )
            }

            var likeCount = (postSnap.data()?["likeCount"] as? Int) ?? 0
            let likeSnap  = try? txn.getDocument(likeRef)
            let exists    = (likeSnap?.exists == true)

            if like {
                if !exists {
                    txn.setData([
                        "createdAt": FieldValue.serverTimestamp(),
                        "userId":    uid,
                        "roomId":    roomId,
                        "postId":    postId
                    ], forDocument: likeRef)
                    txn.setData([
                        "createdAt": FieldValue.serverTimestamp(),
                        "roomId":    roomId
                    ], forDocument: mirrorRef)
                    likeCount += 1
                    txn.updateData(["likeCount": likeCount], forDocument: postRef)
                }
            } else {
                if exists {
                    txn.deleteDocument(likeRef)
                    txn.deleteDocument(mirrorRef)
                    likeCount = max(0, likeCount - 1)
                    txn.updateData(["likeCount": likeCount], forDocument: postRef)
                }
            }
            return NSNumber(value: likeCount)
        }
        return newCountNum.intValue
    }

    /// 新規投稿を Firestore に書き込む
    ///
    /// `FieldValue.serverTimestamp()` を含むペイロード構築はここで行う。
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
        let mediaPayload: [[String: Any]] = media.map { m in
            var item: [String: Any] = [
                "id":       m.id,
                "type":     m.type,
                "mediaUrl": m.mediaUrl,
                "width":    m.width,
                "height":   m.height
            ]
            if let d  = m.duration    { item["duration"]    = d }
            if let sp = m.storagePath { item["storagePath"] = sp }
            return item
        }

        let payload: [String: Any] = [
            "content":    content,
            "authorId":   authorId,
            "authorName": authorName,
            "userIcon":   userIcon,
            "tag":        tag,
            "createdAt":  FieldValue.serverTimestamp(),
            "media":      mediaPayload,
            "likeCount":  0,
            "replyCount": 0
        ]

        try await db.collection("rooms").document(roomId)
            .collection("posts").document(postId)
            .setData(payload)
    }

    /// 投稿を削除する（likes サブコレクション → 本体の順）
    func deletePost(roomId: String, postId: String) async throws {
        let postRef = db.collection("rooms").document(roomId)
            .collection("posts").document(postId)
        try await batchDelete(query: postRef.collection("likes"))
        try await postRef.delete()
    }

    /// 投稿を通報する（reports/{uid} へ作成のみ許可・冪等）
    func reportPost(
        roomId: String,
        postId: String,
        reason: String,
        reporterUid: String
    ) async throws {
        let reportRef = db.collection("rooms").document(roomId)
            .collection("posts").document(postId)
            .collection("reports").document(reporterUid)
        do {
            try await reportRef.setData([
                "reason":      reason,
                "reporterUid": reporterUid,
                "roomId":      roomId,
                "postId":      postId,
                "createdAt":   FieldValue.serverTimestamp()
            ])
        } catch {
            let ns = error as NSError
            if let code = FirestoreErrorCode.Code(rawValue: ns.code), code == .permissionDenied {
                // 既に通報済みとして扱う（冪等）
                print("[FirestorePostDataSource] reportPost ignored (already reported):", ns)
                return
            }
            throw error
        }
    }

    /// ミュート設定 / 解除
    func setMute(roomId: String, targetUid: String, ownerUid: String, mute: Bool) async throws {
        let ref = db.collection("rooms").document(roomId)
            .collection("mutes").document(ownerUid)
            .collection("users").document(targetUid)
        if mute {
            try await ref.setData(["createdAt": FieldValue.serverTimestamp()], merge: true)
        } else {
            try await ref.delete()
        }
    }

    /// 新規投稿用の Firestore DocumentID を事前発行する
    func generatePostId(roomId: String) -> String {
        db.collection("rooms").document(roomId).collection("posts").document().documentID
    }

    // MARK: - Helpers

    /// 指定クエリ結果をページングしながら一括削除
    private func batchDelete(query base: Query, pageSize: Int = 300) async throws {
        var last: DocumentSnapshot?
        while true {
            var q = base.order(by: FieldPath.documentID()).limit(to: pageSize)
            if let last { q = q.start(afterDocument: last) }
            let snap = try await q.getDocuments(source: .server)
            if snap.documents.isEmpty { break }
            let batch = db.batch()
            snap.documents.forEach { batch.deleteDocument($0.reference) }
            try await batch.commit()
            last = snap.documents.last
        }
    }
}
