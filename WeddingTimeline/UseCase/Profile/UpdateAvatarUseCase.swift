//
//  UpdateAvatarUseCase.swift
//  WeddingTimeline
//

import Foundation

/// アバター画像を更新するユースケース
///
/// Storage アップロード→ Firestore URL 保存→ SessionStore キャッシュ更新を
/// ViewModel から隠蔽する。
final class UpdateAvatarUseCase {

    // MARK: - Input

    struct Input {
        let roomId: String
        let uid: String
        /// JPEG 圧縮済みの画像データ
        let imageData: Data
        let contentType: String
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

    /// アバター画像を更新する
    ///
    /// 1. Storage に画像をアップロード
    /// 2. Firestore にダウンロード URL を保存
    /// 3. SessionStore のキャッシュを最新 URL に同期
    ///
    /// - Parameter input: 更新パラメータ
    /// - Throws: Storage アップロードまたは Firestore 書き込みエラー
    ///
    /// - Note: Firestore の保存キーは `avatarURL` だが RoomMemberDTO は `usericon` を読むため、
    ///         再フェッチでは更新後の URL が取得できない。
    ///         `changeAvatar` が返す URL を直接キャッシュに反映する。
    func execute(input: Input) async throws {
        // ネットワーク処理は MainActor に縛らない
        let downloadURL = try await userRepo.changeAvatar(
            roomId: input.roomId,
            uid: input.uid,
            imageData: input.imageData,
            contentType: input.contentType
        )
        // SessionStore は @MainActor のため更新だけ MainActor で実行
        await MainActor.run { session.updateCachedUserIcon(downloadURL.absoluteString) }
    }
}
