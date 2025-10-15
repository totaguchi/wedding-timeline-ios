//
//  RoomMember.swift
//  WeddingTimeline
//
//  Created by 田口友暉 on 2025/09/01.
//

import Foundation
import FirebaseFirestore

/// ルーム文脈でのユーザー（= 画面に出す username はここ）
enum RoomRole: String, Codable { case owner, admin, member }

struct RoomMember: Identifiable, Hashable {
    static func == (lhs: RoomMember, rhs: RoomMember) -> Bool {
        lhs.id == rhs.id
    }
    
    var id: String        // = uid
    var roomId: String
    var username: String
    var usericon: String?
    var role: RoomRole
    var joinedAt: Date?
    var mutedUntil: Date?
    var isBanned: Bool
}

extension RoomMember {
    init?(roomId: String, dto: RoomMemberDTO) {
        guard let uid = dto.uid else { return nil }
        self.id = uid
        self.roomId = roomId
        self.username = dto.username
        self.usericon = dto.usericon
        self.role = RoomRole(rawValue: dto.role) ?? .member
        self.joinedAt = dto.joinedAt?.dateValue()
        self.mutedUntil = dto.mutedUntil?.dateValue()
        self.isBanned = dto.isBanned
    }
}
