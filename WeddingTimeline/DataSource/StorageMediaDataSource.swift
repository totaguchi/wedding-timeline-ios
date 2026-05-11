//
//  StorageMediaDataSource.swift
//  WeddingTimeline
//
//  Firebase Storage SDK を直接操作する DataSource。
//  ファイルの PUT とダウンロード URL 取得をラップする。
//

import FirebaseStorage
import Foundation

/// Firebase Storage SDK 呼び出しを集約する DataSource。
///
/// Storage に関する SDK 依存はすべてここに閉じる。
final class StorageMediaDataSource {

    /// データを指定パスにアップロードし、ダウンロード URL を返す
    ///
    /// - Parameters:
    ///   - data: アップロードするバイナリデータ
    ///   - path: Storage 上のパス（例: `avatars/{roomId}/{uid}.jpg`）
    ///   - contentType: MIME タイプ（例: `image/jpeg`）
    /// - Returns: アップロード後のダウンロード URL
    /// - Throws: Storage SDK エラー
    nonisolated func upload(data: Data, path: String, contentType: String) async throws -> URL {
        let storage = Storage.storage()
        let ref = storage.reference(withPath: path)
        let meta = StorageMetadata()
        meta.contentType = contentType

        _ = try await ref.putDataAsync(data, metadata: meta)
        return try await downloadURL(from: ref)
    }

    nonisolated private func downloadURL(from ref: StorageReference) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            ref.downloadURL { result in
                switch result {
                case .success(let url):   continuation.resume(returning: url)
                case .failure(let error): continuation.resume(throwing: error)
                }
            }
        }
    }
}
