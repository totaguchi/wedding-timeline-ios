//
//  PostDetailView.swift
//  WeddingTimeline
//
//  Created by 田口友暉 on 2025/10/22.
//

import SwiftUI
import FirebaseAuth

struct PostDetailView: View {
    let model: TimelinePost
    let onToggleLike: (Bool) -> Void
    /// 親（TimelineView / ViewModel）に削除処理を委譲するためのコールバック（省略可）
    /// - Returns: 成功したら true
    let onPostDelete: (@Sendable (String) async -> Bool)
    /// ミュート状態が変わったら親に通知（省略可）
    let onMuteChanged: ((String, Bool) -> Void)?

    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss

    @State private var showReportDone = false
    @State private var showDeleteConfirm = false
    @State private var isDeleting = false
    @State private var deleteError: String?
    @State private var isMuted = false

    private let reportReasons: [String] = ["スパム/宣伝", "不適切な表現", "プライバシーの侵害", "その他"]
    private let postRepo = PostRepository()

    private func reportToFirestore(reason: String) {
        guard let uid = Auth.auth().currentUser?.uid else {
            print("[Report] not signed in")
            return
        }
        guard !session.currentRoomId.isEmpty else {
            print("[Report] roomId not found in session")
            return
        }
        Task {
            do {
                try await postRepo.reportPost(roomId: session.currentRoomId, postId: model.id, reason: reason, reporterUid: uid)
                await MainActor.run { showReportDone = true }
            } catch {
                print("[Report] failed:", error)
            }
        }
    }
    
    @MainActor
    private func loadMuteState() {
        guard let uid = Auth.auth().currentUser?.uid, !session.currentRoomId.isEmpty else { return }
        Task {
            do {
                let muted = try await postRepo.isMuted(roomId: session.currentRoomId, targetUid: model.authorId, by: uid)
                await MainActor.run { self.isMuted = muted }
            } catch {
                print("[Mute] check failed:", error)
            }
        }
    }
    
    @MainActor
    private func toggleMuteUser() {
        guard let uid = Auth.auth().currentUser?.uid, !session.currentRoomId.isEmpty else { return }
        let next = !isMuted
        Task {
            do {
                try await postRepo.setMute(roomId: session.currentRoomId, targetUid: model.authorId, by: uid, mute: next)
                await MainActor.run {
                    self.isMuted = next
                    onMuteChanged?(model.authorId, next)
                }
            } catch {
                print("[Mute] set failed:", error)
            }
        }
    }

    private func deletePost() {
        // 1) コールバックが提供されていれば、まずはそれを使う（UI層は依頼だけに徹する）
        isDeleting = true
        Task {
            let result = await onPostDelete(model.id)
            await MainActor.run {
                isDeleting = false
                if result {
                    dismiss()
                } else {
                    deleteError = "削除に失敗しました。時間をおいて再度お試しください。"
                }
            }
        }
    }

    var body: some View {
        let isMine = (Auth.auth().currentUser?.uid == model.authorId)

        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                TimelinePostView(model: model, enableNavigation: false, onToggleLike: onToggleLike, onPostDelete: onPostDelete)
            }
            .padding()
        }
        .navigationTitle("ポスト")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Menu("報告する", systemImage: "flag") {
                        ForEach(reportReasons, id: \.self) { reason in
                            Button(reason, role: .destructive) {
                                reportToFirestore(reason: reason)
                            }
                        }
                    }
                    Button {
                        toggleMuteUser()
                    } label: {
                        if isMuted {
                            Label("ミュートを解除", systemImage: "speaker.wave.2.fill")
                        } else {
                            Label("このユーザーをミュート", systemImage: "speaker.slash.fill")
                        }
                    }
                    if isMine {
                        Button(role: .destructive) {
                            showDeleteConfirm = true
                        } label: {
                            Label("削除する", systemImage: "trash")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .imageScale(.large)
                }
                .accessibilityLabel("その他メニュー")
            }
        }
        .alert("報告を送信しました", isPresented: $showReportDone) {
            Button("OK", role: .cancel) { }
        }
        .alert("このポストを削除しますか？", isPresented: $showDeleteConfirm) {
            Button("キャンセル", role: .cancel) { }
            Button("削除する", role: .destructive) { deletePost() }
        } message: {
            Text("削除すると元に戻せません。よろしいですか？")
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
                        Text("削除しています…").font(.footnote).foregroundStyle(.secondary)
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(.regularMaterial)
                    )
                }
            }
        }
        .task {
            loadMuteState()
        }
    }
}

#Preview {
//    let model = TimeLinePost()
//    PostDetailView()
}
