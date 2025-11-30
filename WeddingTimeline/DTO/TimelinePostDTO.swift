//
//  TimelinePostDTO.swift
//  WeddingTimeline
//
//  Created by 田口友暉 on 2025/08/23.
//

import FirebaseFirestore
import Foundation

struct TimelinePostDTO: Codable {
    @DocumentID var id: String?            // 読み取り専用（書き込みでは使わない）
    let content: String
    let authorId: String
    let authorName: String
    let userIcon: String?
    let createdAt: Timestamp?
    let media: [MediaDTO]
    let replyCount: Int
    let retweetCount: Int
    var likeCount: Int?
    let tag: String?

    enum CodingKeys: String, CodingKey {
        case content, authorId, authorName, createdAt, media
        case userIcon
        case replyCount, retweetCount, likeCount
        case tag
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        
        // payload fields
        content      = try c.decodeIfPresent(String.self, forKey: .content) ?? ""
        authorId     = try c.decodeIfPresent(String.self, forKey: .authorId) ?? ""
        authorName   = try c.decodeIfPresent(String.self, forKey: .authorName) ?? ""
        userIcon     = try c.decodeIfPresent(String.self, forKey: .userIcon)
        createdAt    = try c.decodeIfPresent(Timestamp.self, forKey: .createdAt)
        media        = try c.decodeIfPresent([MediaDTO].self, forKey: .media) ?? []
        replyCount   = try c.decodeIfPresent(Int.self, forKey: .replyCount) ?? 0
        retweetCount = try c.decodeIfPresent(Int.self, forKey: .retweetCount) ?? 0
        likeCount    = try c.decodeIfPresent(Int.self, forKey: .likeCount) ?? 0
        tag          = try c.decodeIfPresent(String.self, forKey: .tag) ?? ""
    }
}
