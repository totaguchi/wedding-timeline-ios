//
//  RoomMemberDTO.swift
//  WeddingTimeline
//
//  Created by 田口友暉 on 2025/08/31.
//

import Foundation
import FirebaseFirestore

// /rooms/{roomId}/members/{uid}
struct RoomMemberDTO: Codable {
    @DocumentID var uid: String?
    var username: String
    var usernameLower: String
    var usericon: String?        // 追加
    var role: String              // "owner" | "admin" | "member"
    @ServerTimestamp var joinedAt: Timestamp?
    var mutedUntil: Timestamp?
    var isBanned: Bool
}
