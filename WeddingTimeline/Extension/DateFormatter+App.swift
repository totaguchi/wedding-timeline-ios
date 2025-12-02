//
//  DateFormatter+App.swift
//  WeddingTimeline
//
//  Created by 田口友暉 on 2025/12/01.
//

import Foundation

extension DateFormatter {
    static let appCreatedAt: DateFormatter = {
        let df = DateFormatter()
        df.locale = Locale(identifier: "ja_JP")
        df.timeZone = .current
        df.dateFormat = "HH:mm・yyyy/MM/dd"
        return df
    }()
}
