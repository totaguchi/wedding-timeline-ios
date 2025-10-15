//
//  PostRepository.swift
//  WeddingTimeline
//
//  Created by 田口友暉 on 2025/09/22.
//

import Foundation
import FirebaseFirestore

final class PostRepository {
    private let db = Firestore.firestore()

    private class ListenerBox {
        private let removeImpl: () -> Void

        init(_ removeImpl: @escaping () -> Void) {
            self.removeImpl = removeImpl
        }

        @MainActor func remove() { removeImpl() }
    }

    // 単発取得（ページング用にカーソル返す）
    func fetchPosts(roomId: String, limit: Int = 20, startAfter: DocumentSnapshot? = nil)
    async throws -> (posts: [TimeLinePost], lastSnapshot: DocumentSnapshot?) {
        let roomIdSan = roomId.trimmingCharacters(in: .whitespacesAndNewlines)
        var q: Query = db.collection("rooms").document(roomIdSan)
            .collection("posts")
            .order(by: "createdAt", descending: true)
            .order(by: FieldPath.documentID(), descending: true)
            .limit(to: limit)

        if let cursor = startAfter {
            q = q.start(afterDocument: cursor)
        }

        let snap = try await q.getDocuments(source: .server)
        let posts: [TimeLinePost] = snap.documents.compactMap { doc in
            do {
                var dto = try doc.data(as: TimeLinePostDTO.self)
                dto.id = doc.documentID
                return TimeLinePost(dto: dto)
            } catch {
                print("[PostRepository] decode failed id=\(doc.documentID): \(error)")
                return nil
            }
        }
        let last: DocumentSnapshot? = snap.documents.last as DocumentSnapshot?
        return (posts, last)
    }

    // リアルタイム購読（最新 N 件）
    func listenLatest(roomId: String, limit: Int = 20)
    -> AsyncThrowingStream<[TimeLinePost], Error> {
        let roomIdSan = roomId.trimmingCharacters(in: .whitespacesAndNewlines)
        let q = db.collection("rooms").document(roomIdSan)
            .collection("posts")
            .order(by: "createdAt", descending: true)
            .limit(to: limit)

        return AsyncThrowingStream { cont in
            let listener = q.addSnapshotListener { snap, err in
                if let err { cont.yield(with: .failure(err)); return }
                guard let snap else { return }
                let posts: [TimeLinePost] = snap.documents.compactMap { doc in
                    do {
                        var dto = try doc.data(as: TimeLinePostDTO.self)
                        if dto.id == nil { dto.id = doc.documentID }
                        return TimeLinePost(dto: dto)
                    } catch {
                        print("[PostRepository] decode failed id=\(doc.documentID): \(error)")
                        return nil
                    }
                }
                cont.yield(posts)
            }
            let box = ListenerBox(listener.remove)
            cont.onTermination = { _ in
                Task { @MainActor in
                    box.remove()
                }
            }
        }
    }
}
