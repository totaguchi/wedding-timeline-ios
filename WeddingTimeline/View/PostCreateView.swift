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

// 挙式/披露宴タグ選択用
private enum ComposeTag: String, CaseIterable, Identifiable {
    case ceremony   // 挙式
    case reception  // 披露宴
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .ceremony:  return "挙式"
        case .reception: return "披露宴"
        }
    }
    var icon: String {
        switch self {
        case .ceremony:  return "heart"
        case .reception: return "fork.knife"
        }
    }
    /// Firestore に保存する際の生文字列（必要になったら submit 側へ渡す）
    var firestoreRaw: String {
        switch self {
        case .ceremony:  return "ceremony"
        case .reception: return "reception"
        }
    }
}

struct PostCreateView: View {
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var vm = PostComposerViewModel()
    @FocusState private var editorFocused: Bool

    @State private var content: String = ""
    @State private var pickedItems: [PhotosPickerItem] = []
    @State private var attachments: [SelectedAttachment] = []
    // タグ選択（必須）：挙式 or 披露宴
    @State private var selectedTag: ComposeTag? = nil

    // MARK: - 制限ロジック
    private var currentMode: MediaMode? {
        guard !attachments.isEmpty else { return nil }
        return attachments.first!.mediaKind == .image ? .images : .video
    }
    private var imageCount: Int { attachments.filter { if case .image = $0.kind { return true } else { return false } }.count }
    private var videoCount: Int { attachments.filter { if case .video = $0.kind { return true } else { return false } }.count }

