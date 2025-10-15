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
            Tab("Received", systemImage: "tray.and.arrow.down.fill") {
                TimeLineView()
            }
            
            
            Tab("Sent", systemImage: "tray.and.arrow.up.fill") {
                BestPostView()
            }
            
            
            Tab("Account", systemImage: "person.crop.circle.fill") {
                SettingView()
            }
        }
        .environment(session)
    }
}

#Preview {
    ContentView()
}
