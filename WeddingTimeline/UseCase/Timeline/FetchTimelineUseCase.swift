//
//  FetchTimelineUseCase.swift
//  WeddingTimeline
//
//  タイムライン投稿の一括取得とページングを担当する UseCase。
//  DocumentSnapshot カーソルを内部管理し、ViewModel から Firestore 型を隠蔽する。
//

import FirebaseFirestore
import Foundation

@MainActor
final class FetchTimelineUseCase {
    private let postRepo: PostRepository
    private var lastSnapshot: DocumentSnapshot? = nil

    init(postRepo: PostRepository) {
        self.postRepo = postRepo
    }

    func execute(roomId: String, reset: Bool = false) async throws -> [TimelinePost] {
        if reset { lastSnapshot = nil }
        let (posts, cursor) = try await postRepo.fetchPosts(
            roomId: roomId, limit: 50, startAfter: lastSnapshot
        )
        lastSnapshot = cursor
        return posts
    }
}
