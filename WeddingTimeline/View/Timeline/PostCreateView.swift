//
//  PostCreateView.swift
//  WeddingTimeline
//
//  Created by 田口友暉 on 2025/08/24.
//

import SwiftUI
import PhotosUI
import AVKit

struct PostCreateView: View {
    // MARK: - Properties
    
    @Environment(\.dismiss) private var dismiss
    @Environment(Session.self) private var session
    @State private var viewModel: PostCreateViewModel
    
    // MARK: - Initialization
    
    /// - Parameter roomId: 投稿先の Room ID
    init(roomId: String) {
        _viewModel = State(wrappedValue: PostCreateViewModel(roomId: roomId))
    }
    
    // MARK: - Body
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // 本文入力
                    textInputSection
                    
                    // カテゴリタグ選択
                    tagPickerSection
                    
                    // 添付メディア
                    attachmentsGridSection
                    
                    Spacer(minLength: 100)
                }
                .padding(.top)
            }
            .navigationTitle("新規投稿")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task {
                            if try await viewModel.submit(authorName: session.cachedMember?.username ?? "", userIcon: session.cachedMember?.userIcon ?? "") {
                                dismiss()
                            }
                        }
                    } label: {
                        if viewModel.isSubmitting {
                            ProgressView()
                        } else {
                            Text("投稿")
                                .bold()
                        }
                    }
                    .disabled(!viewModel.canSubmit)
                }
                
                ToolbarItem(placement: .bottomBar) {
                    PhotosPicker(
                        selection: $viewModel.selectedItems,
                        maxSelectionCount: 4,
                        matching: .any(of: [.images, .videos])
                    ) {
                        Label("メディアを追加", systemImage: "photo.on.rectangle.angled")
                    }
                    .disabled(viewModel.attachments.count >= 4)
                }
            }
            .alert("エラー", isPresented: .constant(viewModel.errorMessage != nil)) {
                Button("OK") {
                    viewModel.errorMessage = nil
                }
            } message: {
                if let message = viewModel.errorMessage {
                    Text(message)
                }
            }
        }
        .task {
            await viewModel.initialize()
        }
    }
    
    // MARK: - Sections
    
    /// 本文入力エリア
    @ViewBuilder private var textInputSection: some View {
        TextEditor(text: $viewModel.text)
            .frame(minHeight: 120)
            .padding(8)
            .background(Color(.systemGray6))
            .cornerRadius(8)
            .padding(.horizontal)
            .overlay(alignment: .topLeading) {
                if viewModel.text.isEmpty {
                    Text("今何してる？")
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 16)
                        .allowsHitTesting(false)
                }
            }
    }
    
    /// カテゴリタグ選択（セグメント）
    @ViewBuilder private var tagPickerSection: some View {
        HStack {
            Text("カテゴリ")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            Spacer()
            
            Picker("", selection: $viewModel.selectedTag) {
                ForEach(PostTag.selectableCases) { tag in
                    Label(tag.displayName, systemImage: tag.icon)
                        .tag(tag)
                }
            }
            .pickerStyle(.segmented)
        }
        .padding(.horizontal)
    }
    
    /// 添付メディアのグリッド表示
    @ViewBuilder private var attachmentsGridSection: some View {
        if !viewModel.attachments.isEmpty && !viewModel.loadingPickerItem {
            AttachmentGrid(
                attachments: $viewModel.attachments,
                onRemove: viewModel.removeAttachment
            )
            .animation(.default, value: viewModel.attachments)
            .padding(.horizontal)
        } else if viewModel.loadingPickerItem {
            HStack {
                ShimmerPlaceholder()
                    .frame(width: 100, height: 100)
                Spacer()
            }
            .padding(.horizontal)
        }
    }
}

// MARK: - AttachmentGrid

/// 添付メディアのグリッド表示（最大4枚）
private struct AttachmentGrid: View {
    @Binding var attachments: [SelectedAttachment]
    let onRemove: (SelectedAttachment) -> Void
    
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)
    
    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(attachments) { att in
                ZStack {
                    if att.isLoading {
                        // 読み込み中
                        ShimmerPlaceholder(cornerRadius: 10)
                        ProgressView()
                            .tint(.white)
                    } else {
                        // 読み込み完了
                        attachmentThumbnail(att)
                    }
                }
                .frame(width: 100, height: 100)
                .cornerRadius(10)
                .overlay(alignment: .topTrailing) {
                    if !att.isLoading {
                        Button {
                            onRemove(att)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title3)
                                .foregroundStyle(.white)
                                .background(Circle().fill(.black.opacity(0.5)))
                        }
                        .padding(4)
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private func attachmentThumbnail(_ att: SelectedAttachment) -> some View {
        switch att.kind {
        case .image(let img):
            Image(uiImage: img)
                .resizable()
                .scaledToFill()
                .frame(width: 100, height: 100)
                .clipped()
        case .video:
            if let thumb = att.thumbnail {
                ZStack {
                    Image(uiImage: thumb)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 100, height: 100)
                        .clipped()
                    
                    Image(systemName: "play.circle.fill")
                        .font(.largeTitle)
                        .foregroundStyle(.white)
                        .shadow(radius: 4)
                }
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .overlay {
                        Image(systemName: "video")
                            .foregroundStyle(.secondary)
                    }
            }
        case .none:
            EmptyView()
        }
    }
}

// MARK: - Preview

#Preview("投稿作成画面") {
    PostCreateView(roomId: "1234")
}
