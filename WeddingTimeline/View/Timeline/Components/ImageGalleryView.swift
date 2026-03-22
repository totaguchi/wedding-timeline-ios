//
//  ImageGalleryView.swift
//  WeddingTimeline
//
//  Created by 田口友暉 on 2025/10/08.
//

import SwiftUI
import Photos
import UIKit

// MARK: - Fullscreen Image Gallery (X-like)
struct ImageGalleryView: View {
    let urls: [URL]
    let startIndex: Int
    @State private var index: Int = 0
    @State private var isDownloading: Bool = false
    @State private var showSaveConfirmation: Bool = false
    @State private var isPreparingShare: Bool = false
    @State private var sharePayload: SharePayload?
    @Environment(\.dismiss) private var dismiss
    
    private var displayableURLs: [URL] {
        urls.filter { url in
            if url.isFileURL { return true }
            guard let scheme = url.scheme?.lowercased() else { return false }
            return scheme == "http" || scheme == "https"
        }
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            if displayableURLs.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "photo")
                        .font(.system(size: 36))
                        .foregroundStyle(TLColor.icoAction)
                    Text("表示できる画像がありません")
                        .font(.callout)
                        .foregroundStyle(TLColor.icoWhite)
                }
                .padding()
            } else {
                TabView(selection: $index) {
                    ForEach(Array(displayableURLs.enumerated()), id: \.offset) { idx, url in
                        ZoomableAsyncImage(url: url)
                            .tag(idx)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .automatic))
            }

            // ヘッダー（閉じる + ダウンロードボタン）
            VStack {
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(TLColor.icoWhite)
                            .padding(8)
                    }
                    .accessibilityLabel("閉じる")
                    
                    Spacer()
                    
                    Button {
                        Task {
                            guard !displayableURLs.isEmpty else { return }
                            let i = min(max(0, index), max(0, displayableURLs.count - 1))
                            await shareCurrentImage(url: displayableURLs[i])
                        }
                    } label: {
                        if isPreparingShare {
                            ProgressView()
                                .tint(TLColor.icoWhite)
                                .padding(8)
                        } else {
                            Image(systemName: "square.and.arrow.up")
                                .font(.title2)
                                .foregroundStyle(TLColor.icoWhite)
                                .padding(8)
                        }
                    }
                    .disabled(isDownloading || isPreparingShare || displayableURLs.isEmpty)
                    .accessibilityLabel("共有")
                }
                .padding()
                
                Spacer()
            }
            
            // 保存完了通知
            if showSaveConfirmation {
                VStack {
                    Spacer()
                    Text("写真を保存しました")
                        .font(.callout)
                        .foregroundStyle(TLColor.icoWhite)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(.bottom, 40)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .sheet(item: $sharePayload) { payload in
            ActivityView(activityItems: [payload.item])
                .ignoresSafeArea()
        }
        .onAppear {
            if urls.count != displayableURLs.count {
                print("[Gallery] filtered invalid urls total=\(urls.count) valid=\(displayableURLs.count)")
            }
            index = min(max(0, startIndex), max(0, displayableURLs.count - 1))
        }
    }
    
    /// 現在表示中の画像を共有シートで配布（"画像として" を保証するため一時JPEGを作成）
    func shareCurrentImage(url: URL) async {
        await MainActor.run { isPreparingShare = true }
        defer { Task { await MainActor.run { isPreparingShare = false } } }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let image = UIImage(data: data) else { return }
            guard let jpeg = image.jpegData(compressionQuality: 0.95) else { return }
            let tmp = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("jpg")
            try jpeg.write(to: tmp, options: .atomic)

            await MainActor.run {
                // 初回でも確実にトリガーされるようにいったん nil を挟む
                self.sharePayload = nil
                self.sharePayload = SharePayload(item: tmp)
            }
        } catch {
            print("[Share] failed:", error)
        }
    }
}

private struct SharePayload: Identifiable {
    let id = UUID()
    let item: URL
}
