# AGENTS.md — WeddingTimeline (SwiftUI + MVVM + Firebase)

本ドキュメントは Codex 用のエージェント定義です。役割分担・ルール・ハンドオフ手順を規定し、安定したコード生成とレビュー運用を行います。

## 0) 全体ポリシー（必読）
- **ターゲット**: iOS 17+（最小 iOS 16 許容）/ Swift 5.9+ / SwiftUI + MVVM
- **状態管理**: `@Observable`（Observation）優先。View の状態は `@State` / `@Bindable`
- **並行性**: async/await を第一選択。UI 更新は `@MainActor`
- **データ層**: Firestore は **DTO** → Domain Model へ変換してから ViewModel へ渡す
- **パフォーマンス**: `task(id:)` を用い、`onAppear` で重処理しない。画像は非同期+キャッシュ。`GeometryReader` は最小限
- **依存**: SPM 最小主義（Rx 系禁止）。Lint/Format は SwiftLint/SwiftFormat
- **命名**: `TimeLinePostDTO`, `TimeLinePost`, `PostRepository`, `TimeLineViewModel`
- **UI方針**: ScrollView + LazyVStack を基本。タイムラインは X/Twitter 風。タグは「挙式/披露宴」
- **i18n/a11y**: テキストは `LocalizedStringKey`、`accessibilityLabel` 付与
- **セキュリティ**: 秘密情報は環境変数/CI 秘密管理。リポジトリ直コミット禁止

---

## 1) エージェント一覧

### A1. iOS SwiftUI エージェント（主担当）
**責務**
- 画面/コンポーネントの SwiftUI 実装、MVVM の ViewModel 実装
- Observation への移行、`task(id:)` 設計、アニメーションの最適化
- タイムライン（1000件級）でのジャンク/白画面対策

**入出力**
- 入力: 画面要件/UX、モデル定義、Figma 指示（あれば）
- 出力: コンパイル可能な最小単位の Swift ファイル + `#Preview`

**ルール**
- DTO を直接 View に渡さない
- `withAnimation` は必要最低限。`opacity + .move(edge:)` を優先
- 非同期画像ローダはキャンセル/再利用対応

**関連ディレクトリ**
- `ios/App/`, `ios/Features/**`, `ios/Shared/**`

---

### A2. Firestore/Backend エージェント
**責務**
- コレクション設計、DTO/Domain 変換、ルール/インデックス（必要に応じて）
- Cloud Storage パス設計、メディア処理（リサイズ/サムネ生成の設計）

**入出力**
- 入力: ユースケース、データ要件
- 出力: DTO/Domain 定義、Repository/Actor、サンプルクエリ、セキュリティルール案

**ルール**
- `rooms/{roomId}/posts/{postId}`, `users/{uid}` を基本例とする
- 書き込み/読み取りの最小権限を原則とする（ルールは具体的に）

**関連ディレクトリ**
- `backend/firestore/`, `ios/Shared/Models/`, `ios/Shared/Services/`

---

### A3. パフォーマンス/計測 エージェント
**責務**
- レンダリング/メモリ/スレッドのボトルネック分析方針を提案
- Instruments での確認手順、Apdex KPI の定義テンプレを提示

**出力**
- 改善 PR の観点チェックリスト
- スクロールにおける “中断なめらかさ” の検証手順

---

### A4. QA/テスト エージェント
**責務**
- XCTest（async 対応）・スナップショットテストの雛形
- CI 上のテスト並列化・失敗時ログ収集設計

**出力**
- `Tests/**` に置くユニット/統合テスト
- 計測用 `measure(metrics:)` サンプル

---

### A5. DevInfra/CI エージェント
**責務**
- XcodeProj/スキーム整備、SwiftLint/SwiftFormat 設定
- GitHub Actions（または他 CI）でのビルド/テスト/アーティファクト化

**出力**
- `.github/workflows/ios.yml`（キャッシュ/並列/テストレポート込み）
- `Makefile` or `scripts/**`（`format`, `lint`, `test` ターゲット）

---

### A6. Docs/UX ライター エージェント
**責務**
- README/ADR/開発規約、ユーザー向け説明の更新
- スクリーンショット/プレビュー GIF の導線整備

**出力**
- `README.md`、`docs/adr/XXXX-YY-zz.md` の追記
- UI コンポーネントの使用例表

---

## 2) 役割分担とルーティング規則
- **iOS SwiftUI**: `ios/` 配下の `.swift`（View, ViewModel, Component）
- **Backend**: `ios/Shared/Models`, `ios/Shared/Services`, `backend/**`
- **Perf**: `ios/**` のうち `View`/`ViewModel`/画像処理
- **QA**: `Tests/**`, `UITests/**`
- **DevInfra**: `.github/**`, `scripts/**`, `Makefile`, `.swiftlint.yml`
- **Docs**: `README.md`, `docs/**`

**曖昧な場合**: iOS → Backend → Perf → QA → Docs の順で相談/ハンドオフ。

---

## 3) ハンドオフ・プロトコル
1. 実装者は `docs/handoffs/` に `YYYYMMDD-<topic>.md` を作成（課題/前提/入出力/制約/完了条件）
2. Pull Request には `Handoff:` セクションを設け、担当エージェントをメンション
3. 受領側は不明点を `Open Questions` として追記し、最小実装を返す
4. 最後に iOS エージェントが UI 結合し、QA がテスト項目を確定

---

## 4) コーディング規約（要約）
- `///` ドキュメントコメント。`Summary/Parameters/Returns/Throws` を書く
- `init(dto:)` で Domain 化。ViewModel では Domain のみ扱う
- 画像/動画は **キャンセル可能** ローディング + メモリ/ディスクキャッシュ
- SwiftUI の状態更新は **メインスレッド厳守**（`@MainActor` または `MainActor.run`）

---

## 5) Firestore/モデル テンプレ（合意済み最小セット）
```swift
public struct TimeLinePostDTO: Codable, Sendable, Identifiable {
    public var id: String
    public var roomId: String
    public var authorId: String
    public var text: String
    public var media: [MediaDTO]
    public var tag: String // "ceremony" | "reception"
    public var createdAt: Timestamp
    public var likeCount: Int
}

public struct TimeLinePost: Sendable, Identifiable {
    public let id: String
    public let roomId: String
    public let authorId: String
    public let text: String
    public let media: [Media]
    public let tag: Tag
    public let createdAt: Date
    public var likeCount: Int
    public enum Tag: String, CaseIterable { case ceremony, reception }
    public init(dto: TimeLinePostDTO) {
        id = dto.id; roomId = dto.roomId; authorId = dto.authorId
        text = dto.text; media = dto.media.map(Media.init)
        tag = Tag(rawValue: dto.tag) ?? .ceremony
        createdAt = dto.createdAt.dateValue()
        likeCount = dto.likeCount
    }
}