//
//  ContentView.swift
//  WeddingTimeline
//
//  Created by 田口友暉 on 2025/07/13.
//

import SwiftUI

struct ContentView: View {
    @Environment(Session.self) private var session
    
    var body: some View {
        TabView {
            Tab("タイムライン", systemImage: "house.fill") {
                TimeLineView()
            }
            
            
            Tab("ベストポスト", systemImage: "trophy.fill") {
                BestPostView()
            }
            
            
            Tab("設定", systemImage: "gearshape.fill") {
                SettingView()
            }
        }
        .environment(session)
    }
}

#Preview {
    ContentView()
}
