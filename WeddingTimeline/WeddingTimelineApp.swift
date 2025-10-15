//
//  WeddingTimelineApp.swift
//  WeddingTimeline
//
//  Created by 田口友暉 on 2025/07/13.
//

import SwiftUI
import FirebaseCore
import FirebaseFirestore
import FirebaseAuth

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // FirebaseApp.configure()
        return true
    }
}

@main
struct WeddingTimelineApp: App {
    @State private var session = Session()
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    
    init() {
        FirebaseApp.configure()
    }

    var body: some Scene {
        WindowGroup {
            if session.isLoggedIn {
                ContentView()          // ← TabView が入っている画面
                    .environment(session)
                // 例：ContentView の .task で
                    .task { await session.bootstrapOnLaunch() }
            } else {
                LoginView()
                    .environment(session)
            }
        }
    }
}
