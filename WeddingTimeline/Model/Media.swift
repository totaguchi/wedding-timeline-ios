//
//  Media.swift
//  WeddingTimeline
//
//  Created by 田口友暉 on 2025/08/26.
//

import Foundation
import CoreGraphics

struct Media: Identifiable, Hashable {
    let id: String
    let type: MediaKind
    var mediaUrl: URL
    let pixelSize: CGSize?
    let duration: TimeInterval?  // 動画のみ
    let storagePath: String?  // Storage のフルパス（例: rooms/{roomId}/posts/{postId}/{userId}/file)

    var aspectRatio: CGFloat? {
        guard let s = pixelSize, s.height > 0 else { return nil }
        return s.width / s.height
    }

    // var isPlaying: Bool = false
    // var isMuted: Bool = true
}

extension Media {
    init?(dto: MediaDTO) {
        guard let url = URL(string: dto.mediaUrl) else { return nil }
        let size: CGSize? = {
            if let w = dto.width, let h = dto.height {
                return CGSize(width: w, height: h)
            }
            return nil
        }()
        self.init(
            id: dto.id,
            type: MediaKind.from(dto.type),
            mediaUrl: url,
            pixelSize: size,
            duration: dto.duration,
            storagePath: dto.storagePath
        )
    }
}
