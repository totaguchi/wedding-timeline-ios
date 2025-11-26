//
//  PostCreateView.swift
//  WeddingTimeline
//
//  Created by 田口友暉 on 2025/08/24.
//

import SwiftUI
import PhotosUI
import AVFoundation
import UniformTypeIdentifiers
import CoreTransferable

/// Xの制限：画像は最大4枚 or 動画は1本（混在不可）
private enum MediaMode { case images, video }

private enum PostError: LocalizedError {
    case notLoggedIn
    var errorDescription: String? {
        switch self {
        case .notLoggedIn:
            return "未ログインです。ログインしてから投稿してください。"
        }
    }
}

/// PhotosPickerItem 用の動画ファイルラッパー（安全に一時URLを受け取る）
struct PickedVideo: Transferable {
    let url: URL
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { file in
            SentTransferredFile(file.url)
        } importing: { received in
            // 写真ライブラリから受け取ったファイルの一時URL
            let src = received.file
            // 拡張子を維持（なければ mov）しつつ、アプリ側の tmp にコピーして寿命を担保
            let ext = src.pathExtension.isEmpty ? "mov" : src.pathExtension
            let dest = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(ext)
            do {
                // 既に存在する場合は一旦削除
                try? FileManager.default.removeItem(at: dest)
                try FileManager.default.copyItem(at: src, to: dest)
                return PickedVideo(url: dest)
            } catch {
                // コピーに失敗したら元のURLをそのまま返す（最後の手段）
                return PickedVideo(url: src)
            }
        }
    }
}

struct PostCreateView: View {
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var vm = PostCreateViewModel()
    @FocusState private var editorFocused: Bool

    @State private var content: String = ""
    @State private var pickedItems: [PhotosPickerItem] = []
    @State private var attachments: [SelectedAttachment] = []
    // タグ選択（必須）：挙式 or 披露宴
    @State private var selectedTag: PostTag? = nil
    @State private var loadingPickerItem = false

    // MARK: - 制限ロジック
    /// 現在のメディアモード（プレースホルダーを除外して判定）
    private var currentMode: MediaMode? {
        let loadedOnly = attachments.filter { !$0.isLoading }
        guard !loadedOnly.isEmpty else { return nil }
        
        let hasVideo = loadedOnly.contains { att in
            if case .video = att.kind { return true }
            else { return false }
        }
        
        return hasVideo ? .video : .images
    }
    /// 読み込み完了した画像の枚数
    private var imageCount: Int {
        attachments.filter { att in
            !att.isLoading && {
                if case .image = att.kind { return true }
                else { return false }
            }()
        }.count
    }

    /// 読み込み完了した動画の本数
    private var videoCount: Int {
        attachments.filter { att in
            !att.isLoading && {
                if case .video = att.kind { return true }
                else { return false }
            }()
        }.count
    }

    /// 追加可能な残り数（読み込み完了分のみカウント）
    private var remainingCount: Int {
        switch currentMode {
        case .none:
            return 4 // 初回は最大4まで（画像想定）
        case .some(.images):
            return max(0, 4 - imageCount)
        case .some(.video):
            return max(0, 1 - videoCount)
        }
    }

    /// ピッカーのフィルター：混在禁止（現在のモードに合わせる）
    private var pickerFilter: PHPickerFilter {
        switch currentMode {
        case .none:
            return .any(of: [.images, .videos])
        case .some(.images):
            return .images
        case .some(.video):
            return .videos
        }
    }

