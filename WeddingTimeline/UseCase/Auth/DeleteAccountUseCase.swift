//
//  DeleteAccountUseCase.swift
//  WeddingTimeline
//
//  アカウント削除フローを担当する UseCase。
//  Firestore データ削除 → Firebase Auth アカウント削除 → セッション状態クリアを行う。
//

import Foundation

@MainActor
final class DeleteAccountUseCase {
    private let session: SessionStore
    private let roomRepo: RoomRepository
    private let authDS: FirebaseAuthDataSource

    init(
        session:  SessionStore,
        roomRepo: RoomRepository       = RoomRepository(),
        authDS:   FirebaseAuthDataSource = FirebaseAuthDataSource()
    ) {
        self.session  = session
        self.roomRepo = roomRepo
        self.authDS   = authDS
    }

    func execute() async throws {
        let roomIdSan = session.currentRoomId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !roomIdSan.isEmpty else {
            throw NSError(
                domain: "DeleteAccountUseCase", code: 400,
                userInfo: [NSLocalizedDescriptionKey: "削除対象のルームが見つかりません"]
            )
        }
        // Firestore データ削除
        try await roomRepo.deleteMyAccount(in: roomIdSan)
        // Auth アカウント削除（Firestore 削除後に失敗した場合はエラーを伝播）
        try await authDS.deleteCurrentUser()
        session.isLoggedIn    = false
        session.currentRoomId = ""
        session.cachedMember  = nil
    }
}
