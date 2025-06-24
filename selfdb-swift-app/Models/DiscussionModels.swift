import Foundation
import SelfDB

// MARK: - Topic
struct Topic: Codable, Identifiable, Equatable, SelfDBFileAttachable {
    var id: String?
    var title: String
    var content: String
    let authorName: String
    let userId: String?
    var fileId: String?
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
    
    static let tableName = "topics"
    
    // Custom fromRow implementation to handle the specific conversion
    static func fromRow(_ row: [String: AnyCodable]) -> Topic? {
        guard let id        = row["id"]?.value as? String,
              let title     = row["title"]?.value as? String,
              let content   = row["content"]?.value as? String,
              let author    = row["author_name"]?.value as? String,
              let created   = row["created_at"]?.value as? String,
              let updated   = row["updated_at"]?.value as? String
        else { return nil }
        
        return Topic(id: id,
                     title: title,
                     content: content,
                     authorName: author,
                     userId: row["user_id"]?.value as? String,
                     fileId: row["file_id"]?.value as? String,
                     createdAt: created,
                     updatedAt: updated)
    }
}

// MARK: - Comment
struct Comment: Codable, Identifiable, Equatable, SelfDBFileAttachable {
    var id: String?
    let topicId: String
    var content: String
    let authorName: String
    let userId: String?
    var fileId: String?
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
    
    static let tableName = "comments"
    
    // Custom fromRow implementation to handle the specific conversion
    static func fromRow(_ row: [String: AnyCodable]) -> Comment? {
        guard let id        = row["id"]?.value as? String,
              let topicId   = row["topic_id"]?.value as? String,
              let content   = row["content"]?.value as? String,
              let author    = row["author_name"]?.value as? String,
              let created   = row["created_at"]?.value as? String,
              let updated   = row["updated_at"]?.value as? String
        else { return nil }

        return Comment(
            id: id,
            topicId: topicId,
            content: content,
            authorName: author,
            userId: row["user_id"]?.value as? String,
            fileId: row["file_id"]?.value as? String,
            createdAt: created,
            updatedAt: updated
        )
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
        print("📎 Topic \(String(describing: id)) has file \(fileId)")
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
        print("📎 Comment \(String(describing: id)) has file \(fileId)")
        return true
    }
}

// MARK: - Network helpers using the new Context pattern
extension Topic {
    /// Fetch all topics
    static func fetchAll(using manager: SelfDBManager) async -> [Topic] {
        await SelfDBContext<Topic>.fetchAll(manager: manager)
    }

    static func create(
        using manager: SelfDBManager,
        title: String,
        content: String,
        authorName: String,
        fileData: Data? = nil,
        filename: String? = nil
    ) async -> Topic? {
        // Don't set dates - let the database handle them
        let topic = Topic(
            id: nil,
            title: title,
            content: content,
            authorName: authorName,
            userId: nil,
            fileId: nil,
            createdAt: "",
            updatedAt: ""
        )
        
        let created = await SelfDBContext<Topic>.create(topic, manager: manager, fileData: fileData, filename: filename)
        
        // Refresh topics list after creation
        if created != nil {
            await manager.fetchTopics()
        }
        
        return created
    }

    static func update(
        using manager: SelfDBManager,
        topic: Topic,
        fileData: Data? = nil,
        filename: String? = nil,
        oldFileId: String? = nil,
        removeFile: Bool = false
    ) async -> Topic? {
        let updated = await SelfDBContext<Topic>.update(topic, manager: manager, fileData: fileData, filename: filename, oldFileId: oldFileId, removeFile: removeFile)
        
        // Refresh topics list after update
        if updated != nil {
            await manager.fetchTopics()
        }
        
        return updated
    }

    static func delete(using manager: SelfDBManager, topic: Topic) async -> Bool {
        // For topics, we need cascade delete (comments + files)
        // This will be handled in SelfDBManager+Topics.swift
        guard let topicId = topic.id else { return false }
        return await manager.deleteTopicCascade(topicId: topicId)
    }
}

extension Comment {
    /// Fetch comments for a topic
    static func fetch(for topicId: String, using manager: SelfDBManager) async -> [Comment] {
        await SelfDBContext<Comment>.fetch(filterColumn: "topic_id", filterValue: topicId, manager: manager)
            .sorted { $0.createdAt > $1.createdAt } // newest first
    }

    static func create(
        using manager: SelfDBManager,
        topicId: String,
        content: String,
        authorName: String,
        fileData: Data? = nil,
        filename: String? = nil
    ) async -> Comment? {
        // Don't set dates - let the database handle them
        let comment = Comment(
            id: nil,
            topicId: topicId,
            content: content,
            authorName: authorName,
            userId: nil,
            fileId: nil,
            createdAt: "",
            updatedAt: ""
        )
        
        let created = await SelfDBContext<Comment>.create(comment, manager: manager, fileData: fileData, filename: filename)
        
        // Refresh topics to update comment counts
        if created != nil {
            await manager.fetchTopics()
        }
        
        return created
    }

    static func update(
        using manager: SelfDBManager,
        comment: Comment,
        fileData: Data? = nil,
        filename: String? = nil,
        oldFileId: String? = nil,
        removeFile: Bool = false
    ) async -> Comment? {
        let updated = await SelfDBContext<Comment>.update(comment, manager: manager, fileData: fileData, filename: filename, oldFileId: oldFileId, removeFile: removeFile)
        
        // Refresh topics to keep everything in sync
        if updated != nil {
            await manager.fetchTopics()
        }
        
        return updated
    }

    static func delete(using manager: SelfDBManager, comment: Comment) async -> Bool {
        let deleted = await SelfDBContext<Comment>.delete(comment, manager: manager)
        
        // Refresh topics to update comment counts
        if deleted {
            await manager.fetchTopics()
        }
        
        return deleted
    }
    
    /// Quick helper – returns total number of comments for a topic
    static func count(for topicId: String, using manager: SelfDBManager) async -> Int {
        await SelfDBContext<Comment>.count(filterColumn: "topic_id", filterValue: topicId, manager: manager)
    }
}
