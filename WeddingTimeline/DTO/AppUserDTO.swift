//
//  AppUserDTO.swift
//  WeddingTimeline
//
//  Created by 田口友暉 on 2025/08/31.
//

import Foundation
import FirebaseFirestore

// /appUsers/{uid}
struct AppUserDTO: Codable {
    @DocumentID var uid: String?
    var displayName: String?
    var photoURL: String?
    @ServerTimestamp var createdAt: Timestamp?
    @ServerTimestamp var lastActiveAt: Timestamp?
}
