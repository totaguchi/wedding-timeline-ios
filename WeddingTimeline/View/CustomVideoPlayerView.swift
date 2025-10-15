//
//  CustomVideoPlayerView.swift
//  WeddingTimeline
//
//  Created by 田口友暉 on 2025/10/15.
//

import SwiftUI
import UIKit
import AVFoundation
import AVKit

struct CustomVideoPlayerView: UIViewControllerRepresentable {
    let player: AVPlayer
    var showsPlaybackControls: Bool = false
    
    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let vc = AVPlayerViewController()
        vc.player = player
        vc.showsPlaybackControls = showsPlaybackControls
        vc.entersFullScreenWhenPlaybackBegins = false
        vc.exitsFullScreenWhenPlaybackEnds = false
        vc.canStartPictureInPictureAutomaticallyFromInline = true
        return vc
    }
    func updateUIViewController(_ vc: AVPlayerViewController, context: Context) {}
}

#Preview {
    CustomVideoPlayerView(player: AVPlayer())
}

