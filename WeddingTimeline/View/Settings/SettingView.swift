//
//  SettingView.swift
//  WeddingTimeline
//
//  Created by 田口友暉 on 2025/07/13.
//

import SwiftUI
import SafariServices
import Network

struct SettingView: View {
    // Session は signOut() のみ確実に存在する前提で参照
    @Environment(Session.self) var session: Session

    @State private var showLogoutAlert = false
    @State private var showDeleteAlert = false
    @State private var isDeleting = false
    @State private var deleteError: String?

    private let legalOnlineURL = URL(string: "https://weddingtimeline-d67a6.web.app/legal.html")! // 統合版（オンライン）

    @State private var showLegalSafari = false
    @State private var showLegalOffline = false
    @State private var isCheckingLegalRoute = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    profileHeader
                        .padding(.top, 8)

                    // 各セクション
                    card {
                        NavigationLink {
                            AboutView()
                        } label: {
                            SettingRowLabel(icon: "info.circle", title: "アプリについて", subtitle: "バージョン情報")
                        }
                        .buttonStyle(.plain)
                    }

                    card {
                        Button {
                            guard !isCheckingLegalRoute else { return }
                            isCheckingLegalRoute = true
                            Task {
                                let online = await Self.isOnline()
                                await MainActor.run {
                                    isCheckingLegalRoute = false
                                    if online {
                                        showLegalSafari = true
                                    } else {
                                        showLegalOffline = true
                                    }
                                }
                            }
                        } label: {
                            SettingRowLabel(icon: "doc.text", title: "規約・プライバシー", subtitle: "ポリシーと利用条件")
                        }
                        .buttonStyle(.plain)
                        .contentShape(Rectangle())
                    }

                    logoutButton
                        .padding(.top, 8)

                    deleteAccountButton
                        .padding(.top, 4)

                    Text("Version \(appVersion)")
                        .font(.footnote)
                        .foregroundStyle(TLColor.textMeta)
                        .padding(.bottom, 24)
                }
                .padding(.horizontal, 16)
            }
            .navigationTitle("設定")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showLegalSafari) {
                SafariSheetView(url: legalOnlineURL)
                    .ignoresSafeArea()
            }
            .navigationDestination(isPresented: $showLegalOffline) {
                LegalView()
            }
            .alert("ログアウトしますか？", isPresented: $showLogoutAlert) {
                Button("キャンセル", role: .cancel) { }
                Button("ログアウト", role: .destructive) {
                    Task { await session.signOut() }
                }
            } message: {
                Text("ルームからログアウトします。よろしいですか？")
            }
            .alert("アカウントを削除しますか？", isPresented: $showDeleteAlert) {
                Button("キャンセル", role: .cancel) { }
                Button("削除する", role: .destructive) {
                    Task {
                        await performAccountDeletion()
                    }
                }
            } message: {
                Text("あなたの投稿・プロフィール・いいね等の関連データが削除され、復元できません。よろしいですか？")
            }
            .alert("削除に失敗しました", isPresented: .init(
                get: { deleteError != nil },
                set: { if !$0 { deleteError = nil } }
            )) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(deleteError ?? "不明なエラー")
            }
            .overlay {
                if isDeleting {
                    ZStack {
                        Color.black.opacity(0.2).ignoresSafeArea()
                        VStack(spacing: 12) {
                            ProgressView()
                            Text("削除しています…")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .padding(16)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(.regularMaterial)
                        )
                    }
                }
                if isCheckingLegalRoute {
                    ZStack {
                        Color.black.opacity(0.2).ignoresSafeArea()
                        VStack(spacing: 12) {
                            ProgressView()
                            Text("確認しています…")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .padding(16)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(.regularMaterial)
                        )
                    }
                }
            }
        }
    }
}

