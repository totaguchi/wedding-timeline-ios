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
    /// Pool 上限超過時に貸し出した一時プレーヤー（プールには戻さず release 時に破棄）
    private var overflowPlayers: Set<ObjectIdentifier> = []
    private let lock = NSLock()

    private init() {}

    func acquire() -> AVPlayer {
        lock.lock()
        defer { lock.unlock() }

        if let player = idlePlayers.popLast() {
            inUse.insert(ObjectIdentifier(player))
            return player
        }

        if allPlayers.count < maxPlayers {
            let player = AVPlayer()
            allPlayers.append(player)
            inUse.insert(ObjectIdentifier(player))
            return player
        }

        // Pool is exhausted. Return a temporary player and track it for cleanup on release.
        let player = AVPlayer()
        overflowPlayers.insert(ObjectIdentifier(player))
        return player
    }

    func release(_ player: AVPlayer) {
        let id = ObjectIdentifier(player)

        lock.lock()
        let isOverflow = overflowPlayers.remove(id) != nil
        let isPooled = !isOverflow && inUse.contains(id)
        if isPooled {
            inUse.remove(id)
        }
        lock.unlock()

        guard isOverflow || isPooled else { return }

        // replaceCurrentItem はロック外で呼ぶ（AVPlayer 内部ロックとのデッドロックを避けるため）
        player.replaceCurrentItem(with: nil)

        if isPooled {
            lock.lock()
            idlePlayers.append(player)
            lock.unlock()
        }
    }
}
