//
//  FullScreenVideoView.swift
//  WeddingTimeline
//
//  Created by 田口友暉 on 2025/10/18.
//

import SwiftUI
import AVFoundation
import UIKit

// フルスクリーン専用: 再生コントロールを担当
struct FullScreenVideoView: View {
    let player: AVPlayer
    let caption: String?
    let initialDuration: Double
    let sourceURL: URL?
    @Environment(\.dismiss) private var dismiss
    @State private var isMuted = false
    @State private var isPlaying = true
    @State private var currentTimeSec: Double = 0
    @State private var durationSec: Double = 0
    @State private var isScrubbing = false
    @State private var timeObserver: Any?
    @State private var isPreparingShare = false
    @State private var shareItem: SharePayload?

    init(player: AVPlayer, caption: String?, initialDuration: Double = 0, sourceURL: URL? = nil) {
        self.player = player
        self.caption = caption
        self.initialDuration = initialDuration
        self.sourceURL = sourceURL
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            CustomVideoPlayerView(player: player, showsPlaybackControls: false)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundStyle(TLColor.icoWhite)
                            .shadow(radius: 4)
                    }
                    Spacer()
                    Button(action: {
                        Task { await shareCurrentVideo() }
                    }) {
                        if isPreparingShare {
                            ProgressView()
                                .tint(TLColor.icoWhite)
                                .padding(6)
                                .background(Color.black.opacity(0.5))
                                .clipShape(Circle())
                        } else {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(TLColor.icoWhite)
                                .padding(6)
                                .background(Color.black.opacity(0.5))
                                .clipShape(Circle())
                        }
                    }
                    .disabled(isPreparingShare)
                    .accessibilityLabel("共有")
                    Button(action: {
                        isMuted.toggle()
                        player.isMuted = isMuted
                    }) {
                        Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(TLColor.icoWhite)
                            .padding(6)
                            .background(Color.black.opacity(0.5))
                            .clipShape(Circle())
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)

                Spacer()

