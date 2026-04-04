//
//  MuteUserUseCase.swift
//  WeddingTimeline
//
//  ユーザーミュートの設定/解除を担当する UseCase。
//

import Foundation

final class MuteUserUseCase {
    private let postRepo: PostRepository

    init(postRepo: PostRepository) {
        self.postRepo = postRepo
    }

    func execute(roomId: String, targetUid: String, ownerUid: String, mute: Bool) async throws {
        try await postRepo.setMute(roomId: roomId, targetUid: targetUid, by: ownerUid, mute: mute)
    }
}
