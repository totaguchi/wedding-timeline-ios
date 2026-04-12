//
//  SettingViewModel.swift
//  WeddingTimeline
//

import Foundation

/// 設定画面の状態管理と UseCase の呼び出し口
///
/// SettingView から UseCase の直接呼び出しを除去し、
/// ViewModel にロジックを集約する。
@MainActor
@Observable
final class SettingViewModel {

    // MARK: - State

    /// アカウント削除処理中フラグ
    var isDeleting: Bool = false

    /// アカウント削除のエラーメッセージ
    var deleteError: String?

    // MARK: - Dependencies

    private var signOutUseCase: SignOutUseCase?
    private var deleteAccountUseCase: DeleteAccountUseCase?

    // MARK: - Initialization

    init() {}

    /// SessionStore を注入する（View の .task から呼ぶ）
    func configure(session: SessionStore) {
        signOutUseCase = SignOutUseCase(session: session)
        deleteAccountUseCase = DeleteAccountUseCase(session: session)
    }

    // MARK: - Actions

    /// ログアウトを実行する
    func signOut() async {
        guard let useCase = signOutUseCase else {
            // configure(session:) が呼ばれる前に操作された場合（通常は発生しない）
            assertionFailure("SettingViewModel.configure(session:) が未実行です")
            return
        }
        await useCase.execute()
    }

    /// アカウント削除を実行する
    ///
    /// 削除完了後は SessionStore の状態がリセットされ、ログイン画面に遷移する。
    func deleteAccount() async {
        guard let useCase = deleteAccountUseCase else {
            // configure(session:) が呼ばれる前に操作された場合（通常は発生しない）
            assertionFailure("SettingViewModel.configure(session:) が未実行です")
            deleteError = "セッション情報が取得できませんでした。画面を閉じて再度お試しください。"
            return
        }
        isDeleting = true
        defer { isDeleting = false }
        do {
            try await useCase.execute()
        } catch {
            deleteError = error.localizedDescription
        }
    }
}
