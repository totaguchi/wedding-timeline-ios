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
        isLogin = true; defer { isLogin = false }
        do {
            guard let selectedIcon else { throw JoinError.iconNotSelected }
            let params = JoinParams(roomId: roomId, roomKey: roomKey, username: username, selectedIcon: selectedIcon)
            try await session.signIn(params: params)
        } catch {
            let ns = error as NSError
            // 詳細ログ（Xcode コンソールに出力）
            print("[LoginViewModel] join failed: domain=\(ns.domain) code=\(ns.code) userInfo=\(ns.userInfo)")
            // LocalizedError を優先し、なければ NSError の説明
            if let le = error as? LocalizedError, let desc = le.errorDescription {
                errorMessage = desc
            } else {
                errorMessage = ns.localizedDescription
            }
        }
    }
}
