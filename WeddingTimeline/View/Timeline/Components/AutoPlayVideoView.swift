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
    let isActive: Bool
    @State private var player: AVPlayer?
    @State private var isVisible = false
    @State private var isFullScreenPresented = false
    @State private var isMuted = true
    @State private var currentTimeSec: Double = 0
    @State private var durationSec: Double = 0
    @State private var timeObserver: Any?
    @State private var isPlayerReady = false
    @State private var isEligibleForPlayback = true
    @State private var thumbImage: UIImage?
    @State private var cachedURL: URL?
    @State private var didPrepareInline = false
    @State private var didPrepareThumb = false
    @State private var didCache = false
    @State private var pendingCachedURL: URL?
    @State private var statusObserver: NSKeyValueObservation?
    @State private var keepUpObserver: NSKeyValueObservation?
    @State private var errorObserver: NSKeyValueObservation?
    @State private var playRetryTask: Task<Void, Never>?
    @State private var shouldAutoPlay = false
    @State private var lastPreparedURL: URL?
    @State private var didRetryAfterError = false

    // グローバルに絞る（同時に大量に走らないように）
    private static let thumbnailLimiter = TaskLimiter(maxConcurrent: 2)
    private static let cacheLimiter = TaskLimiter(maxConcurrent: 1)

    init(url: URL, caption: String? = nil, isActive: Bool = true) {
        self.url = url
        self.caption = caption
        self.isActive = isActive
    }

    var body: some View {
        let base = ZStack {
            if let thumbImage {
                Image(uiImage: thumbImage)
                    .resizable()
                    .scaledToFill()
                    .frame(height: 200)
                    .clipped()
                    .cornerRadius(10)
            }

            if let player {
                CustomVideoPlayerView(player: player, showsPlaybackControls: false)
                    .frame(height: 200)
                    .cornerRadius(10)
                    .allowsHitTesting(false)
                    .opacity(isPlayerReady ? 1 : 0.0001)
            } else {
                Color.clear.frame(height: 200)
            }

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
                        player?.isMuted = isMuted
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

        Group {
            if #available(iOS 18.0, *) {
                base.onScrollVisibilityChange(threshold: 0.5) { isVisible in
                    isEligibleForPlayback = isVisible
                    Task { @MainActor in updatePlaybackState() }
                }
            } else {
                base
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            Task { @MainActor in ensurePlayer() }
            isFullScreenPresented = true
        }
        .fullScreenCover(isPresented: $isFullScreenPresented) {
            if let player {
                FullScreenVideoView(
                    player: player,
                    caption: caption,
                    initialDuration: durationSec,
                    sourceURL: cachedURL ?? url
                )
            }
        }
        .onAppear {
            Task { @MainActor in
                if isActive {
                    activatePlayer()
                }
                updatePlaybackState()
            }
            if !didPrepareThumb {
                didPrepareThumb = true
                Task(priority: .background) { await Self.thumbnailLimiter.withPermit { await prepareThumbnail() } }
            }
            if !didCache {
                Task(priority: .background) {
                    let ok = await Self.cacheLimiter.withPermit { await cacheRemoteIfNeeded() }
                    await MainActor.run { didCache = ok }
                }
            }
        }
        .onChange(of: isActive) { _, _ in
            Task { @MainActor in updatePlaybackState() }
        }
        .onChange(of: isEligibleForPlayback) { _, _ in
            Task { @MainActor in updatePlaybackState() }
        }
        .onDisappear {
            Task { @MainActor in deactivatePlayer() }
        }
        .frame(height: 200)
    }

    private func setupTimeObserver() {
        guard timeObserver == nil, let player else { return }
        let interval = CMTime(seconds: 0.25, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak player] time in
            guard let player = player else { return }
            Task { @MainActor in
                currentTimeSec = time.seconds
                updateDurationIfNeeded(from: player.currentItem)
                if !isPlayerReady { isPlayerReady = player.timeControlStatus != .waitingToPlayAtSpecifiedRate }
            }
        }
    }

    private func removeTimeObserver() {
        if let observer = timeObserver, let player {
            player.removeTimeObserver(observer)
            timeObserver = nil
        } else {
            timeObserver = nil
        }
    }

    private func prepareInlineItem() async {
        guard let player else { return }
        let playableURL = await resolvedPlaybackURL()
        let item = makeInlineItem(for: playableURL)
        await MainActor.run {
            lastPreparedURL = playableURL
            cachedURL = (playableURL.isFileURL ? playableURL : cachedURL)
            player.replaceCurrentItem(with: item)
            observePlayerItem(item)
            updatePlaybackState()
        }
        await prepareDuration(from: item.asset)
    }

    @MainActor
    private func observePlayerItem(_ item: AVPlayerItem) {
        statusObserver?.invalidate()
        keepUpObserver?.invalidate()
        errorObserver?.invalidate()

        statusObserver = item.observe(\.status, options: [.initial, .new]) { [weak item] _, _ in
            guard let item else { return }
            Task { @MainActor in
                isPlayerReady = (item.status == .readyToPlay)
                if isPlayerReady { attemptPlaybackIfNeeded() }
            }
        }

        keepUpObserver = item.observe(\.isPlaybackLikelyToKeepUp, options: [.initial, .new]) { [weak item] _, _ in
            guard let item else { return }
            Task { @MainActor in
                if item.isPlaybackLikelyToKeepUp { attemptPlaybackIfNeeded() }
            }
        }

        errorObserver = item.observe(\.error, options: [.initial, .new]) { [weak item] _, _ in
            guard let item else { return }
            Task { @MainActor in
                if let _ = item.error {
                    if let prepared = lastPreparedURL, prepared.isFileURL, !didRetryAfterError {
                        didRetryAfterError = true
                        try? FileManager.default.removeItem(at: prepared)
                        cachedURL = nil
                        lastPreparedURL = nil
                        Task(priority: .utility) { await prepareInlineItem() }
                    }
                }
            }
        }
    }

    @MainActor
    private func cancelItemObservation() {
        statusObserver?.invalidate()
        keepUpObserver?.invalidate()
        errorObserver?.invalidate()
        statusObserver = nil
        keepUpObserver = nil
        errorObserver = nil
    }

    @MainActor
    private func ensurePlayer() {
        if player == nil {
            activatePlayer()
        }
    }

    @MainActor
    private func activatePlayer() {
        guard player == nil else { return }
        let newPlayer = VideoPlayerPool.shared.acquire()
        player = newPlayer
        isMuted = true
        isPlayerReady = false
        currentTimeSec = 0
        durationSec = 0
        newPlayer.isMuted = true
        newPlayer.automaticallyWaitsToMinimizeStalling = false
        setupTimeObserver()
        // Player instance is swapped when re-acquired, so inline item must be prepared again.
        didPrepareInline = true
        Task(priority: .utility) { await prepareInlineItem() }
    }

    @MainActor
    private func deactivatePlayer() {
        guard let player else { return }
        playRetryTask?.cancel()
        playRetryTask = nil
        cancelItemObservation()
        removeTimeObserver()
        player.pause()
        isPlayerReady = false
        isVisible = false
        shouldAutoPlay = false
        VideoPlayerPool.shared.release(player)
        self.player = nil
    }

    @MainActor
    private func updatePlaybackState() {
        let shouldPlay = isActive && isEligibleForPlayback
        shouldAutoPlay = shouldPlay
        if shouldPlay {
            if player == nil { activatePlayer() }
            attemptPlaybackIfNeeded()
        } else {
            guard let player else { return }
            if isVisible {
                player.pause()
                isVisible = false
                // 見えていない間にキャッシュ済みのURLへ差し替え（スクロール中のハングを抑える）
                if let pending = pendingCachedURL {
                    let current = player.currentTime()
                    let item = makeInlineItem(for: pending)
                    player.replaceCurrentItem(with: item)
                    observePlayerItem(item)
                    player.seek(to: current, toleranceBefore: .zero, toleranceAfter: .zero)
                    cachedURL = pending
                    pendingCachedURL = nil
                }
            }
        }
    }

    @MainActor
    private func attemptPlaybackIfNeeded() {
        guard shouldAutoPlay else { return }
        guard let player else { return }
        if !isVisible {
            player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
            player.play()
            isVisible = true
        }

        playRetryTask?.cancel()
        playRetryTask = Task { @MainActor in
            let retries = 3
            for _ in 0..<retries {
                try? await Task.sleep(for: .milliseconds(250))
                guard shouldAutoPlay, let player = self.player else { return }
                if player.timeControlStatus != .playing {
                    player.play()
                } else {
                    return
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
        if #available(iOS 16.0, *) {
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

    private func cacheRemoteIfNeeded() async -> Bool {
        // ローカルURLや既存キャッシュはスキップ
        guard !url.isFileURL, cachedLocalURL(for: url) == nil else { return false }
        let cacheDir = cacheDirectory()
        let dst = cacheDir.appendingPathComponent(cacheKey(for: url)).appendingPathExtension(url.pathExtension.isEmpty ? "mp4" : url.pathExtension)
        do {
            let (tmp, response) = try await URLSession.shared.download(from: url)
            if let http = response as? HTTPURLResponse {
                guard (200...299).contains(http.statusCode) else {
                    try? FileManager.default.removeItem(at: tmp)
                    return false
                }
            }
            if let mime = response.mimeType, !mime.contains("video") {
                try? FileManager.default.removeItem(at: tmp)
                return false
            }
            let attrs = try? FileManager.default.attributesOfItem(atPath: tmp.path)
            let size = (attrs?[.size] as? NSNumber)?.int64Value ?? 0
            if size < 1024 {
                try? FileManager.default.removeItem(at: tmp)
                return false
            }

            try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
            try? FileManager.default.removeItem(at: dst)
            try FileManager.default.moveItem(at: tmp, to: dst)

            // 再生中なら差し替え（現在位置を維持）
            let current = await MainActor.run { player?.currentTime() ?? .zero }
            let item = makeInlineItem(for: dst)
            await MainActor.run {
                if isVisible {
                    // 再生中は差し替えを遅延し、スクロール停止/画面外で適用
                    pendingCachedURL = dst
                } else if let player {
                    cachedURL = dst
                    player.replaceCurrentItem(with: item)
                    observePlayerItem(item)
                    player.seek(to: current, toleranceBefore: .zero, toleranceAfter: .zero)
                } else {
                    cachedURL = dst
                }
            }
            return true
        } catch {
            print("[AutoPlayVideoView] cache download failed:", error)
            return false
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
