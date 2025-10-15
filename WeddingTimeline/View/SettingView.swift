//
//  SettingView.swift
//  WeddingTimeline
//
//  Created by 田口友暉 on 2025/07/13.
//

import SwiftUI

struct SettingView: View {
    @Environment(Session.self) var session: Session

    var body: some View {
        Button("ログアウト") {
            Task {
                await session.signOut()
            }
        }
    }
}

#Preview {
    SettingView()
}
