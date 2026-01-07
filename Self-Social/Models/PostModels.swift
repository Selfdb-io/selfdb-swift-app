//
//  PostModels.swift
//  Self-Social
//

import Foundation
import SelfDB

struct Post: Identifiable, Codable {
    let id: String
    let userId: String
    let description: String?
    let createdAt: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case description
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct PostFile: Identifiable, Codable {
    let id: String
    let postId: String
    let userId: String
    let fileId: String
    let fileUrl: String
    let fileType: String
    let displayOrder: Int
    let createdAt: String
    let thumbnailFileId: String?
    let thumbnailUrl: String?

    enum CodingKeys: String, CodingKey {
        case id
        case postId = "post_id"
        case userId = "user_id"
        case fileId = "file_id"
        case fileUrl = "file_url"
        case fileType = "file_type"
        case displayOrder = "display_order"
        case createdAt = "created_at"
        case thumbnailFileId = "thumbnail_file_id"
        case thumbnailUrl = "thumbnail_url"
    }

    var isVideo: Bool { fileType == "video" }
    var isImage: Bool { fileType == "image" }
}

struct Like: Identifiable, Codable {
    let id: String
    let postId: String
    let userId: String
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case postId = "post_id"
        case userId = "user_id"
        case createdAt = "created_at"
    }
}

struct Comment: Identifiable, Codable {
    let id: String
    let postId: String
    let userId: String
    let content: String
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case postId = "post_id"
        case userId = "user_id"
        case content
        case createdAt = "created_at"
    }
}

struct PostWithDetails: Identifiable {
    let post: Post
    var files: [PostFileWithData]
    var likesCount: Int
    var commentsCount: Int
    var userHasLiked: Bool
    var author: UserRead?
    let refreshId = UUID()  // Unique ID for each instance to force view updates

    var id: String { post.id }
    var description: String? { post.description }
    var createdAt: String { post.createdAt }
    var updatedAt: String { post.updatedAt }
    var userId: String { post.userId }
}

struct PostFileWithData: Identifiable {
    let postFile: PostFile
    var imageData: Data?
    var thumbnailData: Data?

    var id: String { postFile.id }
}

struct CommentWithAuthor: Identifiable {
    let comment: Comment
    var authorName: String

    var id: String { comment.id }
}
