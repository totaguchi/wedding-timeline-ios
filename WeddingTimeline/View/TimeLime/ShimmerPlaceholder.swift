//
//  ShimmerPlaceholder.swift
//  WeddingTimeline
//
//  Created by 田口友暉 on 2025/11/26.
//

import SwiftUI

struct ShimmerPlaceholder: View {
    /// 角丸の半径（画像: 10pt、グリッド: 6pt など用途に応じて変更可能）
    var cornerRadius: CGFloat = 10

    /// シマーバンドの水平位置（-1: 左端外 → 1: 右端外）
    @State private var move: CGFloat = -1

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let bandW = max(80, w * 0.55)

            // グラデーション定義（淡いグレー → 明るめグレー → 淡いグレー）
            let gradient = LinearGradient(
                colors: [
                    Color.gray.opacity(0.18),
                    Color.gray.opacity(0.32),
                    Color.gray.opacity(0.18)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )

            ZStack {
                // ベースのスケルトンプレート
                Rectangle()
                    .fill(Color.gray.opacity(0.16))

                // 移動するハイライトバンド
                Rectangle()
                    .fill(gradient)
                    .frame(width: bandW, height: h)
                    .offset(x: move * (w + bandW))
            }
            .cornerRadius(cornerRadius)
            .clipped()
            .onAppear {
                // 初期位置: 左端外
                move = -1
                // 連続アニメーション（左 → 右へ無限リピート）
                withAnimation(.linear(duration: 1.1).repeatForever(autoreverses: false)) {
                    move = 1
                }
            }
        }
    }
}

// MARK: - Preview

#Preview("画像プレースホルダー") {
    VStack(spacing: 16) {
        // 単一画像用（角丸 10pt）
        ShimmerPlaceholder()
            .frame(height: 180)

        // グリッド用（角丸 6pt）
        HStack(spacing: 4) {
            ShimmerPlaceholder(cornerRadius: 6)
                .frame(width: 100, height: 100)
            ShimmerPlaceholder(cornerRadius: 6)
                .frame(width: 100, height: 100)
        }
    }
    .padding()
}
