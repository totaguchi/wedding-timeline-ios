//
//  BestPostViewModel.swift
//  WeddingTimeline
//
//  Created by 田口友暉 on 2025/11/05.
//

import Foundation

@MainActor
@Observable
final class BestPostViewModel {
    var top3: [TimelinePost] = []
    var isLoading = false
    var errorMessage: String? = nil

    // nil = すべて, .ceremony / .reception で絞り込み
    var selectedTag: PostTag? = nil

    private let loadBestPostsUseCase: LoadBestPostsUseCase

    init(loadBestPostsUseCase: LoadBestPostsUseCase = LoadBestPostsUseCase()) {
        self.loadBestPostsUseCase = loadBestPostsUseCase
    }

    func loadTop3(roomId: String) async {
        if isLoading { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let input = LoadBestPostsUseCase.Input(roomId: roomId, limit: 3, tag: selectedTag)
            let models = try await loadBestPostsUseCase.execute(input: input)
            self.top3 = models
            self.errorMessage = nil
        } catch {
            self.errorMessage = error.localizedDescription
            print("[BestPost] loadTop3 failed:", error)
        }
    }
}
