//
//  VideoMidYKey.swift
//  WeddingTimeline
//
//  Created by Codex on 2026/02/21.
//

import SwiftUI

struct VideoMidYKey: PreferenceKey {
    static var defaultValue: [String: CGFloat] = [:]

    static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}
