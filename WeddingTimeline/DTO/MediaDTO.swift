//
//  MediaDTO.swift
//  WeddingTimeline
//
//  Created by 田口友暉 on 2025/08/25.
//

import Foundation

struct MediaDTO: Codable {
    let id: String
    let type: String?
    var mediaUrl: String
    let width: Int?
    let height: Int?
    let duration: Double? // 秒（動画のみ）
    let storagePath: String? // Storage のフルパス（例: rooms/{roomId}/posts/{postId}/{userId}/file)

    init(
        id: String,
        type: String?,
        mediaUrl: String,
        width: Int?,
        height: Int?,
        duration: Double?,
        storagePath: String? = nil
    ) {
        self.id = id
        self.type = type
        self.mediaUrl = mediaUrl
        self.width = width
        self.height = height
        self.duration = duration
        self.storagePath = storagePath
    }
}
