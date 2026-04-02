//
//  SessionStore.swift
//  WeddingTimeline
//
//  アプリ全体のセッション状態を保持するストア。
//  状態保持と永続化のみを担当する。
//
//  以下の業務ロジックは今後 UseCase へ移行予定:
//  - bootstrapOnLaunch → BootstrapSessionUseCase
//  - signIn            → JoinRoomUseCase
//  - signOut           → SignOutUseCase
//  - deleteAccount     → DeleteAccountUseCase
//

import FirebaseAuth
import Observation

@MainActor
@Observable
final class SessionStore {

    // MARK: - CachedMember

    struct CachedMember: Equatable {
        let uid: String
        let roomId: String
        let username: String
        let userIcon: String?
    }

    // MARK: - State

    var isLoggedIn: Bool = false {
        didSet { persistence.isLoggedIn = isLoggedIn }
    }

    var currentRoomId: String = "" {
        didSet { persistence.currentRoomId = currentRoomId }
    }

    var cachedMember: CachedMember? = nil {
        didSet { persistence.saveCachedMember(cachedMember.map(CachedMemberDTO.init)) }
    }

    // MARK: - Dependencies

    @ObservationIgnored private let persistence: SessionPersistenceService
    @ObservationIgnored private let roomRepo: RoomRepository

    // MARK: - Init

    init(
        persistence: SessionPersistenceService = SessionPersistenceService(),
        roomRepo: RoomRepository = RoomRepository()
    ) {
        self.persistence = persistence
        self.roomRepo = roomRepo
        self.isLoggedIn = persistence.isLoggedIn
        self.currentRoomId = persistence.currentRoomId
        self.cachedMember = persistence.loadCachedMember().map(CachedMember.init)
    }

    // MARK: - Bootstrap（→ BootstrapSessionUseCase へ移行予定）

    func bootstrapOnLaunch() async {
        let uid: String
        do {
            uid = try await ensureSignedInUID()
        } catch {
            print("[SessionStore] ensureSignedInUID failed: \(error)")
            isLoggedIn = false
            return
        }

        if let cm = cachedMember, cm.uid != uid {
            print("[SessionStore] uid mismatch → キャッシュ破棄")
            cachedMember = nil
            isLoggedIn = false
            currentRoomId = ""
        }

        await validateCurrentMembership()
    }

    func validateCurrentMembership() async {
        guard !currentRoomId.isEmpty, let uid = Auth.auth().currentUser?.uid else {
            isLoggedIn = false
            return
        }
        do {
            if let me = try await roomRepo.fetchRoomUser(roomId: currentRoomId, uid: uid) {
                cachedMember = CachedMember(uid: uid, roomId: currentRoomId, username: me.username, userIcon: me.userIcon)
                isLoggedIn = true
            } else {
                print("[SessionStore] member doc not found → ログアウト状態へ")
                isLoggedIn = false
                cachedMember = nil
                currentRoomId = ""
            }
        } catch {
            print("[SessionStore] validateCurrentMembership failed: \(error)")
        }
    }

    // MARK: - SignIn（→ JoinRoomUseCase へ移行予定）

    func signIn(params: JoinParams) async throws {
        do {
            try await roomRepo.joinRoom(params)
            guard let uid = Auth.auth().currentUser?.uid else {
                throw NSError(domain: "SessionStore", code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Auth UID が取得できませんでした"])
            }
            isLoggedIn = true
            currentRoomId = params.roomId
            cachedMember = CachedMember(uid: uid, roomId: params.roomId, username: params.username, userIcon: params.selectedIcon)
            if let me = try? await roomRepo.fetchRoomUser(roomId: params.roomId, uid: uid) {
                cachedMember = CachedMember(uid: uid, roomId: params.roomId, username: me.username, userIcon: me.userIcon)
            }
        } catch {
            print("[SessionStore] signIn failed: \(error)")
            throw error
        }
    }

    // MARK: - SignOut（→ SignOutUseCase へ移行予定）

    func signOut() async {
        if !currentRoomId.isEmpty {
            do { try await roomRepo.leaveRoom(roomId: currentRoomId) } catch {
                print("[SessionStore] leaveRoom failed: \(error)")
            }
        }
        do { try Auth.auth().signOut() } catch {
            print("[SessionStore] Auth.signOut failed: \(error)")
        }
        isLoggedIn = false
        currentRoomId = ""
        cachedMember = nil
    }

    // MARK: - DeleteAccount（→ DeleteAccountUseCase へ移行予定）

    func deleteAccount() async throws {
        let roomIdSan = currentRoomId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !roomIdSan.isEmpty else {
            throw NSError(domain: "SessionStore", code: 400,
                userInfo: [NSLocalizedDescriptionKey: "削除対象のルームが見つかりません"])
        }
        try await roomRepo.deleteMyAccount(in: roomIdSan)
        if let user = Auth.auth().currentUser {
            do {
                try await user.delete()
            } catch {
                do { try Auth.auth().signOut() } catch {}
            }
        }
        isLoggedIn = false
        currentRoomId = ""
        cachedMember = nil
    }

    // MARK: - Private

    private func ensureSignedInUID() async throws -> String {
        if let uid = Auth.auth().currentUser?.uid { return uid }
        let result = try await Auth.auth().signInAnonymously()
        return result.user.uid
    }
}

// MARK: - CachedMemberDTO 変換

private extension CachedMemberDTO {
    init(_ member: SessionStore.CachedMember) {
        self.init(uid: member.uid, roomId: member.roomId, username: member.username, userIcon: member.userIcon)
    }
}

private extension SessionStore.CachedMember {
    init(_ dto: CachedMemberDTO) {
        self.init(uid: dto.uid, roomId: dto.roomId, username: dto.username, userIcon: dto.userIcon)
    }
}
