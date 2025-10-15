//
//  Comment.swift
//  WeddingTimeline
//
//  Created by 田口友暉 on 2025/07/24.
//

import Foundation

struct Comment {
    var id = UUID()
    var userId: Int
    var comment: String
    var createdAt: Date
}
