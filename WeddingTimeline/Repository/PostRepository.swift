//
//  PostRepository.swift
//  WeddingTimeline
//
//  Created by 田口友暉 on 2025/09/22.
//

import Foundation
import FirebaseFirestore
import FirebaseAuth

final class PostRepository {
    private let db = Firestore.firestore()

    // MARK: - Firestore refs (helpers)
    private func postRef(roomId: String, postId: String) -> DocumentReference {
        db.collection("rooms").document(roomId).collection("posts").document(postId)
    }

    // MARK: - Mutes (ユーザー非表示)
    // 保存先: rooms/{roomId}/mutes/{ownerUid}/users/{targetUid}
    private func muteDocRef(roomIdSan: String, ownerUid: String, targetUid: String) -> DocumentReference {
        return db
            .collection("rooms").document(roomIdSan)
            .collection("mutes").document(ownerUid)
            .collection("users").document(targetUid)
    }
    
    /// 指定ユーザーがミュートされているか（自分視点）
    func isMuted(roomId: String, targetUid: String, by ownerUid: String) async throws -> Bool {
        let roomIdSan = roomId.trimmingCharacters(in: .whitespacesAndNewlines)
        let snap = try await muteDocRef(roomIdSan: roomIdSan, ownerUid: ownerUid, targetUid: targetUid)
            .getDocument(source: .server)
        return snap.exists
    }
    
    /// ミュート設定/解除（true でミュート、false で解除）
    func setMute(roomId: String, targetUid: String, by ownerUid: String, mute: Bool) async throws {
        let roomIdSan = roomId.trimmingCharacters(in: .whitespacesAndNewlines)
        let ref = muteDocRef(roomIdSan: roomIdSan, ownerUid: ownerUid, targetUid: targetUid)
        if mute {
            try await ref.setData([
                "createdAt": FieldValue.serverTimestamp()
            ], merge: true)
        } else {
            try await ref.delete()
        }
    }
    private func likeRef(roomId: String, postId: String, uid: String) -> DocumentReference {
        db.collection("rooms").document(roomId).collection("posts").document(postId)
            .collection("likes").document(uid)
    }
    private func userLikeRef(roomId: String, uid: String, postId: String) -> DocumentReference {
        db.collection("rooms").document(roomId)
            .collection("userLikes").document(uid)
            .collection("posts").document(postId)
    }

    private class ListenerBox {
        private let removeImpl: () -> Void

        init(_ removeImpl: @escaping () -> Void) {
            self.removeImpl = removeImpl
        }

        @MainActor func remove() { removeImpl() }
    }

    // 単発取得（ページング用にカーソル返す）
    func fetchPosts(roomId: String, limit: Int = 20, startAfter: DocumentSnapshot? = nil)
    async throws -> (posts: [TimelinePost], lastSnapshot: DocumentSnapshot?) {
        let roomIdSan = roomId.trimmingCharacters(in: .whitespacesAndNewlines)
        var q: Query = db.collection("rooms").document(roomIdSan)
            .collection("posts")
            .order(by: "createdAt", descending: true)
            .order(by: FieldPath.documentID(), descending: true)
            .limit(to: limit)

        if let cursor = startAfter {
            q = q.start(afterDocument: cursor)
        }

        let snap = try await q.getDocuments(source: .server)

        // ===== isLiked を一括収集（ユーザー/ルーム専用のミラー index から 1 クエリ） =====
        var likedSet: Set<String> = []
        if let uid = Auth.auth().currentUser?.uid {
            do {
                let likedSnap = try await db.collection("rooms").document(roomIdSan)
                    .collection("userLikes").document(uid)
                    .collection("posts")
                    .getDocuments(source: .server)
                likedSet = Set(likedSnap.documents.map { $0.documentID })
            } catch {
                print("[PostRepository] userLikes fetch failed:", error)
            }
        }

        let posts: [TimelinePost] = snap.documents.compactMap { doc in
            do {
                var dto = try doc.data(as: TimelinePostDTO.self)
                dto.id = doc.documentID
                if var model = TimelinePost(dto: dto) {
                    model.isLiked = likedSet.contains(doc.documentID)
                    return model
                } else {
                    return nil
                }
            } catch {
                print("[PostRepository] decode failed id=\(doc.documentID): \(error)")
                return nil
            }
        }
        let last: DocumentSnapshot? = snap.documents.last as DocumentSnapshot?
        return (posts, last)
    }

