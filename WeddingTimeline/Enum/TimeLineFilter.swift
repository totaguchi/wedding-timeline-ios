//
//  TimeLineFilter.swift
//  WeddingTimeline
//
//  Created by 田口友暉 on 2025/11/03.
//

enum TimeLineFilter: String, CaseIterable, Identifiable, Sendable {
    case all = "すべて"
    case ceremony = "挙式"
    case reception = "披露宴"
    

    var id: String { rawValue }
    var icon: String {
        switch self {
        case .all: return "arrow.triangle.2.circlepath"
        case .ceremony: return "heart"
        case .reception: return "person.crop.circle.badge.checkmark"
        }
    }
}

