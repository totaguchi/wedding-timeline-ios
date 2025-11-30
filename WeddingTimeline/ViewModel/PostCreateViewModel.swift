//
//  PostCreateViewModel.swift
//  WeddingTimeline
//
//  Created by 田口友暉 on 2025/08/25.
//

import Foundation
import SwiftUI
import PhotosUI
import FirebaseAuth
import AVFoundation
import UniformTypeIdentifiers

@MainActor
@Observable
final class PostCreateViewModel {
    // MARK: - Properties
    
    /// 投稿先の Room ID
    let roomId: String
    
    /// 投稿本文
    var text: String = ""
    
    /// 選択中のカテゴリタグ
    var selectedTag: PostTag = .ceremony
    
    /// 添付メディア一覧（画像/動画）
    var attachments: [SelectedAttachment] = []
    
    /// PhotosPicker で選択されたアイテム
    var selectedItems: [PhotosPickerItem] = [] {
        didSet {
            if !selectedItems.isEmpty {
                Task { await loadPickedItems(selectedItems) }
            }
        }
    }
    
    /// メディア読み込み中フラグ
    var loadingPickerItem: Bool = false
    
    /// 投稿送信中フラグ
    var isSubmitting: Bool = false
    
    /// エラーメッセージ（表示用）
    var errorMessage: String?
    
    /// 投稿可能かどうか（バリデーション）
    var canSubmit: Bool {
        (!attachments.isEmpty || !text.isEmpty) && !isSubmitting && !loadingPickerItem
    }
    
    // MARK: - Dependencies
    
    private let mediaService: MediaService
    private let postRepo: PostRepository
    
    // MARK: - Private State
    
    /// プレースホルダー用の一時 ID
    private var placeholders: [SelectedAttachment] = []
    
    // MARK: - Initialization
    
    /// - Parameters:
    ///   - roomId: 投稿先の Room ID
    ///   - mediaService: メディアサービス（テスト時に Mock 注入可能）
    ///   - postRepo: 投稿リポジトリ（テスト時に Mock 注入可能）
    init(
        roomId: String,
        mediaService: MediaService = MediaService(),
        postRepo: PostRepository = PostRepository()
    ) {
        self.roomId = roomId
        self.mediaService = mediaService
        self.postRepo = postRepo
    }
    
    /// 初期化処理（必要に応じて Room 情報の検証など）
    func initialize() async {
        // 将来的に Room の権限チェックなどを実装
    }
    
    // MARK: - Media Selection
    
    /// PhotosPicker で選択されたアイテムを読み込む
    ///
    /// - Parameter items: PhotosPicker の選択結果
    /// - Note: 画像は `UIImage`、動画は一時ファイル URL として保持
    private func loadPickedItems(_ items: [PhotosPickerItem]) async {
        guard !items.isEmpty else { return }
        
        loadingPickerItem = true
        defer { loadingPickerItem = false }
        
        // プレースホルダーを追加（読み込み中表示）
        let newPlaceholders = items.map { _ in
            SelectedAttachment(kind: nil, thumbnail: nil, isLoading: true)
        }
        placeholders = newPlaceholders
        attachments.append(contentsOf: newPlaceholders)
        
        // 各アイテムを並行読み込み
        await withTaskGroup(of: (Int, SelectedAttachment?).self) { group in
            for (idx, item) in items.enumerated() {
                group.addTask { [weak self] in
                    await (idx, self?.loadSingleItem(item))
                }
            }
            
            // 読み込み完了順に配列を更新
            for await (idx, attachment) in group {
                guard idx < placeholders.count else { continue }
                let placeholderId = placeholders[idx].id
                
                if let attachment = attachment {
                    if let index = attachments.firstIndex(where: { $0.id == placeholderId }) {
                        attachments[index] = attachment
                    }
                } else {
                    // 読み込み失敗 → プレースホルダーを削除
                    attachments.removeAll { $0.id == placeholderId }
                }
            }
        }
        
        // 選択解除（次回の選択に備える）
        selectedItems = []
        placeholders = []
    }
    
