//
//  SelectedAttachment.swift
//  WeddingTimeline
//
//  Created by 田口友暉 on 2025/08/25.
//

import SwiftUI
import AVFoundation

struct SelectedAttachment: Identifiable {
    enum Kind { case image(UIImage), video(URL) }
    let id = UUID()
    var kind: Kind
    var thumbnail: UIImage? // 動画プレビュー用
}

extension SelectedAttachment {
    var mediaKind: MediaKind {
        switch kind {
        case .image: return .image
        case .video: return .video
        }
    }
}

extension SelectedAttachment: Hashable {
    static func == (lhs: SelectedAttachment, rhs: SelectedAttachment) -> Bool {
        lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
