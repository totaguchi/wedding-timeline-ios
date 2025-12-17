//
//  LegalView.swift
//  WeddingTimeline
//
//  Created by 田口友暉 on 2025/12/17.
//

import SwiftUI

struct LegalView: View {
    @State private var offlineText: String = Self.defaultOfflineMarkdown

    var body: some View {
        ScrollView {
            Text(offlineText)
                .font(.callout)
                .textSelection(.enabled)
                .padding()
        }
        .navigationTitle("規約・プライバシー（オフライン）")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard offlineText == Self.defaultOfflineMarkdown else { return }
            if let url = Bundle.main.url(forResource: "legal_offline", withExtension: "md"),
               let text = try? String(contentsOf: url) {
                offlineText = text
            }
        }
    }

    // 日付表示用
    static var todayJP: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.timeZone = .current
        f.dateFormat = "yyyy年M月d日"
        return f.string(from: Date())
    }

    static var defaultOfflineMarkdown: String {
        """
        # 利用規約・プライバシーポリシー（オフライン要約）
        最終更新: \(todayJP)

        これは通信できない場合に表示する要約版です。

        ## 利用規約（要点）
        - 本アプリはルーム単位の限定タイムラインを提供します。
        - 匿名認証（Firebase Authentication）でサインインします。表示名には識別のため `@UID先頭4桁` が付く場合があります。
        - ルーム入室には roomId / roomKey が必要です。入室キーの共有は禁止します。
        - 投稿の著作権はユーザーに帰属しますが、アプリ運用上の保存・表示・最適化のための利用を許諾いただきます。
        - 法令違反・権利侵害・不適切コンテンツは削除やアカウント制限の対象となります。

        ## プライバシー（要点）
        - 収集する主な情報：Firebase UID、表示名・アイコン、参加ルームID、投稿、いいね／通報等の操作、技術ログなど。
        - 入室キーは Firestore の `roomSecrets/{roomId}` に保存され、クライアントから直接は読めないルールで保護します。端末ローカルには保存しません（保存する場合はアプリ内で明示）。
        - 利用目的：タイムライン提供、不正防止、品質改善、サポート対応。
        - 第三者提供：Firebase（Auth/Firestore/Storage 等）を利用。法令に基づく場合を除き本人同意なく第三者提供しません。
        - 保存期間：目的達成に必要な期間のみ保持し、不要になった情報は適切に削除・匿名化します。退会はアプリ内から申請可能です。

        ## お問い合わせ
        - 運営者名：田口 友暉（個人開発）
        - 連絡先　：ttaguchidevelop@gmail.com
        """
    }
}
