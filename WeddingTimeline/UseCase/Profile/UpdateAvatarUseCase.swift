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
    @MainActor
    func execute(input: Input) async throws {
        try await userRepo.changeAvatar(
            roomId: input.roomId,
            uid: input.uid,
            imageData: input.imageData,
            contentType: input.contentType
        )

        // 更新後の最新データを取得してキャッシュに反映
        if let updated = try await userRepo.fetchRoomUser(roomId: input.roomId, uid: input.uid) {
            session.updateCachedMember(updated)
        }
    }
}
