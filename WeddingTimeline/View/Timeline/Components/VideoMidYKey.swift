//
//  VideoMidYKey.swift
//  WeddingTimeline
//
//  Created by Codex on 2026/02/21.
//

import SwiftUI

/// TimelineScroll 空間での動画セル中心Y座標を集約する PreferenceKey。
/// キーは postId、値は各セルの midY。
/// TimelineView 側で最も中央に近い動画を決めるために使う。
struct VideoMidYKey: PreferenceKey {
    static var defaultValue: [String: CGFloat] = [:]

    static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}
