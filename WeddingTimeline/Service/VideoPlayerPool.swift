//
//  VideoPlayerPool.swift
//  WeddingTimeline
//
//  Created by Codex on 2026/02/21.
//

import AVKit
import Foundation

final class VideoPlayerPool {
    static let shared = VideoPlayerPool()

    private let maxPlayers = 3
    private var idlePlayers: [AVPlayer] = []
    private var inUse: Set<ObjectIdentifier> = []
    private var allPlayers: [AVPlayer] = []
    private let lock = NSLock()

    private init() {}

    func acquire() -> AVPlayer {
        lock.lock()
        defer { lock.unlock() }

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

        // Pool is exhausted. Return a non-pooled player to avoid reuse conflicts.
        return AVPlayer()
    }

    func release(_ player: AVPlayer) {
        lock.lock()
        defer { lock.unlock() }

        let id = ObjectIdentifier(player)
        guard inUse.contains(id) else { return }
        inUse.remove(id)
        player.replaceCurrentItem(with: nil)
        idlePlayers.append(player)
    }
}
