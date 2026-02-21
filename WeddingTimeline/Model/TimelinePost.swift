//
//  TimelinePost.swift
//  WeddingTimeline
//
//  Created by 田口友暉 on 2025/07/13.
//

import FirebaseFirestore
import Foundation
import Observation
import SwiftUI

struct TimelinePost: Identifiable {
    var id: String
    var authorId: String
    var userName: String
    var userIcon: String
    var content: String
    var createdAt: Date
    var replyCount: Int
    var retweetCount: Int
    var likeCount: Int
    var isLiked: Bool
    var media: [Media]
    var tag: PostTag
    /// 初期化時に計算済みの日付文字列（毎描画の DateFormatter 呼び出しを回避）
    let formattedCreatedAt: String

    init(
        id: String,
        authorId: String,
        userName: String,
        userIcon: String,
        content: String,
        createdAt: Date,
        replyCount: Int,
        retweetCount: Int,
        likeCount: Int,
        media: [Media] = [],
        isLiked: Bool = false,
        tag: PostTag = .unknown
    ) {
        self.id = id
        self.authorId = authorId
        self.userName = userName
        self.userIcon = userIcon
        self.content = content
        self.createdAt = createdAt
        self.replyCount = replyCount
        self.retweetCount = retweetCount
        self.likeCount = likeCount
        self.media = media
        self.isLiked = isLiked
        self.tag = tag
        self.formattedCreatedAt = DateFormatter.appCreatedAt.string(from: createdAt)
    }
}

extension TimelinePost {
    init?(dto: TimelinePostDTO) {
        self.init(
            id: dto.id!,
            authorId: dto.authorId,
            userName: dto.authorName,
            userIcon: dto.userIcon ?? "",
            content: dto.content,
            createdAt: dto.createdAt?.dateValue() ?? Date(),
            replyCount: dto.replyCount,
            retweetCount: dto.retweetCount,
            likeCount: dto.likeCount ?? 0,
            media: (dto.media).compactMap { Media(dto: $0) },
            isLiked: false,
            tag: PostTag(rawValue: dto.tag ?? "") ?? .unknown
        )
    }
}

extension TimelinePost: Equatable {
    static func == (lhs: TimelinePost, rhs: TimelinePost) -> Bool {
        return lhs.id == rhs.id &&
        lhs.likeCount == rhs.likeCount &&
        lhs.isLiked == rhs.isLiked
    }
}
    
