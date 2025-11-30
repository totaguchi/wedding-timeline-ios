//
//  ActivityView.swift
//  WeddingTimeline
//
//  Created by 田口友暉 on 2025/11/24.
//

import SwiftUI
import UIKit

// MARK: - ShareSheet bridge
struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]
    let applicationActivities: [UIActivity]? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let vc = UIActivityViewController(activityItems: activityItems, applicationActivities: applicationActivities)
        // iPad対策（必要ならソースビューを設定）
        vc.excludedActivityTypes = nil
        return vc
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
