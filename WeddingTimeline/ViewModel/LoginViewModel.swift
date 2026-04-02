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

    @MainActor
    func join(session: SessionStore) async {
        errorMessage = nil
        isLogin = true; defer { isLogin = false }

        do {
            guard let selectedIcon else {
                throw JoinError.iconNotSelected
            }

            let roomIdSan = roomId.trimmingCharacters(in: .whitespacesAndNewlines)
            let roomKeySan = roomKey.trimmingCharacters(in: .whitespacesAndNewlines)
            let usernameSan = username.trimmingCharacters(in: .whitespacesAndNewlines)

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

            let params = JoinParams(
                roomId: roomIdSan,
                roomKey: roomKeySan,
                username: usernameSan,
                selectedIcon: selectedIcon
            )

            let useCase = JoinRoomUseCase(session: session)
            try await useCase.execute(params: params)
        } catch {
            let ns = error as NSError
            print("[LoginViewModel] join failed: domain=\(ns.domain) code=\(ns.code) userInfo=\(ns.userInfo)")

            if let le = error as? LocalizedError, let desc = le.errorDescription {
                errorMessage = desc
            } else {
                errorMessage = ns.localizedDescription
            }
        }
    }
}
