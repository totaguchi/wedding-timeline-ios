//
//  BestPostViewModel.swift
//  WeddingTimeline
//
//  Created by 田口友暉 on 2025/11/05.
//

import Foundation

@Observable
final class BestPostViewModel {
    var top3: [TimelinePost] = []
    var isLoading = false
    var errorMessage: String? = nil

    // nil = すべて, .ceremony / .reception で絞り込み
    var selectedTag: PostTag? = nil

    private let postRepo = PostRepository()

    @MainActor
    func loadTop3(roomId: String) async {
        if isLoading { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let models = try await postRepo.fetchTopPosts(roomId: roomId, limit: 3, tag: selectedTag)
            self.top3 = models
            self.errorMessage = nil
        } catch {
            self.errorMessage = error.localizedDescription
            print("[BestPost] loadTop3 failed:", error)
        }
    }
}
