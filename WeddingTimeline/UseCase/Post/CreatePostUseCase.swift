//
//  CreatePostUseCase.swift
//  WeddingTimeline
//

import Foundation

/// 新規投稿を作成するユースケース
///
/// メディアアップロード（MediaService）と Firestore 書き込み（PostRepository）を
/// 束ねて投稿作成フローを一本化する。ViewModel は Firebase SDK に直接依存しない。
final class CreatePostUseCase {

    // MARK: - Input

    /// 投稿作成に必要なパラメータ
    struct Input {
        let roomId: String
        let content: String
        let tag: PostTag
        /// PhotosPicker から取得済みのメディア種別
        let attachments: [SelectedAttachment.Kind]
        let authorId: String
        let authorName: String
        let userIcon: String
    }

    // MARK: - Dependencies

    private let mediaService: MediaService
    private let postRepo: PostRepository

    init(
        mediaService: MediaService = MediaService(),
        postRepo: PostRepository = PostRepository()
    ) {
        self.mediaService = mediaService
        self.postRepo = postRepo
    }

    // MARK: - Execute

    /// 投稿を作成する
    ///
    /// 1. Storage にメディアをアップロード
    /// 2. Firestore に投稿ドキュメントを書き込む
    ///
    /// - Parameter input: 投稿作成パラメータ
    /// - Throws: アップロードまたは Firestore 書き込みのエラー
    func execute(input: Input) async throws {
        // 1) メディアのアップロード（添付なしの場合は空配列）
        let mediaDTO = try await mediaService.uploadMedia(
            attachments: input.attachments,
            roomId: input.roomId
        )

        // 2) Firestore への投稿作成
        let postId = postRepo.generatePostId(roomId: input.roomId)
        try await postRepo.createPost(
            roomId: input.roomId,
            postId: postId,
            content: input.content,
            authorId: input.authorId,
            authorName: input.authorName,
            userIcon: input.userIcon,
            tag: input.tag.firestoreValue,
            media: mediaDTO
        )
    }
}
