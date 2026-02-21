//
//  AutoPlayVideoView.swift
//  WeddingTimeline
//
//  Created by 田口友暉 on 2025/07/14.
//

import AVKit
import SwiftUI
import UIKit
import CryptoKit

// シンプルな同時実行制御（スクロール中の重い処理が詰まるのを防ぐ）
private actor TaskLimiter {
    private let maxConcurrent: Int
    private var current = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(maxConcurrent: Int) { self.maxConcurrent = maxConcurrent }

    func withPermit<T>(_ work: @Sendable () async throws -> T) async rethrows -> T {
        await acquire()
        defer { release() }
        return try await work()
    }

    private func acquire() async {
        if current < maxConcurrent {
            current += 1
            return
        }
        await withCheckedContinuation { cont in
            waiters.append(cont)
        }
    }

    private func release() {
        current = max(0, current - 1)
        if !waiters.isEmpty {
            let cont = waiters.removeFirst()
            cont.resume()
            current += 1
        }
    }
}

struct AutoPlayVideoView: View {
    let url: URL
    let caption: String?
    @State private var player: AVPlayer
    @State private var isVisible = false
    @State private var isFullScreenPresented = false
    @State private var isMuted = true
    @State private var currentTimeSec: Double = 0
    @State private var durationSec: Double = 0
    @State private var timeObserver: Any?
    @State private var isPlayerReady = false
    @State private var lastVisibilityCheck: CFTimeInterval = 0
    @State private var thumbImage: UIImage?
    @State private var cachedURL: URL?
    @State private var didPrepareInline = false
    @State private var didPrepareThumb = false
    @State private var didCache = false
    @State private var pendingCachedURL: URL?

    // グローバルに絞る（同時に大量に走らないように）
    private static let thumbnailLimiter = TaskLimiter(maxConcurrent: 1)
    private static let cacheLimiter = TaskLimiter(maxConcurrent: 1)

    init(url: URL, caption: String? = nil) {
        self.url = url
        self.caption = caption
        _player = State(initialValue: AVPlayer(url: url))
    }

    var body: some View {
        GeometryReader { proxy in
            let frame = proxy.frame(in: .named("TimelineScroll"))
            ZStack {
                if let thumbImage {
                    Image(uiImage: thumbImage)
                        .resizable()
                        .scaledToFill()
                        .frame(height: 200)
                        .clipped()
                        .cornerRadius(10)
                }

                CustomVideoPlayerView(player: player, showsPlaybackControls: false)
                    .frame(height: 200)
                    .cornerRadius(10)
                    .allowsHitTesting(false)
                    .opacity(isPlayerReady ? 1 : 0.0001)

                VStack {
                    Spacer()
                    HStack {
                        Text(formatTime(max(0, durationSec - currentTimeSec)))
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.black.opacity(0.5))
                            .foregroundStyle(TLColor.icoWhite)
                            .clipShape(Capsule())

                        Spacer()

                        Button(action: {
                            isMuted.toggle()
                            player.isMuted = isMuted
                        }) {
                            Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(TLColor.icoWhite)
                                .padding(6)
                                .background(.black.opacity(0.5))
                                .clipShape(Circle())
                        }
                    }
                    .padding(8)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { isFullScreenPresented = true }
            .fullScreenCover(isPresented: $isFullScreenPresented) {
                FullScreenVideoView(
                    player: player,
                    caption: caption,
                    initialDuration: durationSec,
                    sourceURL: cachedURL ?? url
                )
            }
            .onAppear {
                isMuted = true
                player.isMuted = true
                player.automaticallyWaitsToMinimizeStalling = false
                setupTimeObserver()
                if !didPrepareInline {
                    didPrepareInline = true
                    Task(priority: .utility) { await prepareInlineItem() }
                }
                if !didPrepareThumb {
                    didPrepareThumb = true
                    Task(priority: .utility) { await Self.thumbnailLimiter.withPermit { await prepareThumbnail() } }
                }
                if !didCache {
                    didCache = true
                    Task(priority: .utility) { await Self.cacheLimiter.withPermit { await cacheRemoteIfNeeded() } }
                }
            }
            .onChange(of: frame.minY) {
                updatePlayStatus(frame: frame)
            }
            .onDisappear {
                removeTimeObserver()
                player.pause()
                isPlayerReady = false
            }
        }
        .frame(height: 200)
    }

    private func setupTimeObserver() {
        guard timeObserver == nil else { return }
        let interval = CMTime(seconds: 0.25, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak player] time in
            guard let player = player else { return }
            currentTimeSec = time.seconds
            
            updateDurationIfNeeded(from: player.currentItem)
            if !isPlayerReady { isPlayerReady = player.timeControlStatus != .waitingToPlayAtSpecifiedRate }
        }
    }

    private func removeTimeObserver() {
        if let observer = timeObserver {
            player.removeTimeObserver(observer)
            timeObserver = nil
        }
    }

    private func prepareInlineItem() async {
        let playableURL = await resolvedPlaybackURL()
        let item = makeInlineItem(for: playableURL)
        await MainActor.run {
            cachedURL = (playableURL.isFileURL ? playableURL : cachedURL)
            player.replaceCurrentItem(with: item)
        }
        await prepareDuration(from: item.asset)
    }

