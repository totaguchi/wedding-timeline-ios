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
        await signOutUseCase?.execute()
    }

    /// アカウント削除を実行する
    ///
    /// 削除完了後は SessionStore の状態がリセットされ、ログイン画面に遷移する。
    func deleteAccount() async {
        isDeleting = true
        defer { isDeleting = false }
        do {
            try await deleteAccountUseCase?.execute()
        } catch {
            deleteError = error.localizedDescription
        }
    }
}
