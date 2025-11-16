# Copilot Instructions — SwiftUI + MVVM + Firestore

## Project Overview
- App: WeddingTimeline（SwiftUI）
- Targets: iOS 17+（最低16想定）、Swift 5.9+ / Concurrency ベース
- Architecture: MVVM + Repository + DTO→Domain Model 変換
- Backend: Firebase Firestore（オフライン無効/必要時のみ有効化）, Firebase Cloud Storage（画像/動画）
- UI: ScrollView + LazyVStack 中心（List ではなくカスタムセル最優先）
- 目的: X のようなタイムライン。Room 単位の公開範囲。タグ絞り込み（例: 挙式/披露宴）

## Code Generation Ground Rules
- **必ずコンパイル可能な最小再現コード**を出力。不要なスタブや謎メソッドを生まない。
- **Swift Concurrency 優先**：async/await, `Task`, `task(id:)` を使う。Combine は必要時のみ。
- **Observation API 使用**：状態モデルは `@Observable`、ビューは `@State`/`@Bindable` を適切に。
- **MainActor 安全**：UI 更新は `@MainActor`。リポジトリ/キャッシュは `actor` または `nonisolated` を明示。
- **DTO と Domain を分離**：Firestore の生データは DTO、View には Domain Model を渡す。
- **エラーは型安全に**：`AppError`（enum + associated values）で集約し、ユーザ文言は `ErrorMessage`に分離。
- **画像/動画は非同期/キャンセル可能**に。サムネ生成やリサイズはバックグラウンド。
- **依存追加は最小限**：Rx 系は導入しない。SPM のみ、iOS 標準/Swift Algorithms など軽量を優先。
- **コメント/Doc**：`///` で Summary/Parameters/Returns/Throws を書く。例を提示すること。
- **国際化/アクセシビリティ**：`Text` は `LocalizedStringKey`。`accessibilityLabel` を提案。

## File/Folder Conventions
- プレビューは `#Preview` を各 View に用意。

## Firestore Rules（生成時の前提）
- コレクション構成（例）:
  - `rooms/{roomId}/posts/{postId}`
  - `users/{uid}`
- Post DTO（例）:  
  ```swift
  struct TimeLinePostDTO: Codable, Sendable {
      var id: String
      var roomId: String
      var authorId: String
      var text: String
      var media: [MediaDTO]
      var tag: String // "ceremony" or "reception"
      var createdAt: Timestamp
      var likeCount: Int
  }
