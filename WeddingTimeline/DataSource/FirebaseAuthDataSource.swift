//
//  FirebaseAuthDataSource.swift
//  WeddingTimeline
//
//  Firebase Auth SDK を直接操作する DataSource。
//  UseCase / Repository は Auth SDK を直接参照せず、このクラスを経由する。
//

import FirebaseAuth
import Foundation

/// Firebase Auth SDK 呼び出しを集約する DataSource。
///
/// Auth に関する SDK 依存はすべてここに閉じる。
final class FirebaseAuthDataSource {

    /// 現在ログイン中のユーザー UID（未ログインは nil）
    func currentUID() -> String? {
        Auth.auth().currentUser?.uid
    }

    /// 匿名サインインが未実施なら実施し UID を返す
    ///
    /// - Returns: 現在または新規発行された匿名 UID
    /// - Throws: Auth SDK エラー
    func ensureSignedIn() async throws -> String {
        if let uid = Auth.auth().currentUser?.uid { return uid }
        let result = try await Auth.auth().signInAnonymously()
        return result.user.uid
    }

    /// サインアウト（同期）
    ///
    /// - Throws: Auth SDK エラー
    func signOut() throws {
        try Auth.auth().signOut()
    }

    /// 現在ログイン中のユーザーアカウントを削除
    ///
    /// - Throws: 未サインイン時は `AppError.unauthenticated`、Auth SDK エラー
    func deleteCurrentUser() async throws {
        guard let user = Auth.auth().currentUser else {
            throw AppError.unauthenticated
        }
        try await user.delete()
    }
}
