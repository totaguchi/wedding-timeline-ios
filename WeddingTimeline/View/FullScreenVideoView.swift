//
//  FullScreenVideoView.swift
//  WeddingTimeline
//
//  Created by 田口友暉 on 2025/10/18.
//

import SwiftUI
import AVFoundation

// フルスクリーン専用: 再生コントロールを担当
struct FullScreenVideoView: View {
    let player: AVPlayer
    let caption: String?
    let initialDuration: Double
    @Environment(\.dismiss) private var dismiss
    @State private var isMuted = false
    @State private var isPlaying = true
    @State private var currentTimeSec: Double = 0
    @State private var durationSec: Double = 0
    @State private var isScrubbing = false
    @State private var timeObserver: Any?

    init(player: AVPlayer, caption: String?, initialDuration: Double = 0) {
        self.player = player
        self.caption = caption
        self.initialDuration = initialDuration
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
                            .foregroundStyle(.white)
                            .shadow(radius: 4)
                    }
                    Spacer()
                    Button(action: {
                        isMuted.toggle()
                        player.isMuted = isMuted
                    }) {
                        Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(.white)
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
                                    .foregroundStyle(.white)
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
                            .tint(.white)
                        }

                        HStack {
                            Text(formatTime(currentTimeSec))
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.white.opacity(0.9))
                            Spacer()
                            Text(formatTime(durationSec))
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.white.opacity(0.9))
                        }

                        if let caption, !caption.isEmpty {
                            Text(caption)
                                .font(.callout)
                                .foregroundStyle(.white)
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
}

#Preview {
    // FullScreenVideoView()
}
