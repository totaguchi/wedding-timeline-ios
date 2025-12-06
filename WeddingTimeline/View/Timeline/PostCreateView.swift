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
    @FocusState var textEditorFocus: Bool
    
    // MARK: - Initialization
    
    /// - Parameter roomId: 投稿先の Room ID
    init(roomId: String) {
        _viewModel = State(wrappedValue: PostCreateViewModel(roomId: roomId))
    }
    
    // MARK: - Body
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                headerBar
                ScrollView {
                    VStack(spacing: 16) {
                        // 本文入力
                        textInputSection
                        // カテゴリタグ選択
                        tagPickerSection
                        // 添付メディア
                        attachmentsGridSection
                        Spacer(minLength: 120)
                    }
                    .padding(.top, 8)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        textEditorFocus = false
                    }
                }
                .scrollDismissesKeyboard(.immediately)
            }
            .toolbar(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("閉じる") {
                        textEditorFocus = false
                    }
                }
            }
            .background(
                LinearGradient(colors: [TLColor.bgGradientStart, TLColor.bgGradientEnd],
                               startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()
            )
            .safeAreaInset(edge: .bottom) {
                bottomBar
            }
            .alert("エラー", isPresented: .constant(viewModel.errorMessage != nil)) {
                Button("OK") { viewModel.errorMessage = nil }
            } message: {
                if let message = viewModel.errorMessage { Text(message) }
            }
        }
        .task { await viewModel.initialize() }
    }
    
    // MARK: - Sections
    
    /// 本文入力エリア
    @ViewBuilder private var textInputSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topLeading) {
                TextEditor(text: $viewModel.text)
                    .frame(minHeight: 120)
                    .padding(8)
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
                    .focused($textEditorFocus)
                
                if viewModel.text.isEmpty {
                    Text("今の気持ちを共有しましょう…")
                        .foregroundStyle(TLColor.textMeta)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .allowsHitTesting(false)
                }
            }
            
            // Compose toolbar row (X/Twitter-like)
            HStack(spacing: 12) {
                PhotosPicker(
                    selection: $viewModel.selectedItems,
                    maxSelectionCount: 4,
                    matching: .any(of: [.images, .videos])
                ) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .imageScale(.large)
                        .padding(8)
                        .background(
                            RoundedRectangle(cornerRadius: 10).fill(TLColor.bgCard)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(AppColor.gray400.opacity(0.35), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .foregroundStyle(TLColor.textMeta)
                .disabled(viewModel.attachments.count >= 4)
                .opacity(viewModel.attachments.count >= 4 ? 0.4 : 1.0)
                
                Spacer()
            }
            .padding(.top, 2)
        }
        .padding(.horizontal)
    }
    
    /// カテゴリタグ選択（セグメント）
    @ViewBuilder private var tagPickerSection: some View {
        HStack {
            Text("カテゴリ")
                .font(.subheadline)
                .foregroundStyle(TLColor.textMeta)
            
            Spacer()
            
            TagSegmented(selection: $viewModel.selectedTag, tags: PostTag.selectableCases)
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
    
    // MARK: - Header / BottomBar
    @ViewBuilder private var headerBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkles")
                .foregroundStyle(TLColor.icoSparkles)
            Text("新規投稿")
                .font(.headline)
                .foregroundStyle(TLColor.textTitlePink)
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.headline)
                    .padding(8)
                    .background(Circle().fill(TLColor.bgCard))
                    .foregroundStyle(TLColor.textMeta)
            }
            .accessibilityLabel("閉じる")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(TLColor.bgHeader) // white/80
    }
    
    @ViewBuilder private var bottomBar: some View {
        HStack(spacing: 12) {
            Button{
                submitAction()
            } label: {
                HStack(spacing: 8) {
                    viewModel.isSubmitting ? AnyView(ProgressView().tint(.white)) :
                                             AnyView(Image(systemName: "paperplane.fill"))
                    Text("投稿する").bold()
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryActionButtonStyle())
            .disabled(!viewModel.canSubmit || viewModel.isSubmitting)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }
    
    struct PrimaryActionButtonStyle: ButtonStyle {
      @Environment(\.isEnabled) private var isEnabled

      func makeBody(configuration: Configuration) -> some View {
        configuration.label
          .padding(.horizontal, 14).padding(.vertical, 10)
          .frame(height: 44)
          .background(
            RoundedRectangle(cornerRadius: 14).fill(
              isEnabled ?
              AnyShapeStyle(LinearGradient(colors: [TLColor.fabFrom, TLColor.fabTo],
                                                       startPoint: .leading, endPoint: .trailing)) :
                AnyShapeStyle(AppColor.gray400.opacity(0.35))
            )
          )
          .foregroundStyle(isEnabled ? TLColor.icoWhite : TLColor.textMeta)
          .opacity(configuration.isPressed ? 0.9 : 1)
          .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
      }
    }
    
    private func submitAction() {
        Task {
            if try await viewModel.submit(authorName: session.cachedMember?.username ?? "",
                                          userIcon: session.cachedMember?.userIcon ?? "") {
                dismiss()
            }
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
                            .tint(TLColor.icoWhite)
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
                                .foregroundStyle(TLColor.icoWhite)
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
                        .foregroundStyle(TLColor.icoWhite)
                        .shadow(radius: 4)
                }
            } else {
                Rectangle()
                    .fill(AppColor.gray400.opacity(0.3))
                    .overlay {
                        Image(systemName: "video")
                            .foregroundStyle(TLColor.textMeta)
                    }
            }
        case .none:
            EmptyView()
        }
    }
}

// MARK: - Custom Segmented (Icon + Text)
private struct TagSegmented: View {
    @Binding var selection: PostTag
    let tags: [PostTag]
    
    var body: some View {
        HStack(spacing: 6) {
            ForEach(tags) { tag in
                let isSelected = selection == tag
                Button {
                    selection = tag
                } label: {
                    TagPill(tag: tag, isSelected: isSelected)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(tag.displayName))
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(4)
        // Segmented の台座（標準 Picker 風の外枠＋淡い背景）
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(TLColor.bgCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(AppColor.gray400.opacity(0.35), lineWidth: 1)
        )
        .animation(.easeInOut(duration: 0.15), value: selection)
    }
}

/// ピル状のセグメント。選択時はタグ別カラーで塗りつぶし、非選択は透明（Picker風）。
private struct TagPill: View {
    let tag: PostTag
    let isSelected: Bool
    
    var body: some View {
        let isCeremony = tag == .ceremony
        let bgColor = isCeremony ? TLColor.badgeCeremonyBg : TLColor.badgeReceptionBg
        let textColor = isCeremony ? TLColor.badgeCeremonyText : TLColor.badgeReceptionText
        // Picker 風にするため、個別の内側ボーダーは付けず、外枠は親側で描画
        
        return HStack(spacing: 6) {
            Image(systemName: tag.icon)
                .imageScale(.medium)
            Text(tag.displayName)
                .font(.subheadline)
                .fontWeight(.semibold)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(minHeight: 32)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isSelected ? bgColor : .clear)
        )
        .foregroundStyle(isSelected ? textColor : TLColor.textMeta)
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Preview

#Preview("投稿作成画面") {
    PostCreateView(roomId: "1234")
}
