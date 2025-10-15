//
//  AppUser.swift
//  WeddingTimeline
//
//  Created by 田口友暉 on 2025/07/24.
//

import Foundation
import FirebaseFirestore

struct AppUser: Identifiable, Hashable {
    var id: String            // = uid
    var displayName: String?
    var avatarURL: URL?
    var createdAt: Date?
    var lastActiveAt: Date?
}

extension AppUser {
    init?(dto: AppUserDTO) {
        guard let uid = dto.uid else { return nil }
        self.id = uid
        self.displayName = dto.displayName
        self.avatarURL = dto.photoURL.flatMap(URL.init(string:))
        self.createdAt = dto.createdAt?.dateValue()
        self.lastActiveAt = dto.lastActiveAt?.dateValue()
    }
}
