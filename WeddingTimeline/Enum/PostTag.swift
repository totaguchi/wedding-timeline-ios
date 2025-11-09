//
//  PostTag.swift
//  WeddingTimeline
//
//  Created by 田口友暉 on 2025/11/04.
//

enum PostTag: String, Codable, CaseIterable, Sendable {
    case ceremony     // 挙式
    case reception    // 披露宴
    case unknown

    var displayName: String {
        switch self {
        case .ceremony: return "挙式"
        case .reception: return "披露宴"
        case .unknown:  return ""
        }
    }
}
