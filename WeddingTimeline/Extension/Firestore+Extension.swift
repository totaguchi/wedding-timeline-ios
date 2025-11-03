//
//  Firestore+Extension.swift
//  WeddingTimeline
//
//  Created by 田口友暉 on 2025/10/28.
//

import FirebaseFirestore

extension Firestore {
    nonisolated func runTransactionAsync<T: Sendable>(
        _ updateBlock: @escaping @Sendable (Transaction) throws -> T
    ) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            self.runTransaction({ (transaction, errorPointer) -> Any? in
                do {
                    return try updateBlock(transaction)
                } catch {
                    errorPointer?.pointee = error as NSError
                    return nil
                }
            }, completion: { (result, error) in
                // キュー移動を削除し、completionハンドラ内で直接resume
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let typedResult = result as? T {
                    continuation.resume(returning: typedResult)
                } else {
                    let castError = NSError(
                        domain: "FirestoreTransactionError",
                        code: -1,
                        userInfo: [
                            NSLocalizedDescriptionKey: "Failed to cast transaction result"
                        ]
                    )
                    continuation.resume(throwing: castError)
                }
            })
        }
    }
}