                VStack(spacing: 8) {
                    VStack(spacing: 4) {
                        HStack(spacing: 4) {
                            Button(action: { togglePlayPause() }) {
                                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                                    .font(.system(size: 22, weight: .bold))
                                    .foregroundStyle(TLColor.icoWhite)
                                    .padding(10)
                                    .background(Color.black.opacity(0.5))
                                    .clipShape(Circle())
                            }
                            Slider(
                                value: Binding(
                                    get: { currentTimeSec },
                                    set: { currentTimeSec = $0 }
                                ),
                                in: 0...max(durationSec, 0.001),
                                onEditingChanged: { editing in
                                    isScrubbing = editing
                                    if editing {
                                        player.pause()
                                    } else {
                                        seek(to: currentTimeSec) {
                                            if isPlaying { player.play() }
                                        }
                                    }
                                }
                            )
                            .tint(TLColor.icoWhite)
                        }

                        HStack {
                            Text(formatTime(currentTimeSec))
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(TLColor.icoWhite.opacity(0.9))
                            Spacer()
                            Text(formatTime(durationSec))
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(TLColor.icoWhite.opacity(0.9))
                        }

                        if let caption, !caption.isEmpty {
                            Text(caption)
                                .font(.callout)
                                .foregroundStyle(TLColor.icoWhite)
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .lineLimit(4)
                                .padding(.top, 4)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
                .background(
                    LinearGradient(
                        colors: [Color.black.opacity(0.0), Color.black.opacity(0.6)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .ignoresSafeArea(edges: .bottom)
                )
            }
        }
        .onAppear {
            durationSec = initialDuration
            setupTimeObserver()
            upgradeToFullQualityIfNeeded()
            player.isMuted = false
            isMuted = false
            player.play()
            isPlaying = true
        }
        .onDisappear {
            removeTimeObserver()
            player.isMuted = true
            isPlaying = false
        }
        .sheet(item: $shareItem) { payload in
            ActivityView(activityItems: [payload.item])
                .ignoresSafeArea()
        }
    }

    private func setupTimeObserver() {
        guard timeObserver == nil else { return }
        let interval = CMTime(seconds: 0.25, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak player] time in
            guard let player = player else { return }
            if !isScrubbing {
                currentTimeSec = time.seconds
            }
            
            // duration の更新
            if let duration = player.currentItem?.duration, duration.isValid, duration.seconds.isFinite {
                durationSec = duration.seconds
            }
        }
    }

    private func removeTimeObserver() {
        if let observer = timeObserver {
            player.removeTimeObserver(observer)
            timeObserver = nil
        }
    }

    private func togglePlayPause() {
        if isPlaying {
            player.pause()
        } else {
            player.play()
        }
        isPlaying.toggle()
    }

    private func seek(to seconds: Double, completion: (() -> Void)? = nil) {
        let time = CMTime(seconds: seconds, preferredTimescale: 600)
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
            DispatchQueue.main.async { completion?() }
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite && seconds >= 0 else { return "00:00" }
        let total = Int(seconds.rounded())
        let m = total / 60
        let s = total % 60
        return String(format: "%02d:%02d", m, s)
    }

    private func upgradeToFullQualityIfNeeded() {
        guard let url = sourceURL else { return }
        let current = player.currentTime()
        let item = AVPlayerItem(url: url)
        item.preferredForwardBufferDuration = 0 // デフォルト
        player.replaceCurrentItem(with: item)
        seek(to: current.seconds) {
            if isPlaying { player.play() }
        }
    }
    
    /// 現在の AVPlayerItem から動画ファイルを一時URLに用意して共有シートを表示
    func shareCurrentVideo() async {
        await MainActor.run { isPreparingShare = true }
        defer { Task { await MainActor.run { isPreparingShare = false } } }

        guard let asset = player.currentItem?.asset else { return }

        do {
            let fileURL: URL
            if let urlAsset = asset as? AVURLAsset {
                fileURL = try await prepareShareableFile(from: urlAsset.url)
            } else {
                fileURL = try await exportAssetToTempFile(asset)
            }
            await MainActor.run {
                // いったん nil にしてから入れ直すことで初回でも正しくシートが表示される
                self.shareItem = nil
                self.shareItem = SharePayload(item: fileURL)
            }
        } catch {
            print("[Share] video share failed:", error)
        }
    }

    /// リモート/ローカルのURLから共有用の一時ファイルを作る
    private func prepareShareableFile(from src: URL) async throws -> URL {
        let tmpDir = FileManager.default.temporaryDirectory
        let ext = src.pathExtension.isEmpty ? "mp4" : src.pathExtension
        let dst = tmpDir.appendingPathComponent(UUID().uuidString).appendingPathExtension(ext)

        if src.isFileURL {
            // ローカルファイルならコピー
            try? FileManager.default.removeItem(at: dst)
            try FileManager.default.copyItem(at: src, to: dst)
            return dst
        } else {
            // リモートURLはダウンロード
            let (localURL, _) = try await URLSession.shared.download(from: src)
            try? FileManager.default.removeItem(at: dst)
            try FileManager.default.moveItem(at: localURL, to: dst)
            return dst
        }
    }

    /// AVAsset をエクスポートして一時mp4に（URLAssetが取れない場合のフォールバック）
    private func exportAssetToTempFile(_ asset: AVAsset) async throws -> URL {
        let outURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mp4")
        guard let exporter = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough) else {
            throw NSError(domain: "VideoShare", code: -10, userInfo: [NSLocalizedDescriptionKey: "Export session unavailable"])
        }
        exporter.outputURL = outURL
        exporter.outputFileType = .mp4
        exporter.shouldOptimizeForNetworkUse = true

        try? FileManager.default.removeItem(at: outURL)

        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            exporter.exportAsynchronously { cont.resume() }
        }

        if exporter.status == .completed {
            return outURL
        } else {
            throw exporter.error ?? NSError(domain: "VideoShare", code: -11, userInfo: [NSLocalizedDescriptionKey: "Export failed with status \(exporter.status.rawValue)"])
        }
    }
}

private struct SharePayload: Identifiable {
    let id = UUID()
    let item: URL
}

#Preview {
    // FullScreenVideoView()
}
