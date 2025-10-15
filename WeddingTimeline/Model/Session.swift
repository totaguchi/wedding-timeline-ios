//
//  Session.swift
//  WeddingTimeline
//
//  Created by 田口友暉 on 2025/08/12.
//

import FirebaseFirestore
import FirebaseAuth
import Observation

@MainActor
@Observable
final class Session {
    @ObservationIgnored private let defaults = UserDefaults.standard
    @ObservationIgnored private static let isLoggedInKey = "isLoggedIn"
    @ObservationIgnored private static let lastRoomIdKey = "lastRoomId"
    @ObservationIgnored private let roomRepo: RoomRepository = RoomRepository()

    var isLoggedIn: Bool = false {
        didSet { defaults.set(isLoggedIn, forKey: Self.isLoggedInKey) }
    }

    var currentRoomId: String = "" {
        didSet { defaults.set(currentRoomId, forKey: Self.lastRoomIdKey) }
    }

    struct CachedMember: Codable, Equatable {
        let uid: String
        let roomId: String
        let username: String
        let userIcon: String?
    }

    var cachedMember: CachedMember? = nil {
        didSet { saveCachedMember(cachedMember) }
    }

    // MARK: - Bootstrap / Checks
    /// アプリ起動時に呼び出して、Auth とキャッシュ、会員状態を整合させる
    func bootstrapOnLaunch() async {
        // 1) Auth を確保（匿名OK）
        let uid: String
        do {
            uid = try await ensureSignedInUID()
        } catch {
            let ns = error as NSError
            print("[Session] ensureSignedInUID failed: domain=\(ns.domain) code=\(ns.code) userInfo=\(ns.userInfo)")
            // Auth が確保できない場合はローカルを一旦無効化
            isLoggedIn = false
            return
        }

        // 2) キャッシュと Auth の整合性を確認（uid 不一致なら破棄）
        if let cm = cachedMember, cm.uid != uid {
            print("[Session] cachedMember.uid (\(cm.uid)) != auth.uid (\(uid)) → キャッシュ破棄")
            cachedMember = nil
            isLoggedIn = false
            currentRoomId = ""
        }

        // 3) 直近のルーム参加を検証し、最新の会員情報でキャッシュを更新
        await validateCurrentMembership()
    }

    /// Firestore の members に自分の doc が存在するかを検証し、キャッシュ更新/破棄を行う
    func validateCurrentMembership() async {
        guard !currentRoomId.isEmpty, let uid = Auth.auth().currentUser?.uid else {
            // 参加中ルームがない or 未ログイン
            isLoggedIn = false
            return
        }

        do {
            if let me = try await roomRepo.fetchRoomUser(roomId: currentRoomId, uid: uid) {
                // 会員ならキャッシュを最新化
                let updated = CachedMember(uid: uid, roomId: currentRoomId, username: me.username, userIcon: me.userIcon)
                cachedMember = updated
                isLoggedIn = true
            } else {
                // 会員でない（退室済みなど）
                print("[Session] validate: member doc not found → ログアウト状態へ")
                isLoggedIn = false
                cachedMember = nil
                currentRoomId = ""
            }
        } catch {
            let ns = error as NSError
            print("[Session] validateCurrentMembership failed: domain=\(ns.domain) code=\(ns.code) userInfo=\(ns.userInfo)")
            // 通信失敗などは致命ではないので、キャッシュはそのまま温存
        }
    }

    init() {
        isLoggedIn = defaults.bool(forKey: Self.isLoggedInKey)
        currentRoomId = defaults.string(forKey: Self.lastRoomIdKey) ?? ""
        cachedMember = loadCachedMember()
    }

    func signIn(params: JoinParams) async throws {
        do {
            try await roomRepo.joinRoom(params)

            // 状態を保持
            isLoggedIn = true
            currentRoomId = params.roomId

            // uid を取得（join 成功時には確実にある想定）
            let uid = Auth.auth().currentUser?.uid ?? ""

            // まずは入力値ベースで即キャッシュ（表示を速く）
            let initial = CachedMember(uid: uid, roomId: params.roomId, username: params.username, userIcon: params.selectedIcon)
            cachedMember = initial

            // 可能であれば最新の会員情報を単発取得してキャッシュを上書き
            do {
                if let me = try await roomRepo.fetchRoomUser(roomId: params.roomId, uid: uid) {
                    // RoomMember から必要項目だけ取り出して再保存（プロパティ名はプロジェクトの定義に合わせてください）
                    let updated = CachedMember(uid: uid, roomId: params.roomId, username: me.username, userIcon: me.userIcon)
                    cachedMember = updated
                }
            } catch {
                // 取得に失敗しても致命ではないのでログのみ
                let ns = error as NSError
                print("[Session] fetchRoomUser after join failed: domain=\(ns.domain) code=\(ns.code) userInfo=\(ns.userInfo)")
            }

        } catch {
            let ns = error as NSError
            print("[Session] signIn failed: domain=\(ns.domain) code=\(ns.code) userInfo=\(ns.userInfo)")
            throw error
        }
    }

    func signOut() async {
        // 先に Firestore 上の members から退室（roomId が分かる場合のみ）
        if !currentRoomId.isEmpty {
            do { try await roomRepo.leaveRoom(roomId: currentRoomId) } catch {
                let ns = error as NSError
                print("[Session] leaveRoom on signOut failed: domain=\(ns.domain) code=\(ns.code) userInfo=\(ns.userInfo)")
            }
        }

        // Firebase Auth からのサインアウト（失敗しても続行）
        do { try Auth.auth().signOut() } catch {
            let ns = error as NSError
            print("[Session] Auth.signOut failed: domain=\(ns.domain) code=\(ns.code) userInfo=\(ns.userInfo)")
        }

        // ローカル状態をクリア
        isLoggedIn = false
        currentRoomId = ""
        cachedMember = nil
    }

    // MARK: - Auth ensure (anonymous OK)
    private func ensureSignedInUID() async throws -> String {
        if let uid = Auth.auth().currentUser?.uid { return uid }
        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<String, Error>) in
            Auth.auth().signInAnonymously { result, error in
                if let error = error { cont.resume(throwing: error) }
                else if let uid = result?.user.uid { cont.resume(returning: uid) }
                else {
                    cont.resume(throwing: NSError(domain: "FirebaseAuth", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to sign in anonymously"]))
                }
            }
        }
    }

    // MARK: - Persistence (UserDefaults)
    private func saveCachedMember(_ member: CachedMember?) {
        let key = "cachedMember"
        if let member {
            do {
                let data = try JSONEncoder().encode(member)
                defaults.set(data, forKey: key)
            } catch {
                let ns = error as NSError
                print("[Session] saveCachedMember encode failed: domain=\(ns.domain) code=\(ns.code) userInfo=\(ns.userInfo)")
            }
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    private func loadCachedMember() -> CachedMember? {
        let key = "cachedMember"
        guard let data = defaults.data(forKey: key) else { return nil }
        do {
            return try JSONDecoder().decode(CachedMember.self, from: data)
        } catch {
            let ns = error as NSError
            print("[Session] loadCachedMember decode failed: domain=\(ns.domain) code=\(ns.code) userInfo=\(ns.userInfo)")
            return nil
        }
    }
    // 例）Root View の .task などで：
    // .task { await session.bootstrapOnLaunch() }
}
