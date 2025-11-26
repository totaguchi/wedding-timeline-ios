//
//  PostTag.swift
//  WeddingTimeline
//
//  Created by 田口友暉 on 2025/11/04.
//

enum PostTag: String, Codable, CaseIterable, Identifiable, Sendable {
    case ceremony     // 挙式
    case reception    // 披露宴
    case unknown      // 不明（古いデータ互換用、UI 選択肢には含まない）

    var id: String { rawValue }

    /// UI 表示用のラベル（国際化対応可能な形式）
    var displayName: String {
        switch self {
        case .ceremony:  return "挙式"
        case .reception: return "披露宴"
        case .unknown:   return ""
        }
    }

    /// SF Symbol アイコン名（投稿作成 UI で使用）
    var icon: String {
        switch self {
        case .ceremony:  return "heart"
        case .reception: return "fork.knife"
        case .unknown:   return "questionmark.circle"
        }
    }

    /// Firestore に保存する際の文字列（`rawValue` と同値だが、明示的に提供）
    var firestoreValue: String {
        rawValue
    }

    // MARK: - UI Selection

    /// 投稿作成時の選択肢（`unknown` を除外）
    static var selectableCases: [PostTag] {
        [.ceremony, .reception]
    }
}
