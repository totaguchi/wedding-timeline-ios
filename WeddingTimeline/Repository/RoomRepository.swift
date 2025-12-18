//
//  RoomRepository.swift
//  WeddingTimeline
//
//  Created by 田口友暉 on 2025/08/31.
//

import Foundation
import FirebaseAuth
import FirebaseFirestore

// NOTE: username は表示名として重複許容。uniqueness ロックは使用しない。
final class RoomRepository {
    private lazy var db: Firestore = Firestore.firestore()
    init() {}
    init(db: Firestore) { self.db = db }

    // 1) 匿名サインイン（必要なら）
    func signInAnonymouslyIfNeeded() async throws -> String {
        if let current = Auth.auth().currentUser {
            return current.uid
        }
        let result = try await Auth.auth().signInAnonymously()
        return result.user.uid
    }
    
    // 2) ルームに入室（roomId + roomKey + username）
    func joinRoom(_ params: JoinParams) async throws {
        let roomIdSan = params.roomId.trimmingCharacters(in: .whitespacesAndNewlines)
        let roomKeySan = params.roomKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let userNameSan = params.username.trimmingCharacters(in: .whitespacesAndNewlines)

        let uid = try await signInAnonymouslyIfNeeded()
        
        // 既に会員かどうかを先に確認
        let existed = try await isUserAlreadyInRoom(roomId: roomIdSan, uid: uid)

        let roomRef   = db.collection("rooms").document(roomIdSan)
        let memberRef = roomRef.collection("members").document(uid)
        let usernameLower = userNameSan.lowercased()

        // NOTE: roomSecrets はクライアントから読まない。providedKey はルール側で照合。
        do {
            try await runTransactionAsync(db: db) { (txn: FirebaseFirestore.Transaction) in
                if existed {
                    // (1) 既存会員: 表示名/アイコン/最終サインイン時間だけ更新（providedKey は送らない）
                    var updates: [String: Any] = [
                        "username": userNameSan,
                        "usernameLower": usernameLower,
                        "lastSignedInAt": FieldValue.serverTimestamp(),
                        "userIcon": params.selectedIcon
                    ]
                    txn.setData(updates, forDocument: memberRef, merge: true)
                } else {
                    // (1) 新規作成: providedKey を含めて create（ルールで検証）
                    var memberData: [String: Any] = [
                        "username": userNameSan,
                        "usernameLower": usernameLower,
                        "role": "member",
                        "joinedAt": FieldValue.serverTimestamp(),
                        "lastSignedInAt": FieldValue.serverTimestamp(),
                        "isBanned": false,
                        "mutedUntil": NSNull(),
                        "providedKey": roomKeySan,
                        "userIcon": params.selectedIcon
                    ]
                    txn.setData(memberData, forDocument: memberRef, merge: false)
                }
            }
        } catch {
            let ns = error as NSError
            print("[RoomRepository] joinRoom transaction failed: domain=\(ns.domain) code=\(ns.code) userInfo=\(ns.userInfo)")
            throw error
        }

        // create のときのみ providedKey を消す
        if !existed {
            try await memberRef.updateData(["providedKey": FieldValue.delete()])
        }
    }
    
    // 3) ルーム内での username 変更
    func changeUsername(roomId: String, newUsername: String) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { throw JoinError.notSignedIn }

        // 入力サニタイズ
        let roomIdSan = roomId.trimmingCharacters(in: .whitespacesAndNewlines)
        let usernameSan = newUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !usernameSan.isEmpty else {
            throw NSError(domain: "User", code: 400, userInfo: [NSLocalizedDescriptionKey: "ユーザー名を入力してください"])
        }

        let roomRef   = db.collection("rooms").document(roomIdSan)
        let memberRef = roomRef.collection("members").document(uid)

        let newLower  = usernameSan.lowercased()

