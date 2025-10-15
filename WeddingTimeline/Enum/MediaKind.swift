//
//  MediaType.swift
//  WeddingTimeline
//
//  Created by 田口友暉 on 2025/07/13.
//

import Foundation

enum MediaKind: String, Codable {
    case image
    case video
    case unknown
    
    static func from(_ string: String?) -> MediaKind {
        guard let lowercased = string?.lowercased() else { return .unknown }
        return MediaKind(rawValue: lowercased) ?? .unknown
    }
    
    var rawString: String {
        return self.rawValue
    }
}
