//
//  AutoPlayVideoView.swift
//  WeddingTimeline
//
//  Created by 田口友暉 on 2025/07/14.
//

import AVKit
import SwiftUI

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

    init(url: URL, caption: String? = nil) {
        self.url = url
        self.caption = caption
        _player = State(initialValue: AVPlayer(url: url))
    }

    var body: some View {
        GeometryReader { proxy in
            let frame = proxy.frame(in: .named("scroll"))
            ZStack {
                CustomVideoPlayerView(player: player, showsPlaybackControls: false)
                    .frame(height: 200)
                    .cornerRadius(10)
                    .allowsHitTesting(false)

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
                    initialDuration: durationSec
                )
            }
            .onAppear {
                isMuted = true
                player.isMuted = true
                setupTimeObserver()
                Task { await prepareDuration() }
            }
            .onChange(of: frame.minY) {
                updatePlayStatus(frame: frame)
            }
            .onDisappear {
                removeTimeObserver()
                player.pause()
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
            
            // duration の更新（currentItem から取得）
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

    private func prepareDuration() async {
        let asset = AVURLAsset(url: url)
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

    private func updatePlayStatus(frame: CGRect) {
        let screenHeight = UIScreen.main.bounds.height
        let centerThreshold = screenHeight / 2

        if abs(frame.midY - centerThreshold) < 150 {
            if !isVisible {
                player.play()
                isVisible = true
            }
        } else {
            if isVisible {
                player.pause()
                isVisible = false
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
}