    // リアルタイム購読（最新 N 件）
    func listenLatest(roomId: String, limit: Int = 20)
    -> AsyncThrowingStream<[TimelinePost], Error> {
        let roomIdSan = roomId.trimmingCharacters(in: .whitespacesAndNewlines)
        let q = db.collection("rooms").document(roomIdSan)
            .collection("posts")
            .order(by: "createdAt", descending: true)
            .limit(to: limit)

        return AsyncThrowingStream { cont in
            let listener = q.addSnapshotListener { snap, err in
                if let err { cont.yield(with: .failure(err)); return }
                guard let snap else { return }
                let posts: [TimelinePost] = snap.documents.compactMap { doc in
                    do {
                        var dto = try doc.data(as: TimelinePostDTO.self)
                        if dto.id == nil { dto.id = doc.documentID }
                        return TimelinePost(dto: dto)
                    } catch {
                        print("[PostRepository] decode failed id=\(doc.documentID): \(error)")
                        return nil
                    }
                }
                cont.yield(posts)
            }
            let box = ListenerBox(listener.remove)
            cont.onTermination = { _ in
                Task { @MainActor in
                    box.remove()
                }
            }
        }
    }

    /// リアルタイム購読（最新 N 件）+ 自分の isLiked を同時反映
    /// - Returns: posts 配列（各要素の `isLiked` は自分の likes から導出）
    func listenLatestWithIsLiked(roomId: String, limit: Int = 20)
    -> AsyncThrowingStream<[TimelinePost], Error> {
        // 未ログインの場合は通常版の購読にフォールバック
        guard let uid = Auth.auth().currentUser?.uid else {
            return listenLatest(roomId: roomId, limit: limit)
        }

        let roomIdSan = roomId.trimmingCharacters(in: .whitespacesAndNewlines)
        let postsQ = db.collection("rooms").document(roomIdSan)
            .collection("posts")
            .order(by: "createdAt", descending: true)
            .limit(to: limit)

        // 自分の likes をこの room で購読（ユーザー/ルーム専用のミラー index）
        let likesQ = db.collection("rooms").document(roomIdSan)
            .collection("userLikes").document(uid)
            .collection("posts")

        return AsyncThrowingStream { cont in
            // 直近のポスト群 & 自分の liked セットを維持
            var latestDocs: [QueryDocumentSnapshot] = []
            var likedSet: Set<String> = []

            // posts listener
            let postsListener = postsQ.addSnapshotListener { snap, err in
                if let err { cont.yield(with: .failure(err)); return }
                guard let snap else { return }
                latestDocs = snap.documents
                let posts = self.makePosts(from: latestDocs, likedSet: likedSet)
                cont.yield(posts)
            }

            // likes listener（ユーザー/ルーム専用のミラー index）
            let likesListener = likesQ.addSnapshotListener { snap, err in
                if let err { cont.yield(with: .failure(err)); return }
                guard let snap else { return }
                var newSet: Set<String> = []
                for d in snap.documents { newSet.insert(d.documentID) }
                likedSet = newSet
                let posts = self.makePosts(from: latestDocs, likedSet: likedSet)
                cont.yield(posts)
            }

            // リスナーの破棄を安全に（Main で remove）
            let postsBox = ListenerBox(postsListener.remove)
            let likesBox = ListenerBox(likesListener.remove)
            cont.onTermination = { _ in
                Task { @MainActor in
                    postsBox.remove()
                    likesBox.remove()
                }
            }
        }
    }

    // Helper: docs + likedSet から画面表示用の配列を構築
    private func makePosts(from docs: [QueryDocumentSnapshot], likedSet: Set<String>) -> [TimelinePost] {
        return docs.compactMap { doc in
            do {
                var dto = try doc.data(as: TimelinePostDTO.self)
                if dto.id == nil { dto.id = doc.documentID }
                if var model = TimelinePost(dto: dto) {
                    model.isLiked = likedSet.contains(doc.documentID)
                    return model
                } else {
                    return nil
                }
            } catch {
                print("[PostRepository] decode failed id=\(doc.documentID): \(error)")
                return nil
            }
        }
    }

