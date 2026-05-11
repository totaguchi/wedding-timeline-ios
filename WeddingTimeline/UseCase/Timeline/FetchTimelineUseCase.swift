//
//  FetchTimelineUseCase.swift
//  WeddingTimeline
//
//  タイムライン投稿の一括取得とページングを担当する UseCase。
//  PostPageCursor カーソルを内部管理し、ViewModel から Firestore 型を隠蔽する。
//

import Foundation

@MainActor
final class FetchTimelineUseCase {
    private let postRepo: PostRepository
    /// ページングカーソル（Firestore DocumentSnapshot を PostPageCursor でラップして保持）
    private var cursor: PostPageCursor? = nil

    init(postRepo: PostRepository) {
        self.postRepo = postRepo
    }

    func execute(roomId: String, reset: Bool = false) async throws -> [TimelinePost] {
        if reset { cursor = nil }
        let (posts, nextCursor) = try await postRepo.fetchPosts(
            roomId: roomId, limit: 50, startAfter: cursor
        )
        cursor = nextCursor
        return posts
    }
}