        do {
            try await runTransactionAsync(db: db) { (txn: FirebaseFirestore.Transaction) in
                // username は表示名として重複を許容するため、ロック操作は不要
                txn.setData([
                    "username": usernameSan,
                    "usernameLower": newLower
                ], forDocument: memberRef, merge: true)
            }
        } catch {
            let ns = error as NSError
            print("[RoomRepository] changeUsername failed: domain=\(ns.domain) code=\(ns.code) userInfo=\(ns.userInfo)")
            // ルールの一意性制約に引っかかった場合は PermissionDenied(=7) になる想定
            if (ns.domain == FirestoreErrorDomain || ns.domain == "FIRFirestoreErrorDomain") && ns.code == 7 {
                throw JoinError.usernameTaken
            }
            throw error
        }
    }

    // 4) 退室（ロック解放＋member削除＋カウント減）
    func leaveRoom(roomId: String) async throws {
        let roomIdSan = roomId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let uid = Auth.auth().currentUser?.uid else { throw JoinError.notSignedIn }
        let roomRef   = db.collection("rooms").document(roomIdSan)
        let memberRef = roomRef.collection("members").document(uid)

        try await runTransactionAsync(db: db) { (txn: FirebaseFirestore.Transaction) in
            // 会員 doc
            let memberSnap = try txn.getDocument(memberRef)
            guard let member = memberSnap.data() else { return }

            // 会員 doc 削除
            txn.deleteDocument(memberRef)
        }
    }
    
    // 5) アカウント削除（指定ルーム内の自分の痕跡を削除：likes / userLikes / 自分の投稿 / members）
    /// Firestore 側のみ削除します（Storage のメディア削除は別サービスで対応してください）
    func deleteMyAccount(in roomId: String) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { throw JoinError.notSignedIn }
        let roomIdSan = roomId.trimmingCharacters(in: .whitespacesAndNewlines)
        let roomRef = db.collection("rooms").document(roomIdSan)

        // 1) /rooms/{roomId}/userLikes/{uid}/posts/* を削除
        do {
            let userLikesPosts = roomRef
                .collection("userLikes")
                .document(uid)
                .collection("posts")
            try await batchDelete(query: userLikesPosts)
        } catch {
            let ns = error as NSError
            print("[RoomRepository] deleteMyAccount userLikes cleanup failed: domain=\(ns.domain) code=\(ns.code) userInfo=\(ns.userInfo)")
            throw error
        }

        // 2) collectionGroup("likes") から自分の like を当該ルーム分だけ削除
        //    （要インデックス： userId / roomId / __name__）
        do {
            let likesGroup = db.collectionGroup("likes")
                .whereField("userId", isEqualTo: uid)
                .whereField("roomId", isEqualTo: roomIdSan)
            try await batchDelete(query: likesGroup)
        } catch {
            let ns = error as NSError
            print("[RoomRepository] deleteMyAccount likes cleanup failed: domain=\(ns.domain) code=\(ns.code) userInfo=\(ns.userInfo)")
            throw error
        }

        // 3) 自分が author の投稿を削除（各投稿の likes サブコレクションを先に削除）
        do {
            var last: DocumentSnapshot?
            while true {
                var q = roomRef.collection("posts")
                    .whereField("authorId", isEqualTo: uid)
                    .order(by: FieldPath.documentID())
                    .limit(to: 200)
                if let last { q = q.start(afterDocument: last) }
                let snap = try await q.getDocuments(source: .server)
                if snap.documents.isEmpty { break }

                // 各ポストの likes をクリア → 本体をまとめて削除
                let batch = db.batch()
                for doc in snap.documents {
                    let postRef = doc.reference
                    // サブコレ likes を全削除
                    let likes = postRef.collection("likes")
                    try await batchDelete(query: likes)
                    // 本体削除
                    batch.deleteDocument(postRef)
                }
                try await batch.commit()
                last = snap.documents.last
            }
        } catch {
            let ns = error as NSError
            print("[RoomRepository] deleteMyAccount authored posts cleanup failed: domain=\(ns.domain) code=\(ns.code) userInfo=\(ns.userInfo)")
            throw error
        }

        // 4) members/{uid} を削除（最終）
        do {
            let memberRef = roomRef.collection("members").document(uid)
            try await memberRef.delete()
        } catch {
            let ns = error as NSError
            print("[RoomRepository] deleteMyAccount member delete failed: domain=\(ns.domain) code=\(ns.code) userInfo=\(ns.userInfo)")
            throw error
        }
    }

    // MARK: - Helpers
    /// 指定クエリの結果をページングしながら一括削除（__name__ でソート → start(after:)）
    private func batchDelete(query base: Query, pageSize: Int = 300) async throws {
        var last: DocumentSnapshot? = nil
        while true {
            var q = base.order(by: FieldPath.documentID()).limit(to: pageSize)
            if let last { q = q.start(afterDocument: last) }
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

    
    /// 指定したルームにすでに入室済みかを確認する
    func isUserAlreadyInRoom(roomId: String, uid: String) async throws -> Bool {
        let roomIdSan = roomId.trimmingCharacters(in: .whitespacesAndNewlines)
        let memberRef = db
            .collection("rooms")
            .document(roomIdSan)
            .collection("members")
            .document(uid)
        do {
            // サーバー優先で存在確認（キャッシュの残骸に左右されない）
            let snapshot = try await memberRef.getDocument(source: .server)
            return snapshot.exists
        } catch {
            let ns = error as NSError
            print("[RoomRepository] isUserAlreadyInRoom failed: domain=\(ns.domain) code=\(ns.code) userInfo=\(ns.userInfo)")
            throw error
        }
    }
    
    // MARK: - Fetch (single shot)
    /// 自分の会員プロフィールを単発取得（サーバー優先）。
    /// 返却は UI で使いやすい最小セット（username / userIcon）。
    func fetchRoomUser(roomId: String, uid: String) async throws -> (username: String, userIcon: String?)? {
        let roomIdSan = roomId.trimmingCharacters(in: .whitespacesAndNewlines)
        let ref = db.collection("rooms").document(roomIdSan)
            .collection("members").document(uid)
        do {
            let snap = try await ref.getDocument(source: .server)
            guard let data = snap.data() else { return nil }
            guard let username = data["username"] as? String, !username.isEmpty else { return nil }
            let userIcon = data["userIcon"] as? String
            return (username: username, userIcon: userIcon)
        } catch {
            let ns = error as NSError
            print("[RoomRepository] fetchRoomUser failed: domain=\(ns.domain) code=\(ns.code) userInfo=\(ns.userInfo)")
            throw error
        }
    }
   
    // MARK: - Transaction async wrapper
    // NOTE: Session は @MainActor だが、Firestore のトランザクションは内部スレッドで実行される。
    // MainActor 隔離のクロージャをそのまま渡すと実行キュー不一致でクラッシュするため、
    // nonisolated のヘルパに切り出し、MainActor に依存しない値だけをキャプチャして実行する。
    private nonisolated func runTransactionAsync(
        db: Firestore,
        body: @Sendable @escaping (FirebaseFirestore.Transaction) throws -> Void
    ) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            db.runTransaction({ (txn, errorPointer) -> Any? in
                do {
                    try body(txn)
                    return nil
                } catch {
                    errorPointer?.pointee = error as NSError
                    return nil
                }
            }, completion: { _, err in
                if let err {
                    cont.resume(throwing: err)
                } else {
                    cont.resume(returning: ())
                }
            })
        }
    }
    
}
