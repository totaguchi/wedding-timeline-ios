//
//  PostCreateViewModel.swift
//  WeddingTimeline
//
//  Created by 田口友暉 on 2025/08/25.
//

import SwiftUI
import FirebaseAuth
import Observation

@MainActor
@Observable
class PostCreateViewModel {
    private let postRepository = PostRepository()
    private let mediaService = MediaService()

    var isUploading = false
    var progress: Double = 0 // 0.0 ~ 1.0

    /// 添付の一括アップロード（並列）→ MediaDTO配列を返す
    func uploadAttachments(
        roomId: String,
        postId: String,
        userId: String,
        attachments: [SelectedAttachment]
    ) async throws -> [MediaDTO] {
        enum UploadItem: Sendable {
            case image(data: Data, width: Int, height: Int)
            case video(url: URL)
        }

        var jobs: [(index: Int, item: UploadItem)] = []
        for (idx, att) in attachments.enumerated() {
            switch att.kind {
            case .image(let uiImage):
                guard let data = uiImage.jpegData(compressionQuality: 0.85) else {
                    throw NSError(domain: "ImageConvert", code: -1)
                }
                jobs.append((idx, .image(data: data, width: Int(uiImage.size.width), height: Int(uiImage.size.height))))
            case .video(let url):
                jobs.append((idx, .video(url: url)))
            }
        }

        let total = attachments.count
        var completed = 0
        progress = 0

        return try await withThrowingTaskGroup(of: MediaDTO.self) { group in
            for (index, item) in jobs {
                group.addTask {
                    switch item {
                    case .image(let data, let width, let height):
                        return try await self.mediaService.uploadImage(
                            index: index,
                            data: data,
                            width: width,
                            height: height,
                            roomId: roomId,
                            postId: postId,
                            userId: userId
                        )
                    case .video(let fileURL):
                        return try await self.mediaService.uploadVideo(
                            index: index,
                            fileURL: fileURL,
                            roomId: roomId,
                            postId: postId,
                            userId: userId
                        )
                    }
                }
            }

            var results: [MediaDTO] = []
            for try await dto in group {
                results.append(dto)
                completed += 1
                await MainActor.run {
                    self.progress = Double(completed) / Double(total)
                }
            }
            return results
        }
    }

    /// 投稿本体：Storage → Firestore
    func submit(
        content: String,
        currentRoomId: String,
        userId: String,
        userName: String,
        userIcon: String,
        attachments: [SelectedAttachment],
        tagRaw: String?
    ) async throws {
        isUploading = true
        progress = 0
        defer { isUploading = false }

        // ID発行
        let roomIdSan = currentRoomId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !roomIdSan.isEmpty else {
            throw NSError(domain: "Post", code: 400, userInfo: [NSLocalizedDescriptionKey: "ルーム情報が取得できませんでした"])
        }

        let postId = postRepository.generatePostId(roomId: roomIdSan)

        // 添付アップロード
        let mediaDTOs = try await uploadAttachments(
            roomId: roomIdSan,
            postId: postId,
            userId: userId,
            attachments: attachments
        )

        // Firestore保存
        try await postRepository.createPost(
            roomId: roomIdSan,
            postId: postId,
            content: content,
            authorId: userId,
            authorName: userName,
            userIcon: userIcon,
            tag: tagRaw ?? "",
            media: mediaDTOs
        )
    }
}
