//
//  SignOutUseCase.swift
//  WeddingTimeline
//
//  ログアウトフローを担当する UseCase。
//  退室処理 → Firebase Auth サインアウト → セッション状態クリアを行う。
//

import Foundation

@MainActor
final class SignOutUseCase {
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

    func execute() async {
        if !session.currentRoomId.isEmpty {
            do {
                try await roomRepo.leaveRoom(roomId: session.currentRoomId)
            } catch {
                print("[SignOutUseCase] leaveRoom failed: \(error)")
            }
        }
        do {
            try authDS.signOut()
        } catch {
            print("[SignOutUseCase] Auth.signOut failed: \(error)")
        }
        session.isLoggedIn    = false
        session.currentRoomId = ""
        session.cachedMember  = nil
    }
}
