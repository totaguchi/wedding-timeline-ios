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
    @State private var player: AVPlayer
    @State private var isVisible = false
    
    init(url: URL) {
        self.url = url
        _player = State(initialValue: AVPlayer(url: url))
    }
    
    var body: some View {
        GeometryReader { proxy in
            let frame = proxy.frame(in: .named("scroll"))
            Color.clear
                .onAppear {
                    player.isMuted = true
                }
                .onChange(of: frame.minY) {
                    updatePlayStatus(frame: frame)
                }
                .onDisappear {
                    player.pause()
                }
        }
        .background(
            VideoPlayer(player: player)
                .frame(height: 200)
                .cornerRadius(10)
        )
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
}

#Preview {
    // AutoPlayVideoView()
}
