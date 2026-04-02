//
//  DeleteAccountUseCase.swift
//  WeddingTimeline
//
//  アカウント削除フローを担当する UseCase。
//  Firestore データ削除 → Firebase Auth アカウント削除 → セッション状態クリアを行う。
//

import FirebaseAuth
import Foundation

@MainActor
final class DeleteAccountUseCase {
    private let session: SessionStore
    private let roomRepo: RoomRepository

    init(session: SessionStore, roomRepo: RoomRepository = RoomRepository()) {
        self.session = session
        self.roomRepo = roomRepo
    }

    func execute() async throws {
        let roomIdSan = session.currentRoomId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !roomIdSan.isEmpty else {
            throw NSError(
                domain: "DeleteAccountUseCase", code: 400,
                userInfo: [NSLocalizedDescriptionKey: "削除対象のルームが見つかりません"]
            )
        }
        try await roomRepo.deleteMyAccount(in: roomIdSan)
        // Firestore 削除後に Auth 削除が失敗した場合はエラーを伝播する。
        // セッションは Auth アカウントも含め正常に削除できた場合のみクリアする。
        if let user = Auth.auth().currentUser {
            try await user.delete()
        }
        session.isLoggedIn = false
        session.currentRoomId = ""
        session.cachedMember = nil
    }
}