    /// 追加可能な残り数（Xの制限に準拠）
    private var remainingCount: Int {
        switch currentMode {
        case .none:
            return 4 // 初回は最大4まで（画像想定）。動画を選んだら1つで終了
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
                            // TODO: ViewModel 側の submit に `tagRaw: selectedTag!.firestoreRaw` を渡す
                            try await vm.submit(
                                content: content.trimmingCharacters(in: .whitespacesAndNewlines),
                                currentRoomId: cachedMember.roomId,
                                userId: cachedMember.uid,
                                userName: cachedMember.username,
                                userIcon: cachedMember.userIcon ?? "",
                                attachments: attachments,
                                tagRaw: selectedTag?.firestoreRaw
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
        if !attachments.isEmpty {
            AttachmentGrid(attachments: $attachments)
                .animation(.default, value: attachments)
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
            switch currentMode {
            case .none:
                Text("画像は最大4枚、または動画は1本のみ")
            case .some(.images):
                Text("画像 \(imageCount)/4")
            case .some(.video):
                Text("動画 \(videoCount)/1")
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
            Task { await loadPickedItems(new) }
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
                                Rectangle().opacity(0.08)
                            }
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 38, weight: .bold))
                                .shadow(radius: 3)
                        }
                    }
                    .frame(height: 100)
                    .clipped()
                    .cornerRadius(10)
                    .overlay(alignment: .topTrailing) {
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

    private struct TagChip: View {
        let tag: ComposeTag
        let isSelected: Bool
        let onTap: () -> Void
        var body: some View {
            Button(action: onTap) {
                HStack(spacing: 8) {
                    Image(systemName: tag.icon)
                    Text(tag.displayName)
                }
                .font(.system(size: 15, weight: .semibold))
                .padding(.vertical, 10)
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity)
                .background(isSelected ? Color.pink.opacity(0.15) : Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(isSelected ? Color.clear : Color.secondary.opacity(0.25), lineWidth: 1)
                )
                .foregroundStyle(isSelected ? Color.pink : Color.primary)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Picker 読み込み & 制限適用（混在禁止 & X制限）
    func loadPickedItems(_ items: [PhotosPickerItem]) async {
        guard !items.isEmpty else { return }

        // 一時結果を構築（順番保持）
        var newAttachments: [SelectedAttachment] = []

        for item in items {
            // 画像優先で読み込み
            if let data = try? await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                newAttachments.append(SelectedAttachment(kind: .image(image), thumbnail: nil))
                continue
            }
            // 動画として読み込み（Transferable ラッパーで安定して URL を取得）
            if let movie = try? await item.loadTransferable(type: PickedVideo.self) {
                let url = movie.url
                let thumb = await generateVideoThumbnail(url: url)
                newAttachments.append(SelectedAttachment(kind: .video(url), thumbnail: thumb))
                continue
            }
        }

        guard !newAttachments.isEmpty else { return }

        // 既存のモードを決定
        let mode = currentMode ?? {
            // 初選択で動画が含まれていたら動画モード、それ以外は画像モード
            if newAttachments.contains(where: { if case .video = $0.kind { return true } else { return false } }) {
                return .video
            } else {
                return .images
            }
        }()

        // 混在禁止：画像モードなら画像のみ、動画モードなら動画のみ残す
        let filteredNew: [SelectedAttachment] = newAttachments.filter { att in
            switch (mode, att.kind) {
            case (.images, .image), (.video, .video): return true
            default: return false
            }
        }

        if filteredNew.count != newAttachments.count {
            limitMessage = "画像と動画は同時に添付できません。どちらか一方のみ選択してください。"
            showLimitAlert = true
        }

        // 既存と合算して上限に収める
        switch mode {
        case .images:
            let merged = (attachments + filteredNew).filter {
                if case .image = $0.kind { return true } else { return false }
            }
            let clamped = Array(merged.prefix(4)) // 上限4
            if clamped.count < merged.count {
                limitMessage = "画像は最大4枚までです。"
                showLimitAlert = true
            }
            withAnimation { attachments = clamped }

        case .video:
            // 動画は常に1本のみ。既にあれば置き換えるか、追加を拒否（ここでは置き換え）
            let newVideo = filteredNew.first(where: { if case .video = $0.kind { return true } else { return false } })
            if let newVideo {
                if videoCount == 0 {
                    withAnimation { attachments = [newVideo] }
                } else {
                    // 置き換え
                    withAnimation { attachments = [newVideo] }
                    limitMessage = "動画は1本のみです。選択した動画に置き換えました。"
                    showLimitAlert = true
                }
            }
        }
    }

    func generateVideoThumbnail(url: URL) async -> UIImage? {
        let asset = AVURLAsset(url: url)

        // 事前に依存プロパティをロード（-17913: AVErrorFailedDependenciesKey = assetProperty_AssetType 対策）
        if #available(iOS 18.0, *) {
            _ = try? await asset.load(.isReadable)
            _ = try? await asset.load(.isPlayable)
            _ = try? await asset.load(.tracks)
            _ = try? await asset.load(.duration)
        }

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1024, height: 1024)
        // まずは最近接キーフレーム許容
        generator.requestedTimeToleranceBefore = .positiveInfinity
        generator.requestedTimeToleranceAfter  = .positiveInfinity

        // 取得時刻：まず 0s（先頭のキーフレーム期待）、だめなら中間 or 1s
        let duration: CMTime = await {
            if #available(iOS 18.0, *) { return (try? await asset.load(.duration)) ?? .zero }
            else { return asset.duration }
        }()
        let dSec = duration.isValid && duration.seconds.isFinite ? duration.seconds : 0
        let zeroTime = CMTime(seconds: 0, preferredTimescale: 600)
        let midTime  = CMTime(seconds: min(1.0, max(0.0, dSec * 0.5)), preferredTimescale: 600)

        // iOS 18+: 非同期 → 失敗なら時刻/トレランスを変えて再試行
        if #available(iOS 18.0, *) {
            // 0秒で試す
            do {
                let cg: CGImage = try await withCheckedThrowingContinuation { cont in
                    generator.generateCGImageAsynchronously(for: zeroTime) { cgImage, _, error in
                        if let cgImage { cont.resume(returning: cgImage) }
                        else { cont.resume(throwing: error ?? NSError(domain: "ThumbGen", code: -1, userInfo: [NSLocalizedDescriptionKey: "Async zeroTime failed"])) }
                    }
                }
                return UIImage(cgImage: cg)
            } catch {
                print("[Thumb] async zeroTime error: \(error)")
            }

            // 中間時刻（~1s）で再試行
            do {
                let cg: CGImage = try await withCheckedThrowingContinuation { cont in
                    generator.generateCGImageAsynchronously(for: midTime) { cgImage, _, error in
                        if let cgImage { cont.resume(returning: cgImage) }
                        else { cont.resume(throwing: error ?? NSError(domain: "ThumbGen", code: -2, userInfo: [NSLocalizedDescriptionKey: "Async midTime failed"])) }
                    }
                }
                return UIImage(cgImage: cg)
            } catch {
                print("[Thumb] async midTime error: \(error)")
            }

            // トレランスを厳密化して再試行（ゼロ許容）
            generator.requestedTimeToleranceBefore = .zero
            generator.requestedTimeToleranceAfter  = .zero

            do {
                let cg: CGImage = try await withCheckedThrowingContinuation { cont in
                    generator.generateCGImageAsynchronously(for: zeroTime) { cgImage, _, error in
                        if let cgImage { cont.resume(returning: cgImage) }
                        else { cont.resume(throwing: error ?? NSError(domain: "ThumbGen", code: -3, userInfo: [NSLocalizedDescriptionKey: "Async zeroTime strict failed"])) }
                    }
                }
                return UIImage(cgImage: cg)
            } catch {
                print("[Thumb] async zeroTime(strict) error: \(error)")
            }

            do {
                let cg: CGImage = try await withCheckedThrowingContinuation { cont in
                    generator.generateCGImageAsynchronously(for: midTime) { cgImage, _, error in
                        if let cgImage { cont.resume(returning: cgImage) }
                        else { cont.resume(throwing: error ?? NSError(domain: "ThumbGen", code: -4, userInfo: [NSLocalizedDescriptionKey: "Async midTime strict failed"])) }
                    }
                }
                return UIImage(cgImage: cg)
            } catch {
                print("[Thumb] async midTime(strict) error: \(error)")
            }
        }

        // 最後に同期API（iOS 17以下/最終手段）
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
    }

    // (transcodeForThumbnail removed: no longer needed)
    
    // Remove legacy video thumbnail helper (now handled solely by AVAssetImageGenerator)
    // private func firstDecodableFrameThumbnail(url: URL, maxEdge: CGFloat) async -> UIImage? { ... }
}
