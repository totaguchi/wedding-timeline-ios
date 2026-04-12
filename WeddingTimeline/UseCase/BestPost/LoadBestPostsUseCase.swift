//
//  LoadBestPostsUseCase.swift
//  WeddingTimeline
//

import Foundation

/// いいね数上位の投稿を取得するユースケース
///
/// BestPostViewModel から PostRepository への直接依存を除去し、
/// 取得ロジックをユースケースに集約する。
final class LoadBestPostsUseCase {

    // MARK: - Input

    /// 取得条件
    struct Input {
        let roomId: String
        let limit: Int
        /// nil = すべてのカテゴリ
        let tag: PostTag?
    }

    // MARK: - Dependencies

    private let postRepo: PostRepository

    init(postRepo: PostRepository = PostRepository()) {
        self.postRepo = postRepo
    }

    // MARK: - Execute

    /// いいね数順に上位投稿を取得する
    ///
    /// - Parameter input: 取得条件
    /// - Returns: 上位投稿の配列（likeCount 降順）
    /// - Throws: Firestore 取得エラー
    func execute(input: Input) async throws -> [TimelinePost] {
        try await postRepo.fetchTopPosts(
            roomId: input.roomId,
            limit: input.limit,
            tag: input.tag
        )
    }
}
