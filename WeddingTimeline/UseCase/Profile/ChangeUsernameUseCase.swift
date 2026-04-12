//
//  ChangeUsernameUseCase.swift
//  WeddingTimeline
//

import Foundation

/// ユーザー名を変更するユースケース
///
/// UserRepository のトランザクション処理（重複チェック＋更新）を
/// ViewModel から隠蔽し、SessionStore のキャッシュも同時に更新する。
final class ChangeUsernameUseCase {

    // MARK: - Input

    struct Input {
        let roomId: String
        let newUsername: String
        let uid: String
    }

    // MARK: - Dependencies

    private let userRepo: UserRepository
    private let session: SessionStore

    init(
        userRepo: UserRepository = UserRepository(),
        session: SessionStore
    ) {
        self.userRepo = userRepo
        self.session = session
    }

    // MARK: - Execute

    /// ユーザー名を変更する
    ///
    /// 1. Firestore トランザクションで重複確認＋更新
    /// 2. SessionStore のキャッシュを最新ユーザー名に同期
    ///
    /// - Parameter input: 変更パラメータ
    /// - Throws: 重複エラーまたは Firestore 書き込みエラー
    @MainActor
    func execute(input: Input) async throws {
        let trimmed = input.newUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw AppError.invalidInput("ユーザー名を入力してください")
        }

        try await userRepo.changeUsername(
            roomId: input.roomId,
            newUsername: trimmed,
            uid: input.uid
        )

        // SessionStore のキャッシュを更新してUIに即反映
        session.updateCachedUsername(trimmed)
    }
}
