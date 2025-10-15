//
//  UserRepository.swift
//  WeddingTimeline
//
//  Created by 田口友暉 on 2025/08/31.
//

import Foundation
@preconcurrency import FirebaseFirestore
import FirebaseStorage

final class UserRepository {
    private let db = Firestore.firestore()
    private let storage = Storage.storage()

    // 1) 単発取得
    func fetchRoomUser(roomId: String, uid: String) async throws -> RoomMember? {
        let ref = db.collection("rooms").document(roomId)
            .collection("members").document(uid)
        let snap = try await ref.getDocument()
        let dto: RoomMemberDTO? = try await MainActor.run { try snap.data(as: RoomMemberDTO.self) }
        guard let dto else { return nil }
        return RoomMember(roomId: roomId, dto: dto)
    }

    // 2) 監視
    func listenRoomUser(roomId: String, uid: String) -> AsyncThrowingStream<RoomMember?, Error> {
        AsyncThrowingStream { cont in
            let ref = db.collection("rooms").document(roomId)
                .collection("members").document(uid)
            let l = ref.addSnapshotListener { snap, err in
                if let err { cont.finish(throwing: err); return }
                guard let snap else { cont.yield(nil); return }
                Task { @MainActor in
                    do {
                        // DocumentSnapshot may exist == false even when snap is non-nil
                        if !snap.exists {
                            cont.yield(nil)
                            return
                        }
                        let dto: RoomMemberDTO = try snap.data(as: RoomMemberDTO.self)
                        cont.yield(RoomMember(roomId: roomId, dto: dto))
                    } catch {
                        cont.finish(throwing: error)
                    }
                }
            }
            cont.onTermination = { _ in l.remove() }
        }
    }

    // 3) username を更新（ルーム単位）
    func changeUsername(roomId: String, newUsername: String, uid: String) async throws {
        let roomRef = db.collection("rooms").document(roomId)
        let memberRef = roomRef.collection("members").document(uid)
        let lower = newUsername.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        try await runTransactionAsync { txn in
            let lockRef = roomRef.collection("usernames").document(lower)
            if (try? txn.getDocument(lockRef))?.exists == true {
                throw NSError(domain: "UserRepository", code: 1, userInfo: [NSLocalizedDescriptionKey: "username is taken"])
            }
            // 旧ロック解除
            if let old = try? txn.getDocument(memberRef).data()? ["usernameLower"] as? String, !old.isEmpty {
                let oldRef = roomRef.collection("usernames").document(old)
                if (try? txn.getDocument(oldRef))?.exists == true { txn.deleteDocument(oldRef) }
            }
            // 新ロック確保＆member更新
            txn.setData(["uid": uid, "createdAt": FieldValue.serverTimestamp()], forDocument: lockRef)
            txn.setData(["username": newUsername, "usernameLower": lower], forDocument: memberRef, merge: true)
        }
    }

    // 4) ルーム用アイコンを更新（Storageアップ→URL保存）
    func changeAvatar(roomId: String, uid: String, imageData: Data, contentType: String = "image/jpeg") async throws {
        // 推奨パス: avatars/{roomId}/{uid}.jpg
        let path = "avatars/\(roomId)/\(uid).jpg"
        let ref = storage.reference(withPath: path)

        let meta = StorageMetadata()
        meta.contentType = contentType

        // putData (callback API) を continuation で await 化
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            ref.putData(imageData, metadata: meta) { _, error in
                if let error {
                    cont.resume(throwing: error)
                } else {
                    cont.resume(returning: ())
                }
            }
        }

        // downloadURL も continuation で await 化
        let url: URL = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<URL, Error>) in
            ref.downloadURL { url, error in
                if let url {
                    cont.resume(returning: url)
                } else {
                    cont.resume(throwing: error ?? NSError(domain: "UserRepository", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to get download URL"]))
                }
            }
        }

        try await db.collection("rooms").document(roomId)
            .collection("members").document(uid)
            .updateData(["avatarURL": url.absoluteString])
    }

    private func runTransactionAsync(_ body: @escaping (Transaction) throws -> Void) async throws {
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
