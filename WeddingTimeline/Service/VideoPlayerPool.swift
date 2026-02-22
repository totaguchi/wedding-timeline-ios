//
//  VideoPlayerPool.swift
//  WeddingTimeline
//
//  Created by Codex on 2026/02/21.
//

import AVKit
import Foundation

@Observable
final class VideoPlayerPool {
    static let shared = VideoPlayerPool()

    private let maxPlayers = 3
    private var idlePlayers: [AVPlayer] = []
    private var inUse: Set<ObjectIdentifier> = []
    private var allPlayers: [AVPlayer] = []

    private init() {}

    func acquire() -> AVPlayer {
        if let player = idlePlayers.popLast() {
            inUse.insert(ObjectIdentifier(player))
            return player
        }

        let totalCount = allPlayers.count
        if totalCount < maxPlayers {
            let player = AVPlayer()
            allPlayers.append(player)
            inUse.insert(ObjectIdentifier(player))
            return player
        }

        // Pool is exhausted. Reuse the oldest player instance.
        let player = allPlayers[0]
        inUse.insert(ObjectIdentifier(player))
        return player
    }

    func release(_ player: AVPlayer) {
        let id = ObjectIdentifier(player)
        guard inUse.contains(id) else { return }
        inUse.remove(id)
        player.replaceCurrentItem(with: nil)
        idlePlayers.append(player)
    }
}
