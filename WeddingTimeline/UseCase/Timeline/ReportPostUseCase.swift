//
//  ReportPostUseCase.swift
//  WeddingTimeline
//
//  投稿通報を担当する UseCase。
//

import Foundation

final class ReportPostUseCase {
    private let postRepo: PostRepository

    init(postRepo: PostRepository) {
        self.postRepo = postRepo
    }

    func execute(roomId: String, postId: String, reason: String, reporterUid: String) async throws {
        try await postRepo.reportPost(
            roomId: roomId, postId: postId, reason: reason, reporterUid: reporterUid
        )
    }
}
