//
//  DisplayTag.swift
//  WeddingTimeline
//
//  Created by 田口友暉 on 2025/12/01.
//

import Foundation
import CryptoKit

enum DisplayTag {
    static let tagLength: Int = 4
    static let useRoomScopedTag: Bool = true
    
    /// ルームスコープな短縮タグ（@xxxx）を生成
    static func make(roomId: String, uid: String, length: Int? = nil, useRoomScoped: Bool? = nil) -> String {
        let raw = length ?? Self.tagLength
        let n = max(1, raw)
        let scoped = useRoomScoped ?? Self.useRoomScopedTag
        return scoped ? roomScoped(roomId: roomId, uid: uid, length: n) : uidScoped(uid: uid, length: n)
    }
    
    /// ルームIDとuidのハッシュから生成（ルームを跨ぐ追跡を避けられる）
    static func roomScoped(roomId: String, uid: String, length: Int = Self.tagLength) -> String {
        let data = Data((roomId + ":" + uid).utf8)
        let hash = SHA256.hash(data: data)
        let hex = hash.map { String(format: "%02x", $0) }.joined()
        return "@" + String(hex.prefix(max(1, length)))
    }

    /// 純粋に uid の先頭から生成（ルームを跨いでも同一タグ）
    static func uidScoped(uid: String, length: Int = Self.tagLength) -> String {
        return "@" + String(uid.prefix(max(1, length))).lowercased()
    }
}