    @State private var showLimitAlert = false
    @State private var limitMessage = ""

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Button {
                    dismiss()
                } label: {
                    Text("キャンセル")
                }
                .disabled(vm.isUploading)
                Spacer()
                Button {
                    Task {
                        do {
                            guard let cachedMember = session.cachedMember else {
                                throw PostError.notLoggedIn
                            }
                            try await vm.submit(
                                content: content.trimmingCharacters(in: .whitespacesAndNewlines),
                                currentRoomId: cachedMember.roomId,
                                userId: cachedMember.uid,
                                userName: cachedMember.username,
                                userIcon: cachedMember.userIcon ?? "",
                                attachments: attachments,
                                tagRaw: selectedTag?.firestoreValue
                            )
                            dismiss()
                        } catch {
                            limitMessage = "投稿に失敗しました：\(error.localizedDescription)"
                            showLimitAlert = true
                            debugPrint(error)
                        }
                    }
                } label: {
                    Text("ポスト")
                }
                .disabled(
                    vm.isUploading ||
                    content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                    selectedTag == nil
                )
            }
            editorSection
            tagSection   // ← 追加：スクショ風のチップUIでタグ選択
            attachmentsGridSection
            limitHintSection
            pickerSection
            Spacer()
            uploadProgressSection
        }
        .padding()
        .alert("注意", isPresented: $showLimitAlert, actions: {
            Button("OK", role: .cancel) {}
        }, message: {
            Text(limitMessage)
        })
    }
    
    // MARK: - Sections (split to avoid “body is too complex”)
    
    @ViewBuilder private var editorSection: some View {
        TextEditor(text: $content)
            .frame(minHeight: 120)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(.secondary.opacity(0.25)))
            .focused($editorFocused)
    }
    
    @ViewBuilder private var attachmentsGridSection: some View {
        if !attachments.isEmpty && !loadingPickerItem {
            AttachmentGrid(attachments: $attachments)
                .animation(.default, value: attachments)
        } else if loadingPickerItem {
            HStack {
                ShimmerPlaceholder(cornerRadius: 10)
                    .frame(width: 100, height: 100, alignment: .leading)
                Spacer()
            }
        }
    }

    @ViewBuilder private var tagSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("タグ")
                .font(.headline)
                .foregroundStyle(Color.pink)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                TagChip(tag: .ceremony, isSelected: selectedTag == .ceremony) {
                    selectedTag = .ceremony
                }
                TagChip(tag: .reception, isSelected: selectedTag == .reception) {
                    selectedTag = .reception
                }
            }
        }
        .padding(.top, 4)
    }
    
    @ViewBuilder private var limitHintSection: some View {
        HStack(spacing: 8) {
            // プレースホルダーが存在する場合は「読み込み中」を表示
            if attachments.contains(where: { $0.isLoading }) {
                HStack(spacing: 4) {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("メディアを読み込み中…")
                }
            } else {
                switch currentMode {
                case .none:
                    Text("画像は最大4枚、または動画は1本のみ")
                case .some(.images):
                    Text("画像 \(imageCount)/4")
                case .some(.video):
                    Text("動画 \(videoCount)/1")
                }
            }
            Spacer()
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
    }
    
    @ViewBuilder private var pickerSection: some View {
        PhotosPicker(
            selection: $pickedItems,
            maxSelectionCount: max(1, remainingCount),
            matching: pickerFilter
        ) {
            Label("メディアを追加", systemImage: "photo.on.rectangle.angled")
        }
        .disabled(remainingCount == 0 || vm.isUploading)
        .onChange(of: pickedItems) { old, new in
            Task {
                await loadPickedItems(new)
            }
        }
    }
    
    @ViewBuilder private var uploadProgressSection: some View {
        if vm.isUploading {
            VStack(spacing: 8) {
                ProgressView(value: vm.progress)
                Text("アップロード中… \(Int(vm.progress * 100))%")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
        }
    }
    // MARK: - Components
    
    private struct AttachmentGrid: View {
        @Binding var attachments: [SelectedAttachment]

        var body: some View {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                ForEach(attachments) { att in
                    ZStack {
                        if att.isLoading {
                            // 読み込み中：シマーエフェクト + スピナー
                            ShimmerPlaceholder(cornerRadius: 10)
                            ProgressView()
                                .tint(.white)
                        } else {
                            switch att.kind {
                            case .image(let img):
                                Image(uiImage: img)
                                    .resizable()
                                    .scaledToFill()
                            case .video:
                                if let thumb = att.thumbnail {
                                    Image(uiImage: thumb)
                                        .resizable()
                                        .scaledToFill()
                                } else {
                                    ShimmerPlaceholder(cornerRadius: 10)
                                }
                                Image(systemName: "play.circle.fill")
                                    .font(.system(size: 38, weight: .bold))
                                    .shadow(radius: 3)
                            }
                        }
                    }
                    .frame(height: 100)
                    .clipped()
                    .cornerRadius(10)
                    .overlay(alignment: .topTrailing) {
                        if !att.isLoading {
                            Button {
                                withAnimation {
                                    attachments.removeAll { $0.id == att.id }
                                }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.ultraThinMaterial)
                                    .font(.title2)
                            }
                            .padding(6)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Picker 読み込み & 制限適用（混在禁止 & X制限）
    func loadPickedItems(_ items: [PhotosPickerItem]) async {
        guard !items.isEmpty else { return }
        loadingPickerItem = true
        defer { loadingPickerItem = false }

        // 1) 先にプレースホルダーを追加（即座に画面反映）
        let placeholders = items.map { _ in
            SelectedAttachment(
                kind: .image(UIImage(systemName: "photo")!), // ダミー画像
                thumbnail: nil,
                isLoading: true
            )
        }
        withAnimation {
            attachments.append(contentsOf: placeholders)
        }

        // 2) バックグラウンドで実際のメディアを読み込み、置き換え
        var loadedAttachments: [SelectedAttachment] = []
        
        for (idx, item) in items.enumerated() {
            let placeholderId = placeholders[idx].id

            // ★ 事前に supportedContentTypes でメディア種別を判定
            let isVideo = item.supportedContentTypes.contains { type in
                type.conforms(to: .movie) || type.conforms(to: .video)
            }

            if isVideo {
                // --- 動画として読み込み ---
                if let movie = try? await item.loadTransferable(type: PickedVideo.self) {
                    let url = movie.url
                    // サムネイル生成（並行実行可能）
                    let thumb = await generateVideoThumbnail(url: url)
                    let newAttachment = SelectedAttachment(
                        kind: .video(url),
                        thumbnail: thumb,
                        isLoading: false
                    )
                    loadedAttachments.append(newAttachment)
                    
                    if let index = attachments.firstIndex(where: { $0.id == placeholderId }) {
                        withAnimation {
                            attachments[index] = newAttachment
                        }
                    }
                    continue
                }
            } else {
                // --- 画像として読み込み ---
                if let data = try? await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    let newAttachment = SelectedAttachment(
                        kind: .image(image),
                        thumbnail: nil,
                        isLoading: false
                    )
                    loadedAttachments.append(newAttachment)
                    
                    if let index = attachments.firstIndex(where: { $0.id == placeholderId }) {
                        withAnimation {
                            attachments[index] = newAttachment
                        }
                    }
                    continue
                }
            }

            // 読み込み失敗時はプレースホルダーを削除
            withAnimation {
                attachments.removeAll { $0.id == placeholderId }
            }
        }

        // 3) 混在チェック & 上限適用（読み込み完了後）
        // ★ プレースホルダーを除外して判定
        let loadedOnly = attachments.filter { !$0.isLoading }
        
        let detectedMode: MediaMode? = {
            guard !loadedOnly.isEmpty else { return nil }
            return loadedOnly.contains(where: { if case .video = $0.kind { return true } else { return false } })
                ? .video
                : .images
        }()
        
        // 既存の添付（プレースホルダー除外）と新規読み込み分を合わせて判定
        let existingMode = currentMode
        let finalMode = detectedMode ?? existingMode ?? .images

        // 混在チェック
        let hasMixedTypes = loadedAttachments.contains { att in
            switch (finalMode, att.kind) {
            case (.images, .video), (.video, .image):
                return true
            default:
                return false
            }
        }

        if hasMixedTypes {
            limitMessage = "画像と動画は同時に添付できません。どちらか一方のみ選択してください。"
            showLimitAlert = true
            // 混在している場合は全て削除
            withAnimation {
                attachments.removeAll { att in
                    loadedAttachments.contains(where: { $0.id == att.id })
                }
            }
            return
        }

        // 上限に収める
        switch finalMode {
        case .images:
            let allImages = loadedOnly.filter { if case .image = $0.kind { return true } else { return false } }
            let clamped = Array(allImages.prefix(4))
            if clamped.count < allImages.count {
                limitMessage = "画像は最大4枚までです。"
                showLimitAlert = true
            }
            withAnimation {
                attachments = clamped
            }

        case .video:
            // ★ 既存の動画数を正確にカウント（プレースホルダー除外）
            let existingVideoCount = loadedOnly.filter {
                if case .video = $0.kind { return true } else { return false }
            }.count - loadedAttachments.filter {
                if case .video = $0.kind { return true } else { return false }
            }.count
            
            let newVideo = loadedAttachments.first(where: { if case .video = $0.kind { return true } else { return false } })
            
            if let newVideo {
                if existingVideoCount == 0 {
                    // 初めての動画選択
                    withAnimation {
                        attachments = [newVideo]
                    }
                } else {
                    // 既に動画がある場合は置き換え
                    withAnimation {
                        attachments = [newVideo]
                    }
                    limitMessage = "動画は1本のみです。選択した動画に置き換えました。"
                    showLimitAlert = true
                }
            }
        }
    }

    func generateVideoThumbnail(url: URL) async -> UIImage? {
        let asset = AVURLAsset(url: url)

        if #available(iOS 18.0, *) {
            _ = try? await asset.load(.isReadable)
            _ = try? await asset.load(.isPlayable)
            _ = try? await asset.load(.tracks)
            _ = try? await asset.load(.duration)
        }

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1024, height: 1024)
        generator.requestedTimeToleranceBefore = .positiveInfinity
        generator.requestedTimeToleranceAfter = .positiveInfinity

        let duration: CMTime = await {
            if #available(iOS 18.0, *) { return (try? await asset.load(.duration)) ?? .zero }
            else { return asset.duration }
        }()
        let dSec = duration.isValid && duration.seconds.isFinite ? duration.seconds : 0
        let zeroTime = CMTime(seconds: 0, preferredTimescale: 600)
        let midTime = CMTime(seconds: min(1.0, max(0.0, dSec * 0.5)), preferredTimescale: 600)

        // iOS 18+: 非同期 API 使用
        if #available(iOS 18.0, *) {
            do {
                let cg: CGImage = try await withCheckedThrowingContinuation { cont in
                    generator.generateCGImagesAsynchronously(forTimes: [NSValue(time: zeroTime)]) { _, image, _, result, error in
                        if let error = error {
                            cont.resume(throwing: error)
                        } else if let image = image {
                            cont.resume(returning: image)
                        } else {
                            cont.resume(throwing: NSError(domain: "Thumbnail", code: -1))
                        }
                    }
                }
                return UIImage(cgImage: cg)
            } catch {
                print("[Thumb] async zeroTime error: \(error)")
            }

            do {
                let cg: CGImage = try await withCheckedThrowingContinuation { cont in
                    generator.generateCGImagesAsynchronously(forTimes: [NSValue(time: midTime)]) { _, image, _, result, error in
                        if let error = error {
                            cont.resume(throwing: error)
                        } else if let image = image {
                            cont.resume(returning: image)
                        } else {
                            cont.resume(throwing: NSError(domain: "Thumbnail", code: -1))
                        }
                    }
                }
                return UIImage(cgImage: cg)
            } catch {
                print("[Thumb] async midTime error: \(error)")
            }
        } else {
            // iOS 17以下: 同期 API（バックグラウンドで実行）
            return await Task.detached {
                do {
                    let cg = try generator.copyCGImage(at: zeroTime, actualTime: nil)
                    return UIImage(cgImage: cg)
                } catch {
                    print("[Thumb] sync zeroTime error: \(error)")
                    do {
                        let cg = try generator.copyCGImage(at: midTime, actualTime: nil)
                        return UIImage(cgImage: cg)
                    } catch {
                        print("[Thumb] sync midTime error: \(error)")
                        return nil
                    }
                }
            }.value
        }

        return nil
    }
}
