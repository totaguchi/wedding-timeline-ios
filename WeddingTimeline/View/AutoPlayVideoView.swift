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
    @State private var durationText = "00:00"
    @State private var isPlaying = false
    @State private var currentTimeSec: Double = 0
    @State private var durationSec: Double = 0
    @State private var isScrubbing = false
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
                // Inline player (no controls)
                CustomVideoPlayerView(player: player, showsPlaybackControls: false)
                    .frame(height: 200)
                    .cornerRadius(10)
                    .allowsHitTesting(false) // インラインでの操作無効

                // Overlay: mute button (left) + duration pill (right)
                VStack {
                    Spacer()
                    HStack {
                        Text(formatTime(durationSec - currentTimeSec))
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.black.opacity(0.5))
                            .foregroundStyle(.white)
                            .clipShape(Capsule())
                        
                        Spacer()
                        
                        Button(action: {
                            isMuted.toggle()
                            player.isMuted = isMuted
                        }) {
                            Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.white)
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
                ZStack {
                    Color.black.ignoresSafeArea()

                    // Video without built-in controls; we overlay our own
                    CustomVideoPlayerView(player: player, showsPlaybackControls: false)
                        .ignoresSafeArea()

                    // Top bar: close (left) + mute (right)
                    VStack(spacing: 0) {
                        HStack {
                            Button(action: { isFullScreenPresented = false }) {
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

                        // Bottom controls + caption
                        VStack(spacing: 8) {
                            // Seek bar + time labels
                            VStack(spacing: 4) {
                                HStack(spacing: 4) {
                                    // Play / Pause button
                                    Button(action: { togglePlayPause() }) {
                                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                                            .font(.system(size: 22, weight: .bold))
                                            .foregroundStyle(.white)
                                            .padding(10)
                                            .background(Color.black.opacity(0.5))
                                            .clipShape(Circle())
                                    }
                                    Slider(value: Binding(get: { currentTimeSec }, set: { newVal in currentTimeSec = newVal }), in: 0...max(durationSec, 0.001), onEditingChanged: { editing in
                                        isScrubbing = editing
                                        if editing {
                                            player.pause()
                                        } else {
                                            seek(to: currentTimeSec) {
                                                if isPlaying { player.play() }
                                            }
                                        }
                                    })
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
                                // Caption (if provided)
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
                            // subtle gradient to improve readability like X
                            LinearGradient(colors: [Color.black.opacity(0.0), Color.black.opacity(0.6)], startPoint: .top, endPoint: .bottom)
                                .ignoresSafeArea(edges: .bottom)
                        )
                    }
                }
                .onAppear {
                    activatePlaybackAudioSession()
                    // Prepare duration and time observer
                    setupDurationAndObserver()
                    // Start playing with sound
                    player.isMuted = false
                    isMuted = false
                    player.play()
                    isPlaying = true
                }
                .onDisappear {
                    // Clean up observer & restore inline policy
                    if let token = timeObserver { player.removeTimeObserver(token); timeObserver = nil }
                    player.isMuted = true
                    isMuted = true
                    isPlaying = false
                }
            }
            .onAppear {
                isMuted = true
                player.isMuted = true
                Task { await prepareDuration() }
            }
            .onChange(of: frame.minY) {
                updatePlayStatus(frame: frame)
            }
            .onDisappear { player.pause() }
        }
        .frame(height: 200)
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

    private func prepareDuration() async {
        let asset = AVURLAsset(url: url)
        let duration: CMTime
        if #available(iOS 18.0, *) {
            duration = (try? await asset.load(.duration)) ?? .zero
        } else {
            duration = asset.duration
        }
        let seconds = CMTimeGetSeconds(duration)
        await MainActor.run { self.durationText = formatTime(seconds) }
    }
    
    private func activatePlaybackAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .moviePlayback, options: [.mixWithOthers])
            try session.setActive(true)
        } catch {
            print("[AudioSession] activation failed: \(error)")
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
        let t = CMTime(seconds: seconds, preferredTimescale: 600)
        player.seek(to: t, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
            completion?()
        }
    }

    private func setupDurationAndObserver() {
        // durationSec は起動時に算出、timeObserver で currentTimeSec を追従
        let asset = player.currentItem?.asset ?? AVURLAsset(url: url)
        if let d = (asset as? AVURLAsset)?.duration.seconds, d.isFinite, d > 0 {
            durationSec = d
        } else {
            let d = player.currentItem?.duration.seconds ?? 0
            durationSec = d.isFinite && d > 0 ? d : 0
        }

        if timeObserver == nil {
            let interval = CMTime(seconds: 0.25, preferredTimescale: 600)
            timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
                if !isScrubbing {
                    currentTimeSec = time.seconds
                }
            }
        }
    }
}