// MARK: - Subviews
private extension SettingView {
    var deleteAccountButton: some View {
        Button {
            showDeleteAlert = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "person.crop.circle.badge.xmark")
                    .font(.system(size: 18, weight: .semibold))
                Text("アカウント削除")
                    .font(.headline)
            }
            .foregroundStyle(TLColor.textDeleteTitle)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(TLColor.textDeleteTitle.opacity(0.35), lineWidth: 1)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(TLColor.textDeleteTitle.opacity(0.07))
                    )
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 4)
    }

    var profileHeader: some View {
        HStack(spacing: 16) {
            AvatarView(userIcon: session.cachedMember?.userIcon)
                .frame(width: 64, height: 64)

            VStack(alignment: .leading, spacing: 6) {
                if let uid = session.cachedMember?.uid,
                   let username = session.cachedMember?.username {
                    let tag = DisplayTag.make(roomId: session.currentRoomId, uid: uid)
                    HStack(spacing: 0) {
                        Text(username)
                            .font(.title3.bold())
                            .foregroundStyle(TLColor.textAuthor)
                        Text(" \(tag)")
                            .font(.caption)
                            .foregroundStyle(TLColor.textMeta)
                    }
                } else {
                    Text("未設定")
                        .font(.title3.bold())
                        .foregroundStyle(TLColor.textBody)
                }

                Spacer()
            }
            Spacer()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [TLColor.btnCategorySelFrom.opacity(0.22), TLColor.icoCategoryPurple.opacity(0.18)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(TLColor.borderCard.opacity(0.12), lineWidth: 1)
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
            .foregroundStyle(TLColor.fillPink500)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(TLColor.btnCategorySelFrom.opacity(0.35), lineWidth: 1)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(TLColor.btnCategorySelFrom.opacity(0.07))
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
                        .fill(TLColor.btnCategorySelFrom.opacity(0.12))
                        .frame(width: 36, height: 36)
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(TLColor.icoCategoryPink)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .foregroundStyle(TLColor.textBody)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(TLColor.textMeta)
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

private struct SettingRowLabel: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(TLColor.btnCategorySelFrom.opacity(0.12))
                    .frame(width: 36, height: 36)
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(TLColor.icoCategoryPink)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .foregroundStyle(TLColor.textBody)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(TLColor.textMeta)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 10)
    }
}

private struct AvatarView: View {
    var userIcon: String?

    var body: some View {
        Group {
            if let icon = userIcon {
                Image(icon)
                    .resizable()
                    .scaledToFill()
                    .foregroundStyle(TLColor.textMeta)
            } else {
                Image(systemName: "person.crop.circle.fill")
                    .resizable()
                    .scaledToFill()
                    .foregroundStyle(TLColor.textMeta)
            }
        }
        .clipShape(Circle())
        .overlay(Circle().stroke(AppColor.white.opacity(0.9), lineWidth: 2))
        .shadow(color: .black.opacity(0.08), radius: 4, x: 0, y: 2)
    }
}

private struct AboutView: View {
    var body: some View {
        List {
            Section("アプリ") {
                HStack {
                    Text("アプリ名")
                    Spacer()
                    Text("WeddingTimeline")
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("バージョン")
                    Spacer()
                    Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "-")
                        .foregroundStyle(.secondary)
                }
            }

            Section("説明") {
                Text("結婚式の思い出をみんなで共有する、参列者向けのタイムラインアプリです。")
            }
        }
        .navigationTitle("アプリについて")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct PlaceholderSheet: View {
    let title: String
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "hammer")
                .font(.system(size: 32))
                .foregroundStyle(TLColor.textMeta)
            Text("\(title) は準備中です")
                .foregroundStyle(TLColor.textMeta)
        }
        .padding()
    }
}

private extension SettingView {
    var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "-"
        return "\(v)"
    }

    @MainActor
    func performAccountDeletion() async {
        isDeleting = true
        defer { isDeleting = false }
        do {
            // 実運用では Session 側で Firestore/Storage のユーザーデータ削除を実装してください。
            try await session.deleteAccount()
        } catch {
            deleteError = error.localizedDescription
        }
    }

    static func isOnline() async -> Bool {
        await withCheckedContinuation { continuation in
            let monitor = NWPathMonitor()
            let queue = DispatchQueue(label: "WeddingTimeline.NetworkReachability")
            monitor.pathUpdateHandler = { path in
                monitor.cancel()
                continuation.resume(returning: path.status == .satisfied)
            }
            monitor.start(queue: queue)
        }
    }
}

private struct SafariSheetView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {
        // no-op
    }
}

#Preview {
    SettingView()
}
