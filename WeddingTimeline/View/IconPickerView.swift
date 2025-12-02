//
//  IconPickerView.swift
//  WeddingTimeline
//
//  Created by 田口友暉 on 2025/11/30.
//

import SwiftUI

struct IconPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedIcon: String?
    let icons: [String]

    private let cols = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        ZStack {
            // 背景カード感（シート上に白カード）
            Color.clear.ignoresSafeArea()

            VStack(spacing: 16) {
                // Header
                HStack(alignment: .center) {
                    HStack(spacing: 8) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .foregroundStyle(TLColor.icoCategoryPink)
                        Text("アバターを選択")
                            .font(.title3).bold()
                    }
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(TLColor.textMeta)
                            .padding(8)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("閉じる")
                }

                Text("お好きなアバターを選んでください")
                    .font(.subheadline)
                    .foregroundStyle(TLColor.textMeta)
                    .frame(maxWidth: .infinity, alignment: .leading)

                ScrollView {
                    LazyVGrid(columns: cols, spacing: 20) {
                        ForEach(icons, id: \.self) { icon in
                            avatarCell(icon)
                        }
                    }
                    .padding(.top, 8)
                }
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(TLColor.bgCard)
                    .shadow(color: .black.opacity(0.06), radius: 16, y: 6)
            )
            .padding(.horizontal)
        }
    }

    @ViewBuilder
    private func avatarCell(_ icon: String) -> some View {
        let isSelected = (selectedIcon == icon)

        Button {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
                selectedIcon = icon
            }
            dismiss()
        } label: {
            // 中央の丸アイコン
            VStack(alignment: .center) {
                Image(icon)
                    .resizable()
                    .scaledToFill()
                    .padding(5)
                    .frame(width: 60, height: 60)
                    .clipShape(Circle())
                    .shadow(color: .black.opacity(0.08), radius: 8, y: 3)
                    .overlay(
                        Circle()
                            .strokeBorder(isSelected ? TLColor.btnCategorySelTo : AppColor.white, lineWidth: 2)
                    )
                
                if isSelected {
                    HStack(spacing: 6) {
                        Image(systemName: "heart.fill").foregroundStyle(TLColor.fillPink500)
                        Text("選択中").font(.caption2).bold().foregroundStyle(TLColor.fillPink500)
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(AppColor.white)
                            .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
                    )
                    .padding(8)
                } else {
                    Spacer()
                }
            }
            .frame(height: 120)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .shadow(color: .black.opacity(0.04), radius: 6, y: 2)
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(isSelected ? TLColor.btnCategorySelTo : TLColor.borderCard.opacity(0.25), lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    let icons = [
        "oomimigitsune", "lesser_panda", "bear",
        "todo", "musasabi", "rakko"
    ]
    return IconPickerView(selectedIcon: .constant("lesser_panda"), icons: icons)
        .padding()
        .background(LinearGradient(colors: [TLColor.btnCategorySelFrom.opacity(0.15), TLColor.icoCategoryPurple.opacity(0.12)], startPoint: .top, endPoint: .bottom))
}
