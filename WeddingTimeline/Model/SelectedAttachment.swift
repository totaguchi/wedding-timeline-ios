//
//  SelectedAttachment.swift
//  WeddingTimeline
//
//  Created by 田口友暉 on 2025/08/25.
//

import SwiftUI
import AVFoundation

struct SelectedAttachment: Identifiable {
    /// メディアの種類（画像または動画）
    enum Kind {
        case image(UIImage)
        case video(URL)
    }
    
    let id = UUID()
    
    /// メディアの種類（Optional: 読み込み中プレースホルダー用）
    var kind: Kind?
    
    /// 動画プレビュー用サムネイル
    var thumbnail: UIImage?
    
    /// 読み込み中フラグ（プレースホルダー表示用）
    var isLoading: Bool = false
}

extension SelectedAttachment {
    /// MediaKind への変換（Firestore 保存用）
    var mediaKind: MediaKind {
        switch kind {
        case .image: return .image
        case .video: return .video
        case .none: return .image  // Fallback（通常は発生しない）
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
