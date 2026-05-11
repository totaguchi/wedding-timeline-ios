//
//  UserRepository.swift
//  WeddingTimeline
//
//  ユーザー/メンバー情報の取得・更新を担当する Repository。
//  Firestore / Storage の直接操作は DataSource に委譲し、
//  このクラスは orchestration と Entity マッピングに専念する。
//

import Foundation

final class UserRepository {

    // MARK: - Dependencies

    private let firestoreDS: FirestoreRoomDataSource
    private let storageDS: StorageMediaDataSource

    init(
        firestoreDS: FirestoreRoomDataSource = FirestoreRoomDataSource(),
        storageDS:   StorageMediaDataSource  = StorageMediaDataSource()
    ) {
        self.firestoreDS = firestoreDS
        self.storageDS   = storageDS
    }

    // MARK: - Fetch

    /// メンバー情報を単発取得する（サーバー優先）
    func fetchRoomUser(roomId: String, uid: String) async throws -> RoomMember? {
        guard let dto = try await firestoreDS.fetchMemberDTO(roomId: roomId, uid: uid) else {
            return nil
        }
        return RoomMember(roomId: roomId, dto: dto)
    }

    // MARK: - Listen

    /// メンバー情報をリアルタイム購読する
    func listenRoomUser(roomId: String, uid: String) -> AsyncThrowingStream<RoomMember?, Error> {
        AsyncThrowingStream { cont in
            let stream = self.firestoreDS.listenMemberDTO(roomId: roomId, uid: uid)
            let task = Task {
                do {
                    for try await dto in stream {
                        if let dto {
                            cont.yield(RoomMember(roomId: roomId, dto: dto))
                        } else {
                            cont.yield(nil)
                        }
                    }
                    cont.finish()
                } catch {
                    cont.finish(throwing: error)
                }
            }
            // 外側のストリームが終了したら内側の Task をキャンセルする
            cont.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Username

    /// ユーザー名を変更する（一意性ロック付きトランザクション）
    ///
    /// - Throws: ユーザー名が重複している場合や Firestore エラー
    func changeUsername(roomId: String, newUsername: String, uid: String) async throws {
        let trimmed = newUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        try await firestoreDS.changeUsername(roomId: roomId, newUsername: trimmed, uid: uid)
    }

    // MARK: - Avatar

    /// アバター画像を更新する（Storage アップロード → Firestore URL 保存）
    ///
    /// - Returns: Storage にアップロードした画像のダウンロード URL
    @discardableResult
    func changeAvatar(
        roomId: String,
        uid: String,
        imageData: Data,
        contentType: String = "image/jpeg"
    ) async throws -> URL {
        // Storage パス: avatars/{roomId}/{uid}.jpg
        let path = "avatars/\(roomId)/\(uid).jpg"
        let url  = try await storageDS.upload(data: imageData, path: path, contentType: contentType)
        try await firestoreDS.saveAvatarURL(roomId: roomId, uid: uid, urlString: url.absoluteString)
        return url
    }
}