    /// 単一アイテムの読み込み
    ///
    /// - Parameter item: PhotosPicker の1アイテム
    /// - Returns: 読み込み成功した `SelectedAttachment`、失敗時は `nil`
    private func loadSingleItem(_ item: PhotosPickerItem) async -> SelectedAttachment? {
        // メディア種別を判定
        let isVideo = item.supportedContentTypes.contains { type in
            type.conforms(to: .movie) || type.conforms(to: .video)
        }
        
        if isVideo {
            // 動画として読み込み
            guard let movie = try? await item.loadTransferable(type: PickedVideo.self) else {
                return nil
            }
            
            let url = movie.url
            let thumb = await generateVideoThumbnail(url: url)
            
            return SelectedAttachment(
                kind: .video(url),
                thumbnail: thumb,
                isLoading: false
            )
        } else {
            // 画像として読み込み
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else {
                return nil
            }
            
            return SelectedAttachment(
                kind: .image(image),
                thumbnail: nil,
                isLoading: false
            )
        }
    }
    
    /// 動画のサムネイルを生成
    ///
    /// - Parameter url: 動画ファイルの URL
    /// - Returns: サムネイル画像（失敗時は `nil`）
    private func generateVideoThumbnail(url: URL) async -> UIImage? {
        await Task.detached {
            let asset = AVURLAsset(url: url)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            
            let time = CMTime(seconds: 0, preferredTimescale: 600)
            guard let cgImage = try? generator.copyCGImage(at: time, actualTime: nil) else {
                return nil
            }
            return UIImage(cgImage: cgImage)
        }.value
    }
    
    // MARK: - Attachment Management
    
    /// 添付メディアを削除
    ///
    /// - Parameter attachment: 削除対象の添付ファイル
    func removeAttachment(_ attachment: SelectedAttachment) {
        withAnimation {
            attachments.removeAll { $0.id == attachment.id }
        }
    }
    
    // MARK: - Submit
    
    /// 投稿を送信
    ///
    /// - Throws: Storage/Firestore のエラー
    /// - Returns: 成功時は `true`（View で `dismiss()` を呼ぶため）
    @discardableResult
    func submit(authorName: String, userIcon: String) async throws -> Bool {
        guard canSubmit else { return false }
        
        guard let uid = Auth.auth().currentUser?.uid else {
            throw AppError.unauthenticated
        }
        
        isSubmitting = true
        defer { isSubmitting = false }
        
        do {
            // 1) Storage にメディアをアップロード（kind を compactMap で抽出）
            let kinds = attachments.compactMap { $0.kind }
            let mediaDTO = try await mediaService.uploadMedia(
                attachments: kinds,
                roomId: roomId
            )
            
            // 2) Firestore に投稿を作成
            let postId = postRepo.generatePostId(roomId: roomId)
            try await postRepo.createPost(
                roomId: roomId,
                postId: postId,
                content: text,
                authorId: uid,
                authorName: authorName,
                userIcon: userIcon,
                tag: selectedTag.firestoreValue,
                media: mediaDTO
            )
            
            return true
        } catch {
            // エラーを ViewModel で保持（View で Alert 表示）
            errorMessage = error.localizedDescription
            throw error
        }
    }
}

// MARK: - PickedVideo (Transferable)

/// PhotosPicker から動画を読み込むための `Transferable` 型
///
/// PhotosPicker が動画を選択した際、一時ファイルとして URL を返す。
/// この型を `loadTransferable(type:)` で指定することで動画を取得できる。
///
/// ## 使用例
/// ```swift
/// if let movie = try? await item.loadTransferable(type: PickedVideo.self) {
///     let videoURL = movie.url
///     // AVPlayer や AVAssetImageGenerator で処理
/// }
/// ```
struct PickedVideo: Transferable {
    /// 動画ファイルの一時 URL
    let url: URL
    
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            // PhotosPicker が渡す一時ファイルをコピー
            let copy = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("mov")
            try FileManager.default.copyItem(at: received.file, to: copy)
            return Self(url: copy)
        }
    }
}
