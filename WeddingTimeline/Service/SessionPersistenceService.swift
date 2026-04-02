//
//  SessionPersistenceService.swift
//  WeddingTimeline
//

import Foundation

/// SessionPersistenceService が扱う永続化用の中立データ型。
/// SessionStore に依存しないため、層をまたいで安全に使用できる。
struct CachedMemberDTO: Codable {
    let uid: String
    let roomId: String
    let username: String
    let userIcon: String?
}

/// UserDefaults を使ったセッション状態の永続化を担当するサービス
final class SessionPersistenceService {
    private let defaults: UserDefaults

    private enum Key {
        static let isLoggedIn = "isLoggedIn"
        static let lastRoomId = "lastRoomId"
        static let cachedMember = "cachedMember"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: - isLoggedIn

    var isLoggedIn: Bool {
        get { defaults.bool(forKey: Key.isLoggedIn) }
        set { defaults.set(newValue, forKey: Key.isLoggedIn) }
    }

    // MARK: - currentRoomId

    var currentRoomId: String {
        get { defaults.string(forKey: Key.lastRoomId) ?? "" }
        set { defaults.set(newValue, forKey: Key.lastRoomId) }
    }

    // MARK: - cachedMember

    func loadCachedMember() -> CachedMemberDTO? {
        guard let data = defaults.data(forKey: Key.cachedMember) else { return nil }
        do {
            return try JSONDecoder().decode(CachedMemberDTO.self, from: data)
        } catch {
            print("[SessionPersistenceService] loadCachedMember decode failed: \(error)")
            return nil
        }
    }

    func saveCachedMember(_ member: CachedMemberDTO?) {
        if let member {
            do {
                let data = try JSONEncoder().encode(member)
                defaults.set(data, forKey: Key.cachedMember)
            } catch {
                print("[SessionPersistenceService] saveCachedMember encode failed: \(error)")
            }
        } else {
            defaults.removeObject(forKey: Key.cachedMember)
        }
    }
}
