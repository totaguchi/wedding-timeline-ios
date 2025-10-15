//
//  RoomRepository.swift
//  WeddingTimeline
//
//  Created by 田口友暉 on 2025/08/31.
//

import Foundation
import FirebaseAuth
import FirebaseFirestore

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

        // 匿名サインインして uid を確保
        if Auth.auth().currentUser == nil {
            _ = try await Auth.auth().signInAnonymously()
        }
        guard let uid = Auth.auth().currentUser?.uid else { throw JoinError.notSignedIn }
        
        if try await isUserAlreadyInRoom(roomId: roomIdSan, uid: uid) {
            return
        }
        
        // roomSecrets で roomKey をサーバー照会して検証（入室処理の前に実施）
        let roomRef   = db.collection("rooms").document(roomIdSan)
        let secretRef = db.collection("roomSecrets").document(roomIdSan)
        do {
            let secretSnap = try await secretRef.getDocument(source: .server)
            guard let secretData = secretSnap.data(),
                  let storedKey = secretData["roomKey"] as? String else {
                throw NSError(domain: "Auth", code: 404, userInfo: [NSLocalizedDescriptionKey: "このルームは存在しません"])
            }
            guard storedKey == roomKeySan else {
                throw NSError(domain: "Auth", code: 403, userInfo: [NSLocalizedDescriptionKey: "ルームキーが違います"])
            }
        } catch {
            let ns = error as NSError
            print("[RoomRepository] roomKey validation failed: domain=\(ns.domain) code=\(ns.code) userInfo=\(ns.userInfo)")
            throw error
        }

        let usernameLower = userNameSan
            .lowercased()

        let usernameRef = roomRef.collection("usernames").document(usernameLower)
        let memberRef   = roomRef.collection("members").document(uid)

        do {
            try await runTransactionAsync(db: db) { (txn: FirebaseFirestore.Transaction) in
                // (1) username ロック: create を試みる（既存なら rules で update 拒否）
                txn.setData([
                    "uid": uid,
                    "createdAt": FieldValue.serverTimestamp()
                ], forDocument: usernameRef, merge: false)

                // (2) members/{uid} 作成（providedKey はルールで検証）
                var memberData: [String: Any] = [
                    "username": userNameSan,
                    "usernameLower": usernameLower,
                    "role": "member",
                    "joinedAt": FieldValue.serverTimestamp(),
                    "isBanned": false,
                    "mutedUntil": NSNull(),
                    "providedKey": roomKeySan
                ]
            
                memberData["userIcon"] = params.selectedIcon // 既存スキーマに合わせて保持（avatarKey を使う場合はここを変更）
                txn.setData(memberData, forDocument: memberRef, merge: false)

                // (3) memberCount はクライアントでは更新しない（集計は Cloud Functions 推奨）
            }
        } catch {
            let ns = error as NSError
            print("[RoomRepository] joinRoom transaction failed: domain=\(ns.domain) code=\(ns.code) userInfo=\(ns.userInfo)")
            throw error
        }

        // B案: 書き込み直後に providedKey を消す
        try await db.collection("rooms").document(roomIdSan)
            .collection("members").document(uid)
            .updateData(["providedKey": FieldValue.delete()])
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
        let newLock   = roomRef.collection("usernames").document(newLower)

        do {
            try await runTransactionAsync(db: db) { (txn: FirebaseFirestore.Transaction) in
                // 自分の member を読み取り（これはルールで許可されている）
                let memberSnap = try txn.getDocument(memberRef)
                guard let member = memberSnap.data() else {
                    throw NSError(domain: "Room", code: 404, userInfo: [NSLocalizedDescriptionKey: "メンバー情報が見つかりません"])
                }

                let oldLower = (member["usernameLower"] as? String)?.lowercased() ?? ""
                if oldLower == newLower {
                    // 変更なし: 何もしない
                    return
                }

                // 新しいロックを作成（存在チェックはせず、ルール側の "!exists" で一意性を担保する）
                txn.setData([
                    "uid": uid,
                    "createdAt": FieldValue.serverTimestamp()
                ], forDocument: newLock, merge: false)

                // 旧ロックを解放（read 権限は無いので存在チェックなしで delete）
                if !oldLower.isEmpty {
                    let oldLock = roomRef.collection("usernames").document(oldLower)
                    txn.deleteDocument(oldLock)
                }

                // member を更新
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

            // username ロック解放（read 権限が無いため存在チェックは行わず、直接 delete）
            if let lower = member["usernameLower"] as? String, !lower.isEmpty {
                let lockRef = roomRef.collection("usernames").document(lower)
                txn.deleteDocument(lockRef) // 既存でも未存在でも OK（delete 権限のみ評価される）
            }

            // 会員 doc 削除
            txn.deleteDocument(memberRef)
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
