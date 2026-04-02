//
//  BootstrapSessionUseCase.swift
//  WeddingTimeline
//
//  アプリ起動時のセッション復元を担当する UseCase。
//  匿名サインイン確保 → UID整合性確認 → 会員資格の検証を行う。
//

import FirebaseAuth
import Foundation

@MainActor
final class BootstrapSessionUseCase {
    private let session: SessionStore
    private let roomRepo: RoomRepository

    init(session: SessionStore, roomRepo: RoomRepository = RoomRepository()) {
        self.session = session
        self.roomRepo = roomRepo
    }

    func execute() async {
        let uid: String
        do {
            uid = try await ensureSignedInUID()
        } catch {
            print("[BootstrapSessionUseCase] ensureSignedInUID failed: \(error)")
            session.isLoggedIn = false
            return
        }

        if let cm = session.cachedMember, cm.uid != uid {
            print("[BootstrapSessionUseCase] uid mismatch → キャッシュ破棄")
            session.cachedMember = nil
            session.isLoggedIn = false
            session.currentRoomId = ""
        }

        await validateCurrentMembership(uid: uid)
    }

    // MARK: - Private

    private func ensureSignedInUID() async throws -> String {
        if let uid = Auth.auth().currentUser?.uid { return uid }
        let result = try await Auth.auth().signInAnonymously()
        return result.user.uid
    }

    private func validateCurrentMembership(uid: String) async {
        guard !session.currentRoomId.isEmpty else {
            session.isLoggedIn = false
            return
        }
        do {
            if let me = try await roomRepo.fetchRoomUser(roomId: session.currentRoomId, uid: uid) {
                session.cachedMember = SessionStore.CachedMember(
                    uid: uid,
                    roomId: session.currentRoomId,
                    username: me.username,
                    userIcon: me.userIcon
                )
                session.isLoggedIn = true
            } else {
                print("[BootstrapSessionUseCase] member doc not found → ログアウト状態へ")
                session.isLoggedIn = false
                session.cachedMember = nil
                session.currentRoomId = ""
            }
        } catch {
            print("[BootstrapSessionUseCase] validateCurrentMembership failed: \(error)")
        }
    }
}
