//
//  PostDetailView.swift
//  WeddingTimeline
//
//  Created by 田口友暉 on 2025/10/22.
//

import SwiftUI

struct PostDetailView: View {
    let model: TimelinePost
    let onToggleLike: (Bool) -> Void
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                TimelinePostView(model: model, enableNavigation: false, onToggleLike: onToggleLike)
            }
            .padding()
        }
        .navigationTitle("ポスト")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
//    let model = TimeLinePost()
//    PostDetailView()
}
