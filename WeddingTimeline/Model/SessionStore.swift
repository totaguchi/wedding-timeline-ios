//
//  SessionStore.swift
//  WeddingTimeline
//
//  アプリ全体のセッション状態を保持するストア。
//  状態の保持と永続化のみを担当する。
//
//  業務ロジックは各 UseCase で実装する:
//  - bootstrapOnLaunch → BootstrapSessionUseCase
//  - signIn            → JoinRoomUseCase
//  - signOut           → SignOutUseCase
//  - deleteAccount     → DeleteAccountUseCase
//

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

    // MARK: - Init

    init(persistence: SessionPersistenceService = SessionPersistenceService()) {
        self.persistence = persistence
        self.isLoggedIn = persistence.isLoggedIn
        self.currentRoomId = persistence.currentRoomId
        self.cachedMember = persistence.loadCachedMember().map(CachedMember.init)
    }
}

// MARK: - Cache Update Helpers

extension SessionStore {
    /// ユーザー名だけを更新してキャッシュに反映する（ChangeUsernameUseCase から呼ぶ）
    func updateCachedUsername(_ newUsername: String) {
        guard let current = cachedMember else { return }
        cachedMember = CachedMember(
            uid: current.uid,
            roomId: current.roomId,
            username: newUsername,
            userIcon: current.userIcon
        )
    }

    /// RoomMember からキャッシュ全体を更新する（UpdateAvatarUseCase から呼ぶ）
    func updateCachedMember(_ member: RoomMember) {
        cachedMember = CachedMember(
            uid: member.id,
            roomId: member.roomId,
            username: member.username,
            userIcon: member.usericon
        )
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