    private func updatePlayStatus(frame: CGRect) {
        let screenHeight = UIScreen.main.bounds.height
        let centerThreshold = screenHeight / 2

        // 過剰な頻度で処理しない（約120ms間隔）
        let now = CACurrentMediaTime()
        guard now - lastVisibilityCheck > 0.12 else { return }
        lastVisibilityCheck = now

        if abs(frame.midY - centerThreshold) < 150 {
            if !isVisible {
                player.play()
                isVisible = true
            }
        } else {
            if isVisible {
                player.pause()
                isVisible = false
                // 見えていない間にキャッシュ済みのURLへ差し替え（スクロール中のハングを抑える）
                if let pending = pendingCachedURL {
                    let current = player.currentTime()
                    let item = makeInlineItem(for: pending)
                    player.replaceCurrentItem(with: item)
                    player.seek(to: current, toleranceBefore: .zero, toleranceAfter: .zero)
                    cachedURL = pending
                    pendingCachedURL = nil
                }
            }
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite && seconds >= 0 else { return "00:00" }
        let total = Int(seconds.rounded())
        let m = total / 60
        let s = total % 60
        return String(format: "%02d:%02d", m, s)
    }

    private func makeInlineItem(for url: URL) -> AVPlayerItem {
        let item = AVPlayerItem(url: url)
        item.preferredMaximumResolution = CGSize(width: 1280, height: 720) // 720p 相当で初期バッファ軽量化
        item.preferredPeakBitRate = 3_000_000 // ~3Mbps
        item.preferredForwardBufferDuration = 1 // 1秒だけ前読み
        return item
    }

    private func updateDurationIfNeeded(from item: AVPlayerItem?) {
        guard let duration = item?.duration, duration.isValid, duration.seconds.isFinite else { return }
        durationSec = duration.seconds
    }

    private func prepareDuration(from asset: AVAsset) async {
        let duration: CMTime
        if #available(iOS 18.0, *) {
            duration = (try? await asset.load(.duration)) ?? .zero
        } else {
            duration = asset.duration
        }
        if duration.isValid, duration.seconds.isFinite {
            await MainActor.run { durationSec = duration.seconds }
        }
    }

    private func resolvedPlaybackURL() async -> URL {
        if let cached = cachedLocalURL(for: url) {
            await MainActor.run { cachedURL = cached }
            return cached
        }
        return url
    }

    private func cacheRemoteIfNeeded() async {
        // ローカルURLや既存キャッシュはスキップ
        guard !url.isFileURL, cachedLocalURL(for: url) == nil else { return }
        let cacheDir = cacheDirectory()
        let dst = cacheDir.appendingPathComponent(cacheKey(for: url)).appendingPathExtension(url.pathExtension.isEmpty ? "mp4" : url.pathExtension)
        do {
            let (tmp, _) = try await URLSession.shared.download(from: url)
            try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
            try? FileManager.default.removeItem(at: dst)
            try FileManager.default.moveItem(at: tmp, to: dst)

            // 再生中なら差し替え（現在位置を維持）
            let current = await MainActor.run { player.currentTime() }
            let item = makeInlineItem(for: dst)
            await MainActor.run {
                if isVisible {
                    // 再生中は差し替えを遅延し、スクロール停止/画面外で適用
                    pendingCachedURL = dst
                } else {
                    cachedURL = dst
                    player.replaceCurrentItem(with: item)
                    player.seek(to: current, toleranceBefore: .zero, toleranceAfter: .zero)
                }
            }
        } catch {
            print("[AutoPlayVideoView] cache download failed:", error)
        }
    }

    private func cacheDirectory() -> URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("VideoCache", isDirectory: true)
    }

    private func cacheKey(for url: URL) -> String {
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8))
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }

    private func cachedLocalURL(for url: URL) -> URL? {
        let dir = cacheDirectory()
        let base = dir.appendingPathComponent(cacheKey(for: url))
        let ext = url.pathExtension.isEmpty ? "mp4" : url.pathExtension
        let candidate = base.appendingPathExtension(ext)
        return FileManager.default.fileExists(atPath: candidate.path) ? candidate : nil
    }

    private func prepareThumbnail() async {
        if let cached = cachedThumbnail(for: url) {
            await MainActor.run { thumbImage = cached }
            return
        }
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 480, height: 480) // 低解像度で生成コストを抑える
        do {
            let cgImage = try generator.copyCGImage(at: CMTime(seconds: 0.1, preferredTimescale: 600), actualTime: nil)
            let img = UIImage(cgImage: cgImage)
            await MainActor.run { thumbImage = img }
            cacheThumbnail(img, for: url)
        } catch {
            // サムネ生成失敗時は無視
        }
    }

    private func thumbnailDirectory() -> URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("VideoThumbs", isDirectory: true)
    }

    private func cachedThumbnail(for url: URL) -> UIImage? {
        let dir = thumbnailDirectory()
        let path = dir.appendingPathComponent(cacheKey(for: url)).appendingPathExtension("jpg")
        guard let data = try? Data(contentsOf: path),
              let img = UIImage(data: data) else { return nil }
        return img
    }

    private func cacheThumbnail(_ image: UIImage, for url: URL) {
        let dir = thumbnailDirectory()
        let path = dir.appendingPathComponent(cacheKey(for: url)).appendingPathExtension("jpg")
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            if let data = image.jpegData(compressionQuality: 0.75) {
                try data.write(to: path, options: .atomic)
            }
        } catch {
            // キャッシュ失敗は致命的でないので無視
        }
    }
}
