//
//  Color+App.swift
//  WeddingTimeline
//
//  Created by 田口友暉 on 2025/12/03.
//

import SwiftUI

// MARK: - Base Tokens (Colors.xcassets の生色を参照)
public enum AppColor {
    // White
    public static let white    = Color("AppWhite")
    public static let whiteA80 = Color("AppWhiteA80") // 80% 透過

    // Pink scale
    public static let pink50   = Color("AppPink50")   // #fdf2f8
    public static let pink100  = Color("AppPink100")  // #fce7f3
    public static let pink200  = Color("AppPink200")  // #fbcfe8
    public static let pink400  = Color("AppPink400")  // #f472b6
    public static let pink500  = Color("AppPink500")  // #ec4899
    public static let pink600  = Color("AppPink600")  // #db2777

    // Purple scale
    public static let purple100 = Color("AppPurple100") // #f3e8ff
    public static let purple200 = Color("AppPurple200") // #e9d5ff
    public static let purple500 = Color("AppPurple500") // #a855f7
    public static let purple600 = Color("AppPurple600") // #9333ea

    // Gray scale
    public static let gray400  = Color("AppGray400")  // #9ca3af
    public static let gray500  = Color("AppGray500")  // #6b7280
    public static let gray600  = Color("AppGray600")  // #4b5563
    public static let gray800  = Color("AppGray800")  // #1f2937
    public static let gray900  = Color("AppGray900")  // #111827

    // Red
    public static let red50    = Color("AppRed50")    // #fef2f2
    public static let red500   = Color("AppRed500")   // #ef4444
    public static let red600   = Color("AppRed600")   // #dc2626

    // Card 背景（ライト/ダーク差分）
    public static let bgCard   = Color("AppBgCard")
}

// MARK: - Timeline 用の意味色（UI はこの層だけ参照）
public enum TLColor {
    // Background
    public static let bgGradientStart = AppColor.pink50    // from-pink-50
    public static let bgGradientEnd   = AppColor.white     // to-white
    public static let bgHeader        = AppColor.whiteA80  // bg-white/80
    public static let bgCard          = AppColor.bgCard    // カード背景（ライト/ダーク対応）

    // Borders
    public static let borderHeader         = AppColor.pink100
    public static let borderCard           = AppColor.pink200
    public static let borderBadgeCeremony  = AppColor.pink200
    public static let borderBadgeReception = AppColor.purple200

    // Badges (タグ)
    public static let badgeCeremonyBg    = AppColor.pink100
    public static let badgeCeremonyText  = AppColor.pink600
    public static let badgeReceptionBg   = AppColor.purple100
    public static let badgeReceptionText = AppColor.purple600

    // Category filter button
    public static let btnCategorySelFrom     = AppColor.pink400
    public static let btnCategorySelTo       = AppColor.pink500
    public static let btnCategorySelText     = AppColor.white

    public static let btnCategoryUnselBg     = AppColor.white
    public static let btnCategoryUnselText   = AppColor.gray600
    public static let btnCategoryUnselBorder = AppColor.pink200
    public static let btnCategoryUnselHoverBg = AppColor.pink50

    // FAB
    public static let fabFrom      = AppColor.pink400
    public static let fabTo        = AppColor.pink500
    public static let fabHoverFrom = AppColor.pink500
    public static let fabHoverTo   = AppColor.pink600

    // Delete
    public static let btnDeleteBg      = AppColor.red500
    public static let btnDeleteHoverBg = AppColor.red600

    // Icons
    public static let icoSparkles      = AppColor.pink400   // タイトルのSparkles
    public static let icoCategoryPink  = AppColor.pink500   // 挙式
    public static let icoCategoryPurple = AppColor.purple500 // 披露宴
    public static let icoMenu          = AppColor.gray400
    public static let icoAction        = AppColor.gray500
    public static let icoWhite         = AppColor.white

    // Text
    public static let textTitlePink   = AppColor.pink600     // 「タイムライン」
    public static let textTagPurple   = AppColor.purple600   // 披露宴タグ
    public static let textAuthor      = AppColor.gray900
    public static let textBody        = AppColor.gray800
    public static let textCategory    = AppColor.gray600     // 非選択カテゴリ
    public static let textMeta        = AppColor.gray500     // ユーザー名/タイムスタンプ/アクション数
    public static let textDot         = AppColor.gray400     // 区切り「·」
    public static let textDeleteTitle = AppColor.red600

    // Hover/Active
    public static let hoverTextPink500 = AppColor.pink500
    public static let hoverBgPink50    = AppColor.pink50
    public static let hoverBgRed50     = AppColor.red50
    public static let fillPink500      = AppColor.pink500    // いいねアイコン塗りつぶし
}

// MARK: - Shadow Presets
public enum TLShadowStyle { case lg, md, sm }

public extension View {
    @ViewBuilder
    func tlShadow(_ style: TLShadowStyle) -> some View {
        switch style {
        case .lg:
            self.shadow(color: .black.opacity(0.12), radius: 16, x: 0, y: 8)
        case .md:
            self.shadow(color: .black.opacity(0.10), radius: 8,  x: 0, y: 4)
        case .sm:
            self.shadow(color: .black.opacity(0.08), radius: 4,  x: 0, y: 2)
        }
    }
}
