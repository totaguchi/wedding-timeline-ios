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
import Nuke

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        return true
    }
}

@main
struct WeddingTimelineApp: App {
    @State private var session = Session()
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    
    init() {
        FirebaseApp.configure()
        var conf = ImagePipeline.Configuration()
        // ディスクキャッシュ（永続）
        if let dataCache = try? DataCache(name: "ImageDataCache") {
            dataCache.sizeLimit = 200 * 1024 * 1024  // 200MB 目安（bytes）
            conf.dataCache = dataCache               // プロトコル型に代入
        }

        // メモリキャッシュ（必要なら調整。未設定でも用意されます）
        conf.imageCache = ImageCache()

        // レートリミッタは引き続き有効化可（12.x で存続）
        conf.isRateLimiterEnabled = true

        // Nuke 12 では重複ダウンロードの排除は常時有効化に寄ったため、
        // `isDeduplicationEnabled` は削除されています。

        ImagePipeline.shared = ImagePipeline(configuration: conf)
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
