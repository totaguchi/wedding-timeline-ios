//
//  ToggleLikeUseCase.swift
//  WeddingTimeline
//
//  いいねのトグルを担当する UseCase。
//  PostRepository に委譲し、ViewModel から Repository 型を隠蔽する。
//

import Foundation

final class ToggleLikeUseCase {
    private let postRepo: PostRepository

    init(postRepo: PostRepository) {
        self.postRepo = postRepo
    }

    func execute(roomId: String, postId: String, uid: String, isLiked: Bool) async throws -> Int {
        try await postRepo.toggleLike(roomId: roomId, postId: postId, uid: uid, like: isLiked)
    }
}
