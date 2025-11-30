//
//  SettingView.swift
//  WeddingTimeline
//
//  Created by 田口友暉 on 2025/07/13.
//

import SwiftUI

struct SettingView: View {
    // Session は signOut() のみ確実に存在する前提で参照
    @Environment(Session.self) var session: Session

    // ナビゲーション先のプレースホルダ表示
    @State private var showProfile = false
    @State private var showNotification = false
    @State private var showPrivacy = false
    @State private var showTheme = false
    @State private var showAbout = false
    @State private var showLogoutAlert = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    profileHeader
                        .padding(.top, 8)

                    // 各セクション
//                    card {
//                        SettingRow(icon: "lock", title: "プライバシー", subtitle: "アカウントの公開範囲を設定") {
//                            showPrivacy = true
//                        }
//                        Divider()
//                        SettingRow(icon: "paintbrush", title: "テーマ設定", subtitle: "アプリの外観をカスタマイズ") {
//                            showTheme = true
//                        }
//                    }

                    card {
                        SettingRow(icon: "info.circle", title: "アプリについて", subtitle: "バージョン情報と利用規約") {
                            showAbout = true
                        }
                    }

                    logoutButton
                        .padding(.top, 8)

                    Text("Version \(appVersion)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 24)
                }
                .padding(.horizontal, 16)
            }
            .navigationTitle("設定")
            .navigationBarTitleDisplayMode(.inline)
            // プレースホルダ遷移先
            .sheet(isPresented: $showProfile) { PlaceholderSheet(title: "プロフィール設定") }
            .sheet(isPresented: $showNotification) { PlaceholderSheet(title: "通知設定") }
            .sheet(isPresented: $showPrivacy) { PlaceholderSheet(title: "プライバシー") }
            .sheet(isPresented: $showTheme) { PlaceholderSheet(title: "テーマ設定") }
            .sheet(isPresented: $showAbout) { PlaceholderSheet(title: "アプリについて") }
            .alert("ログアウトしますか？", isPresented: $showLogoutAlert) {
                Button("キャンセル", role: .cancel) { }
                Button("ログアウト", role: .destructive) {
                    Task { await session.signOut() }
                }
            } message: {
                Text("ロームからログアウトします。よろしいですか？")
            }
        }
    }
}

// MARK: - Subviews
private extension SettingView {
    var profileHeader: some View {
        HStack(spacing: 16) {
            AvatarView(userIcon: session.cachedMember?.userIcon)
                .frame(width: 64, height: 64)

            VStack(alignment: .leading, spacing: 6) {
                Text(session.cachedMember?.username ?? "未設定")
                    .font(.title3.bold())
                    .foregroundStyle(.primary)
                Spacer()
            }
            Spacer()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.pink.opacity(0.22), Color.purple.opacity(0.18)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.pink.opacity(0.12), lineWidth: 1)
        )
    }

    @ViewBuilder
    func card(@ViewBuilder content: () -> some View) -> some View {
        VStack(spacing: 0) { content() }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.background.opacity(0.6))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color(.separator).opacity(0.3), lineWidth: 0.5)
            )
    }

    var logoutButton: some View {
        Button {
            showLogoutAlert = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                    .font(.system(size: 18, weight: .semibold))
                Text("ログアウト")
                    .font(.headline)
            }
            .foregroundStyle(Color.pink)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.pink.opacity(0.35), lineWidth: 1)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.pink.opacity(0.07))
                    )
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 4)
    }
}

// MARK: - Components
private struct SettingRow: View {
    let icon: String
    let title: String
    let subtitle: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.pink.opacity(0.12))
                        .frame(width: 36, height: 36)
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.pink)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
    }
}

private struct AvatarView: View {
    var userIcon: String?

    var body: some View {
        Group {
            if let icon = userIcon {
                Image(icon)
                    .resizable().scaledToFill()
                    .foregroundStyle(.secondary)
            } else {
                Image(systemName: "person.crop.circle.fill")
                    .resizable().scaledToFill()
                    .foregroundStyle(.secondary)
            }
        }
        .clipShape(Circle())
        .overlay(Circle().stroke(Color.white.opacity(0.9), lineWidth: 2))
        .shadow(color: .black.opacity(0.08), radius: 4, x: 0, y: 2)
    }
}

private struct PlaceholderSheet: View {
    let title: String
    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Image(systemName: "hammer")
                    .font(.system(size: 32))
                    .foregroundStyle(.secondary)
                Text("\(title) は準備中です")
                    .foregroundStyle(.secondary)
            }
            .padding()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private extension SettingView {
    var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "-"
        return "\(v)"
    }
}

#Preview {
    SettingView()
}
