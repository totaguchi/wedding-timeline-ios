//
//  RoomRepository.swift
//  WeddingTimeline
//
//  ルーム入退室・アカウント管理を担当する Repository。
//  Firestore / Auth の直接操作は DataSource に委譲し、
//  このクラスは orchestration とエラー変換に専念する。
//

import Foundation

// NOTE: username は表示名として重複許容。uniqueness ロックは使用しない。
final class RoomRepository {

    // MARK: - Dependencies

    private let firestoreDS: FirestoreRoomDataSource
    private let authDS: FirebaseAuthDataSource

    init(
        firestoreDS: FirestoreRoomDataSource = FirestoreRoomDataSource(),
        authDS:      FirebaseAuthDataSource  = FirebaseAuthDataSource()
    ) {
        self.firestoreDS = firestoreDS
        self.authDS      = authDS
    }

    // MARK: - Auth

    /// 匿名サインインが未実施なら実施し UID を返す
    func signInAnonymouslyIfNeeded() async throws -> String {
        try await authDS.ensureSignedIn()
    }

    // MARK: - Room

    /// ルームに入室する（匿名サインイン → 存在確認 → トランザクション）
    func joinRoom(_ params: JoinParams) async throws {
        let roomIdSan   = params.roomId.trimmingCharacters(in: .whitespacesAndNewlines)
        let roomKeySan  = params.roomKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let userNameSan = params.username.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !roomIdSan.isEmpty else {
            throw NSError(domain: "JoinRoom", code: 1001, userInfo: [
                NSLocalizedDescriptionKey: "ルームIDを入力してください。"
            ])
        }
        guard !roomKeySan.isEmpty else {
            throw NSError(domain: "JoinRoom", code: 1002, userInfo: [
                NSLocalizedDescriptionKey: "入室キーを入力してください。"
            ])
        }
        guard !userNameSan.isEmpty else {
            throw NSError(domain: "JoinRoom", code: 1003, userInfo: [
                NSLocalizedDescriptionKey: "ユーザー名を入力してください。"
            ])
        }

        let uid     = try await authDS.ensureSignedIn()
        let existed = try await firestoreDS.isUserAlreadyInRoom(roomId: roomIdSan, uid: uid)

        // DataSource 内でエラーマッピング済み
        try await firestoreDS.joinMember(
            roomId: roomIdSan,
            uid: uid,
            params: params,
            existed: existed
        )

        if !existed {
            do {
                try await firestoreDS.removeProvidedKey(roomId: roomIdSan, uid: uid)
            } catch {
                // 入室自体は完了しているため、ログ出力のみ
                print("[RoomRepository] cleanup providedKey failed: \(error)")
            }
        }
    }

    /// 退室する（会員ドキュメント削除）
    func leaveRoom(roomId: String) async throws {
        guard let uid = authDS.currentUID() else { throw JoinError.notSignedIn }
        let roomIdSan = roomId.trimmingCharacters(in: .whitespacesAndNewlines)
        try await firestoreDS.leaveRoom(roomId: roomIdSan, uid: uid)
    }

    /// アカウントを削除する（指定ルーム内の自分の痕跡を削除）
    func deleteMyAccount(in roomId: String) async throws {
        guard let uid = authDS.currentUID() else { throw JoinError.notSignedIn }
        let roomIdSan = roomId.trimmingCharacters(in: .whitespacesAndNewlines)
        try await firestoreDS.deleteMyAccount(in: roomIdSan, uid: uid)
    }

    // MARK: - Fetch

    /// 指定ルームにすでに入室済みかを確認する
    func isUserAlreadyInRoom(roomId: String, uid: String) async throws -> Bool {
        let roomIdSan = roomId.trimmingCharacters(in: .whitespacesAndNewlines)
        return try await firestoreDS.isUserAlreadyInRoom(roomId: roomIdSan, uid: uid)
    }

    /// 自分の会員プロフィールを単発取得する（サーバー優先）
    ///
    /// - Returns: `username` / `userIcon` の最小セット。存在しない場合は nil
    func fetchRoomUser(roomId: String, uid: String) async throws -> (username: String, userIcon: String?)? {
        let roomIdSan = roomId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let dto = try await firestoreDS.fetchMemberDTO(roomId: roomIdSan, uid: uid) else {
            return nil
        }
        guard !dto.username.isEmpty else { return nil }
        return (username: dto.username, userIcon: dto.usericon)
    }
}
