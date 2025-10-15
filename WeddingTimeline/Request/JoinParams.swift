//
//  JoinParams.swift
//  WeddingTimeline
//
//  Created by 田口友暉 on 2025/08/31.
//
import Foundation

struct JoinParams {
    let roomId: String
    let roomKey: String
    let username: String
    let selectedIcon: String
}

enum JoinError: Error, @preconcurrency LocalizedError {
    case notSignedIn
    case invalidKey
    case usernameTaken
    case banned
    case iconNotSelected
    case unknown

    var errorDescription: String? {
        switch self {
        case .notSignedIn: return "サインインに失敗しました。"
        case .invalidKey:  return "roomKey が正しくありません。"
        case .usernameTaken: return "このユーザー名は既に使われています。"
        case .banned:      return "このルームへの参加は禁止されています。"
        case .iconNotSelected: return "アイコンを指定してください。"
        case .unknown:     return "不明なエラーが発生しました。"
        }
    }
}
