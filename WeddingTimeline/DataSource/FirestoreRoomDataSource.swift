//
//  FirestoreRoomDataSource.swift
//  WeddingTimeline
//
//  ルーム・メンバー関連の Firestore SDK 操作を集約する DataSource。
//  RoomRepository / UserRepository は Firestore SDK を直接参照せず、
//  このクラスを経由する。
//

@preconcurrency import FirebaseFirestore
import FirebaseAuth
import Foundation

/// ルーム/メンバー関連 Firestore SDK 呼び出しを集約する DataSource。
///
/// - 入室トランザクション・退室・メンバー取得・アバター URL 保存など
///   Firestore の直接操作をすべてここに閉じる。
/// - エラーは Firebase SDK エラーのまま throw するか、
///   ユーザー向け文言へのマッピングが必要な場合は内部でマップして throw する。
final class FirestoreRoomDataSource {

    private let db = Firestore.firestore()

    // MARK: - Membership

    /// 指定ルームにすでに入室済みかを確認する（サーバー優先）
    func isUserAlreadyInRoom(roomId: String, uid: String) async throws -> Bool {
        let snap = try await db
            .collection("rooms").document(roomId)
            .collection("members").document(uid)
            .getDocument(source: .server)
        return snap.exists
    }

    /// 入室トランザクションを実行する
    ///
    /// - Parameters:
    ///   - roomId: 入室するルームの ID（サニタイズ済み）
    ///   - uid: 入室するユーザーの UID
    ///   - params: 入室パラメータ
    ///   - existed: すでに会員ドキュメントが存在するか
    /// - Throws: Firestore ルール違反・ネットワークエラー等（mapJoinError でユーザー文言に変換済み）
    func joinMember(roomId: String, uid: String, params: JoinParams, existed: Bool) async throws {
        let roomRef   = db.collection("rooms").document(roomId)
        let memberRef = roomRef.collection("members").document(uid)
        let usernameLower = params.username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let usernameSan   = params.username.trimmingCharacters(in: .whitespacesAndNewlines)
        let roomKeySan    = params.roomKey.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            try await db.runTransactionAsync { (txn: Transaction) in
                if existed {
                    // 既存会員: 表示名 / アイコン / 最終サインイン時間のみ更新
                    // NOTE: フィールドキーは RoomMemberDTO.usericon（小文字）に統一
                    txn.setData([
                        "username": usernameSan,
                        "usernameLower": usernameLower,
                        "lastSignedInAt": FieldValue.serverTimestamp(),
                        "usericon": params.selectedIcon
                    ], forDocument: memberRef, merge: true)
                } else {
                    // 新規作成: providedKey を含めて create（Firestore ルールで検証）
                    // NOTE: フィールドキーは RoomMemberDTO.usericon（小文字）に統一
                    txn.setData([
                        "username": usernameSan,
                        "usernameLower": usernameLower,
                        "role": "member",
                        "joinedAt": FieldValue.serverTimestamp(),
                        "lastSignedInAt": FieldValue.serverTimestamp(),
                        "isBanned": false,
                        "mutedUntil": NSNull(),
                        "providedKey": roomKeySan,
                        "usericon": params.selectedIcon
                    ], forDocument: memberRef, merge: false)
                }
            }
        } catch {
            throw mapJoinError(error, roomId: roomId)
        }
    }

    /// 入室後の providedKey フィールドを削除する（新規入室時のみ）
    ///
    /// 失敗しても入室自体は完了しているため、呼び出し側は握りつぶしてよい。
    func removeProvidedKey(roomId: String, uid: String) async throws {
        try await db
            .collection("rooms").document(roomId)
            .collection("members").document(uid)
            .updateData(["providedKey": FieldValue.delete()])
    }

    // MARK: - Member CRUD

    /// メンバーの DTO を単発取得する（サーバー優先）
    ///
    /// - Returns: メンバーが存在しない場合は `nil`
    func fetchMemberDTO(roomId: String, uid: String) async throws -> RoomMemberDTO? {
        let snap = try await db
            .collection("rooms").document(roomId)
            .collection("members").document(uid)
            .getDocument(source: .server)
        guard snap.exists else { return nil }
        return try snap.data(as: RoomMemberDTO.self)
    }

    /// メンバー情報をリアルタイム購読する
    ///
    /// - Returns: DTO の変化を流すストリーム（ドキュメント削除時は nil を yield）
    func listenMemberDTO(roomId: String, uid: String) -> AsyncThrowingStream<RoomMemberDTO?, Error> {
        AsyncThrowingStream { cont in
            let ref = db
                .collection("rooms").document(roomId)
                .collection("members").document(uid)
            let listener = ref.addSnapshotListener { snap, err in
                if let err { cont.finish(throwing: err); return }
                guard let snap else { cont.yield(nil); return }
                guard snap.exists else { cont.yield(nil); return }
                do {
                    let dto = try snap.data(as: RoomMemberDTO.self)
                    cont.yield(dto)
                } catch {
                    cont.finish(throwing: error)
                }
            }
            cont.onTermination = { _ in listener.remove() }
        }
    }

    /// ユーザー名を変更する（一意性ロック付きトランザクション）
    ///
    /// - Throws: ユーザー名が重複している場合は `username is taken` エラー
    func changeUsername(roomId: String, newUsername: String, uid: String) async throws {
        let roomRef   = db.collection("rooms").document(roomId)
        let memberRef = roomRef.collection("members").document(uid)
        let lower     = newUsername.lowercased()

        try await db.runTransactionAsync { txn in
            let lockRef = roomRef.collection("usernames").document(lower)
            if let lockDoc = try? txn.getDocument(lockRef), lockDoc.exists {
                // 同じ uid が持つロックなら自己リネーム（大文字小文字変更など）として続行
                let lockOwner = lockDoc.data()?["uid"] as? String
                if lockOwner != uid {
                    throw NSError(
                        domain: "FirestoreRoomDataSource",
                        code: 1,
                        userInfo: [NSLocalizedDescriptionKey: "username is taken"]
                    )
                }
            }
            // 旧ロック解除
            if let oldLower = try? txn.getDocument(memberRef).data()?["usernameLower"] as? String,
               !oldLower.isEmpty {
                let oldRef = roomRef.collection("usernames").document(oldLower)
                if (try? txn.getDocument(oldRef))?.exists == true {
                    txn.deleteDocument(oldRef)
                }
            }
            // 新ロック確保 & member 更新
            txn.setData(
                ["uid": uid, "createdAt": FieldValue.serverTimestamp()],
                forDocument: lockRef
            )
            txn.setData(
                ["username": newUsername, "usernameLower": lower],
                forDocument: memberRef,
                merge: true
            )
        }
    }

    /// 退室トランザクション（会員ドキュメント削除）
    func leaveRoom(roomId: String, uid: String) async throws {
        let memberRef = db
            .collection("rooms").document(roomId)
            .collection("members").document(uid)

        try await db.runTransactionAsync { txn in
            let snap = try txn.getDocument(memberRef)
            guard snap.data() != nil else { return }
            txn.deleteDocument(memberRef)
        }
    }

    /// 指定ルーム内の自分の痕跡を削除する
    ///
    /// 削除順: userLikes → likes（collectionGroup）→ 投稿（likes サブコレクション含む）→ member
    func deleteMyAccount(in roomId: String, uid: String) async throws {
        let roomRef = db.collection("rooms").document(roomId)

        // 1) userLikes 削除
        let userLikesPosts = roomRef.collection("userLikes").document(uid).collection("posts")
        try await batchDelete(query: userLikesPosts)

        // 2) collectionGroup("likes") から自分の like を削除
        // NOTE: like ドキュメントを消すが、投稿側の likeCount フィールドは更新しない。
        //       各投稿のカウントを 1 件ずつ読んで差し引くと大量の読み取りが発生するため、
        //       既存の設計上この不整合は許容している。
        let likesGroup = db.collectionGroup("likes")
            .whereField("userId", isEqualTo: uid)
            .whereField("roomId", isEqualTo: roomId)
        try await batchDelete(query: likesGroup)

        // 3) 自分が author の投稿を削除
        var lastDoc: DocumentSnapshot?
        while true {
            var q = roomRef.collection("posts")
                .whereField("authorId", isEqualTo: uid)
                .order(by: FieldPath.documentID())
                .limit(to: 200)
            if let last = lastDoc { q = q.start(afterDocument: last) }
            let snap = try await q.getDocuments(source: .server)
            if snap.documents.isEmpty { break }

            let batch = db.batch()
            for doc in snap.documents {
                try await batchDelete(query: doc.reference.collection("likes"))
                batch.deleteDocument(doc.reference)
            }
            try await batch.commit()
            lastDoc = snap.documents.last
        }

        // 4) member ドキュメント削除
        try await roomRef.collection("members").document(uid).delete()
    }

    // MARK: - Avatar

    /// アバター URL を Firestore に保存する
    ///
    /// - Note: Firestore キーは `avatarURL`、読み取り時の `usericon` とは異なるため
    ///         再フェッチでは反映されない。キャッシュ更新は呼び出し元が担う。
    func saveAvatarURL(roomId: String, uid: String, urlString: String) async throws {
        try await db
            .collection("rooms").document(roomId)
            .collection("members").document(uid)
            .updateData(["avatarURL": urlString])
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

    // MARK: - Error Mapping

    /// Firestore / Auth / Network エラーをユーザー向け文言に変換
    private func mapJoinError(_ error: Error, roomId: String) -> NSError {
        let ns = error as NSError
        let domain = ns.domain

        if domain == FirestoreErrorDomain || domain == "FIRFirestoreErrorDomain" {
            let msg: String
            switch ns.code {
            case 7:  msg = "入室に失敗しました。ルームIDまたは入室キーが正しいか確認してください。"
            case 5:  msg = "指定のルームが見つかりませんでした。ルームIDをご確認ください。"
            case 4:  msg = "タイムアウトしました。通信環境を確認して、もう一度お試しください。"
            case 14: msg = "サーバーに接続できませんでした。しばらくしてから再度お試しください。"
            case 2:  msg = "操作がキャンセルされました。再度お試しください。"
            default: msg = "入室に失敗しました（\(ns.code)）。しばらくしてから再度お試しください。"
            }
            return NSError(domain: "JoinRoom", code: ns.code, userInfo: [
                NSLocalizedDescriptionKey: msg,
                NSUnderlyingErrorKey: ns
            ])
        }

        if domain == AuthErrorDomain || domain == "FIRAuthErrorDomain" {
            let msg: String
            switch ns.code {
            case AuthErrorCode.networkError.rawValue:
                msg = "ネットワークエラーのためサインインできませんでした。通信状況を確認して再度お試しください。"
            case AuthErrorCode.tooManyRequests.rawValue:
                msg = "リクエストが集中しています。時間をおいて再度お試しください。"
            default:
                msg = "サインインに失敗しました。もう一度お試しください。"
            }
            return NSError(domain: "JoinRoom", code: ns.code, userInfo: [
                NSLocalizedDescriptionKey: msg,
                NSUnderlyingErrorKey: ns
            ])
        }

        if domain == NSURLErrorDomain {
            let msg: String
            switch ns.code {
            case NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost, NSURLErrorTimedOut:
                msg = "ネットワークに接続できません。通信環境を確認して再度お試しください。"
            default:
                msg = "通信エラーが発生しました。時間をおいてお試しください。"
            }
            return NSError(domain: "JoinRoom", code: ns.code, userInfo: [
                NSLocalizedDescriptionKey: msg,
                NSUnderlyingErrorKey: ns
            ])
        }

        return NSError(domain: "JoinRoom", code: ns.code, userInfo: [
            NSLocalizedDescriptionKey: "入室に失敗しました。しばらくしてから再度お試しください。",
            NSUnderlyingErrorKey: ns
        ])
    }
}
