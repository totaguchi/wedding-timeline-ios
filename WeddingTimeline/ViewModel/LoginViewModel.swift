//
//  LoginViewModel.swift
//  WeddingTimeline
//
//  Created by 田口友暉 on 2025/09/01.
//

import Foundation

@Observable
final class LoginViewModel {
    var roomId: String = ""
    var roomKey: String = ""
    var username: String = ""
    var selectedIcon: String? = nil
    var isLogin = false
    var errorMessage: String?

    let icons = [
        "oomimigitsune", "lesser_panda", "bear",
        "todo", "musasabi", "rakko"
    ]

    private let roomRepo = RoomRepository()

    @MainActor
    func join(session: Session) async {
        errorMessage = nil
        isLogin = true; defer { isLogin = false }

        do {
            // アイコン未選択は即時にわかりやすく返す
            guard let selectedIcon else {
                throw JoinError.iconNotSelected
            }

            // 余分な空白・改行を除去してから判定/送信
            let roomIdSan = roomId.trimmingCharacters(in: .whitespacesAndNewlines)
            let roomKeySan = roomKey.trimmingCharacters(in: .whitespacesAndNewlines)
            let usernameSan = username.trimmingCharacters(in: .whitespacesAndNewlines)

            // 入力チェック（Repository 側でも検証するが、ここで先にユーザーへ即時フィードバック）
            guard !roomIdSan.isEmpty else {
                throw NSError(domain: "JoinRoom", code: 1001, userInfo: [
                    NSLocalizedDescriptionKey: "ルームIDを入力してください。"
                ])
            }
            guard !roomKeySan.isEmpty else {
                throw NSError(domain: "JoinRoom", code: 1002, userInfo: [
                    NSLocalizedDescriptionKey: "入室キーを入力してください。"
                ])
            }
            guard !usernameSan.isEmpty else {
                throw NSError(domain: "JoinRoom", code: 1003, userInfo: [
                    NSLocalizedDescriptionKey: "ユーザー名を入力してください。"
                ])
            }

            // サニタイズ済み値で JoinParams を構築
            let params = JoinParams(
                roomId: roomIdSan,
                roomKey: roomKeySan,
                username: usernameSan,
                selectedIcon: selectedIcon
            )

            try await session.signIn(params: params)
        } catch {
            let ns = error as NSError
            // 詳細ログ（Xcode コンソール）
            print("[LoginViewModel] join failed: domain=\(ns.domain) code=\(ns.code) userInfo=\(ns.userInfo)")

            // Repository 側の mapJoinError で整形された localizedDescription を優先採用
            if let le = error as? LocalizedError, let desc = le.errorDescription {
                errorMessage = desc
            } else {
                errorMessage = ns.localizedDescription
            }
        }
    }
}
