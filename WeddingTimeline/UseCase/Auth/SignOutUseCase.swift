//
//  SignOutUseCase.swift
//  WeddingTimeline
//
//  ログアウトフローを担当する UseCase。
//  退室処理 → Firebase Auth サインアウト → セッション状態クリアを行う。
//

import FirebaseAuth
import Foundation

@MainActor
final class SignOutUseCase {
    private let session: SessionStore
    private let roomRepo: RoomRepository

    init(session: SessionStore, roomRepo: RoomRepository = RoomRepository()) {
        self.session = session
        self.roomRepo = roomRepo
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
            try Auth.auth().signOut()
        } catch {
            print("[SignOutUseCase] Auth.signOut failed: \(error)")
        }
        session.isLoggedIn = false
        session.currentRoomId = ""
        session.cachedMember = nil
    }
}
