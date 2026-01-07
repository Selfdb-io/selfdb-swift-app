//
//  NotificationModels.swift
//  Self-Social
//

import Foundation

enum NotificationType: String, Codable {
    case like
    case comment
    case newPost = "new_post"
}

struct AppNotification: Identifiable, Codable {
    let id: String
    let userId: String
    let senderId: String
    let type: String
    let postId: String?
    let commentId: String?
    let title: String
    let body: String
    var isRead: Bool
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case senderId = "sender_id"
        case type
        case postId = "post_id"
        case commentId = "comment_id"
        case title
        case body
        case isRead = "is_read"
        case createdAt = "created_at"
    }

    var notificationType: NotificationType? {
        NotificationType(rawValue: type)
    }
}

struct DeviceToken: Identifiable, Codable {
    let id: String
    let userId: String
    let deviceToken: String
    let platform: String
    let createdAt: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case deviceToken = "device_token"
        case platform
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}