    // MARK: - Likes
    /// 現在のユーザーがいいね済みかを単発で取得
    func fetchIsLiked(roomId: String, postId: String, uid: String) async throws -> Bool {
        let snap = try await likeRef(roomId: roomId, postId: postId, uid: uid).getDocument()
        return snap.exists
    }

    /// いいね状態をリアルタイム購読
    func listenIsLiked(roomId: String, postId: String, uid: String) -> AsyncThrowingStream<Bool, Error> {
        let ref = likeRef(roomId: roomId, postId: postId, uid: uid)
        return AsyncThrowingStream { cont in
            let listener = ref.addSnapshotListener { snap, err in
                if let err { cont.yield(with: .failure(err)); return }
                cont.yield(snap?.exists == true)
            }
            let box = ListenerBox(listener.remove)
            cont.onTermination = { _ in
                Task { @MainActor in box.remove() }
            }
        }
    }

    /// いいねのトグル（true: いいね、false: 解除）。
    /// likes/{uid} の作成/削除と posts.likeCount の増減を 1 トランザクションで整合。
    /// （async helper を使わず、ここで直接 withCheckedThrowingContinuation で橋渡し）
    func toggleLike(
        roomId: String,
        postId: String,
        uid: String,
        like: Bool
    ) async throws -> Int {
        let roomIdSan = roomId.trimmingCharacters(in: .whitespacesAndNewlines)
        let postRef = postRef(roomId: roomIdSan, postId: postId)
        let likeRef = likeRef(roomId: roomIdSan, postId: postId, uid: uid)
        let mirrorRef = userLikeRef(roomId: roomIdSan, uid: uid, postId: postId)

        let newCountNum: NSNumber = try await db.runTransactionAsync { (txn: Transaction) throws -> NSNumber in
            // Post の取得（ここで失敗＝ルール or パス不正）
            let postSnap: DocumentSnapshot
            do {
                postSnap = try txn.getDocument(postRef)
            } catch {
                throw NSError(
                    domain: "PostRepository",
                    code: -20,
                    userInfo: [NSLocalizedDescriptionKey: "failed to get post doc (rules or path?)",
                               "roomId": roomIdSan, "postId": postId]
                )
            }
            guard postSnap.exists else {
                throw NSError(
                    domain: "PostRepository",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Post does not exist"]
                )
            }

            var likeCount = (postSnap.data()? ["likeCount"] as? Int) ?? 0

            // likes サブコレクション（存在チェックだけ）
            let likeSnap = try? txn.getDocument(likeRef)
            let exists = (likeSnap?.exists == true)

            if like {
                if !exists {
                    txn.setData(
                        [
                            "createdAt": FieldValue.serverTimestamp(),
                            "userId": uid,
                            "roomId": roomIdSan,
                            "postId": postId
                        ],
                        forDocument: likeRef
                    )
                    txn.setData(["createdAt": FieldValue.serverTimestamp(),
                                 "roomId": roomIdSan], forDocument: mirrorRef)
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
    
    /// 新規投稿用の DocumentID を事前発行
    func generatePostId(roomId: String) -> String {
        let roomIdSan = roomId.trimmingCharacters(in: .whitespacesAndNewlines)
        let ref = db.collection("rooms").document(roomIdSan).collection("posts").document()
        return ref.documentID
    }

    /// 新規投稿を作成（Firestore のみ、メディアは既にアップロード済み前提）
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
        let roomIdSan = roomId.trimmingCharacters(in: .whitespacesAndNewlines)
        let contentSan = content.trimmingCharacters(in: .whitespacesAndNewlines)
        let tagSan = tag.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        // バリデーション
        guard !roomIdSan.isEmpty else {
            throw NSError(domain: "PostRepository", code: 400, userInfo: [NSLocalizedDescriptionKey: "ルーム情報が取得できませんでした"])
        }
        let allowedTags: Set<String> = ["ceremony", "reception"]
        guard allowedTags.contains(tagSan) else {
            throw NSError(domain: "PostRepository", code: 400, userInfo: [NSLocalizedDescriptionKey: "タグは挙式/披露宴のみ選択可能です"])
        }

        // メディアのペイロード構築
        var mediaPayload: [[String: Any]] = []
        for m in media {
            var item: [String: Any] = [
                "id": m.id,
                "type": m.type,
                "mediaUrl": m.mediaUrl,
                "width": m.width,
                "height": m.height,
            ]
            if let d = m.duration { item["duration"] = d }
            if let sp = m.storagePath { item["storagePath"] = sp }
            mediaPayload.append(item)
        }

        let payload: [String: Any] = [
            "content": contentSan,
            "authorId": authorId,
            "authorName": authorName,
            "userIcon": userIcon,
            "tag": tagSan,
            "createdAt": FieldValue.serverTimestamp(),
            "media": mediaPayload,
            "likeCount": 0,
            "replyCount": 0
        ]

        let docRef = db.collection("rooms").document(roomIdSan).collection("posts").document(postId)
        try await docRef.setData(payload)
    }
    
    // MARK: - Report (UGC)
    /// ユーザー通報を Firestore に保存します（1ユーザー1通報：reports/{uid} へ作成のみ許可・冪等）
    /// パス: rooms/{roomId}/posts/{postId}/reports/{uid}
    func reportPost(roomId: String, postId: String, reason: String, reporterUid: String) async throws {
        let roomIdSan = roomId.trimmingCharacters(in: .whitespacesAndNewlines)
        precondition(!roomIdSan.isEmpty, "roomId is empty")

        let reasonSan = reason.trimmingCharacters(in: .whitespacesAndNewlines)

        let reportRef = db
            .collection("rooms").document(roomIdSan)
            .collection("posts").document(postId)
            .collection("reports").document(reporterUid)

        // ルール上 `reports/{uid}` は create のみ許可（update/read は不可）。
        // そのため、初回は setData で作成し、2回目以降は PermissionDenied になる想定。
        // 2回目以降は「通報済み」とみなして握りつぶし（idempotent）にする。
        do {
            try await reportRef.setData([
                "reason": reasonSan,
                "reporterUid": reporterUid,
                "roomId": roomIdSan,
                "postId": postId,
                "createdAt": FieldValue.serverTimestamp()
            ])
        } catch {
            let nsError = error as NSError
            if let code = FirestoreErrorCode.Code(rawValue: nsError.code), code == .permissionDenied {
                // 既に通報済み（=ドキュメントが存在して update 扱いになった）等。
                // read も禁止されているため厳密判定できないので、通報済みとして扱う。
                print("[PostRepository] reportPost ignored (already reported or no permission):", nsError)
                return
            }
            throw error
        }
    }

    // MARK: - Delete Post
    /// 指定ポストを削除（先に likes サブコレクションを全削除 → 本体削除）
    /// - Note: Firestore ルールで `request.auth.uid == resource.data.authorId` による削除制限を前提
    func deletePost(roomId: String, postId: String, authorUid: String) async throws {
        let roomIdSan = roomId.trimmingCharacters(in: .whitespacesAndNewlines)
        let roomRef = db.collection("rooms").document(roomIdSan)
        let postRef = roomRef.collection("posts").document(postId)

        // likes サブコレクションを全削除
        let likesQuery = postRef.collection("likes")
        try await batchDelete(query: likesQuery)

        // 本体削除
        try await postRef.delete()
    }

    // MARK: - Helpers
    /// 指定クエリの結果をページングしながら一括削除（__name__ でソート → start(after:)）
    private func batchDelete(query base: Query, pageSize: Int = 300) async throws {
        var last: DocumentSnapshot? = nil
        while true {
            var q = base.order(by: FieldPath.documentID()).limit(to: pageSize)
            if let lastDoc = last {
                q = q.start(afterDocument: lastDoc)
            }
            let snap = try await q.getDocuments(source: .server)
            if snap.documents.isEmpty { break }
            let batch = db.batch()
            for d in snap.documents {
                batch.deleteDocument(d.reference)
            }
            try await batch.commit()
            last = snap.documents.last
        }
    }
}
