//
//  DeletePostUseCase.swift
//  WeddingTimeline
//
//  投稿削除を担当する UseCase。
//

import Foundation

final class DeletePostUseCase {
    private let postRepo: PostRepository

    init(postRepo: PostRepository) {
        self.postRepo = postRepo
    }

    func execute(roomId: String, postId: String, uid: String) async throws {
        try await postRepo.deletePost(roomId: roomId, postId: postId, authorUid: uid)
    }
}
