//
//  AppError.swift
//  WeddingTimeline
//
//  Created by 田口友暉 on 2025/11/27.
//

import Foundation

enum AppError: Error, LocalizedError {
    /// 未ログイン状態
    case unauthenticated
    
    /// 権限不足（他人の投稿を編集しようとした場合など）
    case unauthorized
    
    /// データが不正（画像変換失敗など）
    case invalidData
    
    /// ファイルサイズ超過（画像 10MB、動画 200MB）
    case fileTooLarge(String)
    
    /// 動画変換エラー（トランスコード失敗）
    case transcodeError(String)
    
    /// Storage アップロード失敗
    case uploadFailed(Error)
    
    /// Firestore 書き込み失敗
    case firestoreError(Error)
    
    /// ネットワークエラー
    case networkError(Error)
    
    // MARK: - LocalizedError
    
    /// ユーザー向けエラーメッセージ
    ///
    /// - Note: 本番環境では `Localizable.strings` に集約すること
    var errorDescription: String? {
        switch self {
        case .unauthenticated:
            return "ログインが必要です"
            
        case .unauthorized:
            return "この操作を行う権限がありません"
            
        case .invalidData:
            return "データが不正です"
            
        case .fileTooLarge(let message):
            return message
            
        case .transcodeError(let message):
            return "動画の変換に失敗しました: \(message)"
            
        case .uploadFailed(let error):
            return "アップロードに失敗しました: \(error.localizedDescription)"
            
        case .firestoreError(let error):
            return "投稿の作成に失敗しました: \(error.localizedDescription)"
            
        case .networkError(let error):
            return "ネットワークエラーが発生しました: \(error.localizedDescription)"
        }
    }
    
    /// デバッグ用の詳細情報
    ///
    /// - Note: 開発環境でのみログ出力に使用
    var debugDescription: String {
        switch self {
        case .unauthenticated:
            return "[Auth] User not authenticated"
            
        case .unauthorized:
            return "[Auth] Insufficient permissions"
            
        case .invalidData:
            return "[Data] Invalid or corrupted data"
            
        case .fileTooLarge(let message):
            return "[Storage] File size limit exceeded: \(message)"
            
        case .transcodeError(let message):
            return "[Media] Transcode failed: \(message)"
            
        case .uploadFailed(let error):
            return "[Storage] Upload failed: \(error)"
            
        case .firestoreError(let error):
            return "[Firestore] Database error: \(error)"
            
        case .networkError(let error):
            return "[Network] Connection error: \(error)"
        }
    }
}

// MARK: - Error Recovery Suggestions

extension AppError {
    /// ユーザーに提示する対処法（オプション）
    ///
    /// ## 使用例
    /// ```swift
    /// if let suggestion = error.recoverySuggestion {
    ///     print("対処法: \(suggestion)")
    /// }
    /// ```
    var recoverySuggestion: String? {
        switch self {
        case .unauthenticated:
            return "ログイン画面からログインしてください"
            
        case .unauthorized:
            return "投稿の作成者に連絡してください"
            
        case .invalidData:
            return "別のファイルを選択してください"
            
        case .fileTooLarge:
            return "ファイルサイズを小さくしてから再度お試しください"
            
        case .transcodeError:
            return "別の動画を選択するか、時間をおいて再度お試しください"
            
        case .uploadFailed, .firestoreError, .networkError:
            return "ネットワーク接続を確認してから再度お試しください"
        }
    }
}
