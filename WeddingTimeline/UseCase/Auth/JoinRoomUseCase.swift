//
//  JoinRoomUseCase.swift
//  WeddingTimeline
//
//  入室フローを担当する UseCase。
//  匿名サインイン → ルーム入室 → セッション更新を一連で行う。
//

import Foundation

@MainActor
final class JoinRoomUseCase {
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

    func execute(params: JoinParams) async throws {
        try await roomRepo.joinRoom(params)
        guard let uid = authDS.currentUID() else {
            throw NSError(
                domain: "JoinRoomUseCase", code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Auth UID が取得できませんでした"]
            )
        }
        session.isLoggedIn    = true
        session.currentRoomId = params.roomId
        session.cachedMember  = SessionStore.CachedMember(
            uid:      uid,
            roomId:   params.roomId,
            username: params.username,
            userIcon: params.selectedIcon
        )
        if let me = try? await roomRepo.fetchRoomUser(roomId: params.roomId, uid: uid) {
            session.cachedMember = SessionStore.CachedMember(
                uid:      uid,
                roomId:   params.roomId,
                username: me.username,
                userIcon: me.userIcon
            )
        }
    }
}
