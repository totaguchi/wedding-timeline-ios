//
//  PostDetailView.swift
//  WeddingTimeline
//
//  Created by 田口友暉 on 2025/10/22.
//

import SwiftUI

struct PostDetailView: View {
    private struct GalleryPayload: Identifiable {
        let id = UUID()
        let urls: [URL]
        let startIndex: Int
    }

    let model: TimelinePost
    let isMutedByViewer: Bool
    let onToggleLike: (Bool) -> Void
    /// 親（TimelineView / ViewModel）に削除処理を委譲するためのコールバック
    let onPostDelete: (@Sendable (String) async -> Bool)
    /// ミュート状態が変わったら親に通知
    let onMuteChanged: ((String, Bool) -> Void)?
    /// ミュート変更処理を親に委譲
    let onSetMute: (@Sendable (String, Bool) async -> Bool)?
    /// 通報処理を親（ViewModel）に委譲（postId, reason） - 成功時 true を返す
    let onReport: (@Sendable (String, String) async -> Bool)?

    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss

    @State private var showReportDone = false
    @State private var showDeleteConfirm = false
    @State private var isDeleting = false
    @State private var deleteError: String?
    @State private var isMuted = false

    @State private var galleryPayload: GalleryPayload?

    private let reportReasons: [String] = ["スパム/宣伝", "不適切な表現", "プライバシーの侵害", "その他"]

    init(
        model: TimelinePost,
        isMutedByViewer: Bool,
        onToggleLike: @escaping (Bool) -> Void,
        onPostDelete: @escaping (@Sendable (String) async -> Bool),
        onMuteChanged: ((String, Bool) -> Void)? = nil,
        onSetMute: (@Sendable (String, Bool) async -> Bool)? = nil,
        onReport: (@Sendable (String, String) async -> Bool)? = nil
    ) {
        self.model = model
        self.isMutedByViewer = isMutedByViewer
        self.onToggleLike = onToggleLike
        self.onPostDelete = onPostDelete
        self.onMuteChanged = onMuteChanged
        self.onSetMute = onSetMute
        self.onReport = onReport
        _isMuted = State(initialValue: isMutedByViewer)
    }

    private func reportPost(reason: String) {
        guard let onReport else { return }
        Task {
            let ok = await onReport(model.id, reason)
            // 通報成功時のみ完了ダイアログを表示する
            if ok { await MainActor.run { showReportDone = true } }
        }
    }

    @MainActor
    private func toggleMuteUser() {
        guard let onSetMute else { return }
        let next = !isMuted
        Task {
            let ok = await onSetMute(model.authorId, next)
            if ok {
                await MainActor.run {
                    self.isMuted = next
                }
            }
        }
    }

    private func deletePost() {
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
        // UID を SessionStore から取得（FirebaseAuth 非依存）
        let isMine = (session.cachedMember?.uid == model.authorId)

        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                TimelinePostView(
                    model: model,
                    enableNavigation: false,
                    onToggleLike: onToggleLike,
                    onPostDelete: onPostDelete,
                    onImageTap: { urls, startIndex in
                        guard !urls.isEmpty else { return }
                        galleryPayload = GalleryPayload(
                            urls: urls,
                            startIndex: startIndex
                        )
                    }
                )
            }
            .padding()
        }
        .fullScreenCover(item: $galleryPayload) { payload in
            ImageGalleryView(
                urls: payload.urls,
                startIndex: payload.startIndex
            )
        }
        .navigationTitle("ポスト")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Menu("報告する", systemImage: "flag") {
                        ForEach(reportReasons, id: \.self) { reason in
                            Button(reason, role: .destructive) {
                                reportPost(reason: reason)
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
    }
}

#Preview {
//    let model = TimeLinePost()
//    PostDetailView()
}
