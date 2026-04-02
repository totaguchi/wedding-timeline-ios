//
//  JoinRoomUseCase.swift
//  WeddingTimeline
//
//  入室フローを担当する UseCase。
//  匿名サインイン → ルーム入室 → セッション更新を一連で行う。
//

import FirebaseAuth
import Foundation

@MainActor
final class JoinRoomUseCase {
    private let session: SessionStore
    private let roomRepo: RoomRepository

    init(session: SessionStore, roomRepo: RoomRepository = RoomRepository()) {
        self.session = session
        self.roomRepo = roomRepo
    }

    func execute(params: JoinParams) async throws {
        try await roomRepo.joinRoom(params)
        guard let uid = Auth.auth().currentUser?.uid else {
            throw NSError(
                domain: "JoinRoomUseCase", code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Auth UID が取得できませんでした"]
            )
        }
        session.isLoggedIn = true
        session.currentRoomId = params.roomId
        session.cachedMember = SessionStore.CachedMember(
            uid: uid,
            roomId: params.roomId,
            username: params.username,
            userIcon: params.selectedIcon
        )
        if let me = try? await roomRepo.fetchRoomUser(roomId: params.roomId, uid: uid) {
            session.cachedMember = SessionStore.CachedMember(
                uid: uid,
                roomId: params.roomId,
                username: me.username,
                userIcon: me.userIcon
            )
        }
    }
}
