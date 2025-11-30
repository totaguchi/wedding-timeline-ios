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
        if #available(iOS 18.0, *) {
            // iOS 18+ の新しい Tab API
            modernTabView
        } else {
            // iOS 17 互換の TabView
            legacyTabView
        }
    }
    
    // MARK: - iOS 18+ Tab API
    
    @available(iOS 18.0, *)
    @ViewBuilder
    private var modernTabView: some View {
        TabView {
            Tab("タイムライン", systemImage: "house.fill") {
                TimelineView()
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
    
    // MARK: - iOS 17 互換 TabView
    
    @ViewBuilder
    private var legacyTabView: some View {
        TabView {
            TimelineView()
                .tabItem {
                    Label("タイムライン", systemImage: "house.fill")
                }
            
            BestPostView()
                .tabItem {
                    Label("ベストポスト", systemImage: "trophy.fill")
                }
            
            SettingView()
                .tabItem {
                    Label("設定", systemImage: "gearshape.fill")
                }
        }
        .environment(session)
    }
}

#Preview("iOS 17 互換") {
    ContentView()
        .environment(Session())
}

#Preview {
    ContentView()
}
