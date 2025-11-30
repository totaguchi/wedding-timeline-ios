//
//  BestPostViewModel.swift
//  WeddingTimeline
//
//  Created by 田口友暉 on 2025/11/05.
//

import Foundation
import FirebaseFirestore

@Observable
final class BestPostViewModel {
    var top3: [TimelinePost] = []
    var isLoading = false
    var errorMessage: String? = nil

    // nil = すべて, .ceremony / .reception で絞り込み
    var selectedTag: PostTag? = nil

    private let db = Firestore.firestore()

    @MainActor
    func loadTop3(roomId: String) async {
        if isLoading { return }
        isLoading = true
        defer { isLoading = false }
        do {
            var q: Query = db.collection("rooms").document(roomId)
                .collection("posts")

            if let tag = selectedTag {
                q = q.whereField("tag", isEqualTo: tag.rawValue)
            }
            q = q.order(by: "likeCount", descending: true).limit(to: 3)

            let snap = try await q.getDocuments(source: .server)
            let models: [TimelinePost] = try snap.documents.compactMap { doc in
                var dto = try doc.data(as: TimelinePostDTO.self)
                dto.id = doc.documentID
                return TimelinePost(dto: dto)
            }
            self.top3 = models
            self.errorMessage = nil
        } catch {
            self.errorMessage = error.localizedDescription
            print("[BestPost] loadTop3 failed:", error)
        }
    }
}
