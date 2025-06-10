import Foundation

// MARK: - Topic
struct Topic: Codable, Identifiable, Equatable {
    let id: String
    let title: String
    let content: String
    let authorName: String
    let userId: String?
    let fileId: String?
    let createdAt: String
    let updatedAt: String

    private enum CodingKeys: String, CodingKey {
        case id, title, content
        case authorName = "author_name"
        case userId     = "user_id"
        case fileId     = "file_id"
        case createdAt  = "created_at"
        case updatedAt  = "updated_at"
    }
}

// MARK: - Comment
struct Comment: Codable, Identifiable, Equatable {
    let id: String
    let topicId: String
    let content: String
    let authorName: String
    let userId: String?
    let fileId: String?
    let createdAt: String
    let updatedAt: String

    private enum CodingKeys: String, CodingKey {
        case id, content
        case topicId    = "topic_id"
        case authorName = "author_name"
        case userId     = "user_id"
        case fileId     = "file_id"
        case createdAt  = "created_at"
        case updatedAt  = "updated_at"
    }
}

// MARK: - Helper Extensions
extension Topic {
    var formattedCreatedAt: String { formatDate(createdAt) }
    var formattedUpdatedAt: String { formatDate(updatedAt) }

    var hasFile: Bool {
        guard let fileId = fileId,
              !fileId.isEmpty,
              fileId != "null",
              fileId != "nil" else {
            return false
        }
        print("📎 Topic \(id) has file \(fileId)")
        return true
    }
}

extension Comment {
    var formattedCreatedAt: String { formatDate(createdAt) }
    var formattedUpdatedAt: String { formatDate(updatedAt) }

    var hasFile: Bool {
        guard let fileId = fileId,
              !fileId.isEmpty,
              fileId != "null",
              fileId != "nil" else {
            return false
        }
        print("📎 Comment \(id) has file \(fileId)")
        return true
    }
}

// MARK: - Network helpers
extension Topic {
    /// Convenience wrapper: fetch all topics and return them.
    static func fetchAll(using manager: SelfDBManager) async -> [Topic] {
        // We intentionally ignore the Void result of `fetchTopics`
        _ = await manager.fetchTopics()       // ensure the call is awaited
        return await manager.topics
    }

    static func create(
        using manager: SelfDBManager,
        title: String,
        content: String,
        authorName: String,
        fileData: Data? = nil,
        filename: String? = nil
    ) async -> Topic? {
        await manager.createTopic(
            title: title,
            content: content,
            authorName: authorName,
            fileData: fileData,
            filename: filename
        )
    }

    static func update(
        using manager: SelfDBManager,
        topicId: String,
        title: String,
        content: String,
        fileData: Data? = nil,
        filename: String? = nil
    ) async -> Topic? {
        await manager.updateTopic(
            topicId: topicId,
            title: title,
            content: content,
            fileData: fileData,
            filename: filename
        )
    }

    static func delete(using manager: SelfDBManager, topicId: String) async -> Bool {
        await manager.deleteTopic(topicId: topicId)
    }
}

extension Comment {
    /// Convenience wrapper: fetch comments for a topic and return them.
    static func fetch(for topicId: String, using manager: SelfDBManager) async -> [Comment] {
        return await manager.fetchCommentsForTopic(topicId)   // explicit `await`
    }

    static func create(
        using manager: SelfDBManager,
        topicId: String,
        content: String,
        authorName: String,
        fileData: Data? = nil,
        filename: String? = nil
    ) async -> Comment? {
        await manager.createComment(
            topicId: topicId,
            content: content,
            authorName: authorName,
            fileData: fileData,
            filename: filename
        )
    }

    static func update(
        using manager: SelfDBManager,
        commentId: String,
        content: String,
        fileData: Data? = nil,
        filename: String? = nil
    ) async -> Comment? {
        await manager.updateComment(
            commentId: commentId,
            content: content,
            fileData: fileData,
            filename: filename
        )
    }

    static func delete(using manager: SelfDBManager, commentId: String) async -> Bool {
        await manager.deleteComment(commentId: commentId)
    }
}
