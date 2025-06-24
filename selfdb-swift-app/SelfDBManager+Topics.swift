//
//  SelfDBManager+Topics.swift
//  selfdb-swift-app
//
//  Specialized topic operations that require complex logic
//

import Foundation
import SelfDB

@MainActor
extension SelfDBManager {
    
    // MARK: - Specialized Topic Operations
    
    /// Delete topic with cascade (all comments and files)
    func deleteTopicCascade(topicId: String) async -> Bool {
        guard selfDB != nil else { return false }

        log("🗑️ Starting cascade delete for topic \(topicId)")

        // 1️⃣ Load all comments belonging to the topic
        let comments = await SelfDBContext<Comment>.fetch(
            filterColumn: "topic_id",
            filterValue: topicId,
            manager: self,
            pageSize: 1000
        )
        
        log("📝 Found \(comments.count) comments to delete")
        
        // Delete all comments and their files using the generic context
        for comment in comments {
            let commentDeleted = await SelfDBContext<Comment>.delete(comment, manager: self)
            if !commentDeleted {
                log("⚠️ Failed to delete comment \(comment.id ?? "unknown")")
            }
        }

        // 2️⃣ Get the topic to delete it and its file
        let topics = await SelfDBContext<Topic>.fetch(
            filterColumn: "id",
            filterValue: topicId,
            manager: self
        )
        
        guard let topic = topics.first else { 
            log("❌ Topic \(topicId) not found")
            return false 
        }

        // 3️⃣ Delete the topic itself (this will also delete its file via the context)
        let deleted = await SelfDBContext<Topic>.delete(topic, manager: self)
        
        if deleted {
            await MainActor.run { 
                self.topics.removeAll { $0.id == topicId } 
            }
            log("✅ Successfully cascade deleted topic \(topicId)")
        } else {
            log("❌ Failed to delete topic \(topicId)")
        }
        
        return deleted
    }
    
    /// Fetch topics with optimized sorting and optional comment count preloading
    func fetchTopics() async {
        // Prevent concurrent topic calls
        guard !isFetchingTopics else {
            log("⏳ fetchTopics skipped – already running")
            return
        }
        isFetchingTopics = true
        defer { isFetchingTopics = false }
        
        resetError()
        isLoading = true
        log("Fetching topics …")
        defer { isLoading = false }
        
        let fetchedTopics = await SelfDBContext<Topic>.fetchAll(
            manager: self,
            orderBy: "createdAt",
            descending: true
        )
        
        topics = fetchedTopics
        log("✅ fetched \(topics.count) topics (sorted newest-first)")
    }
    
    /// Get comment count for a specific topic
    func commentCount(for topicId: String) async -> Int {
        await SelfDBContext<Comment>.count(
            filterColumn: "topic_id",
            filterValue: topicId,
            manager: self
        )
    }
    
    /// Fetch comments for a topic
    func fetchCommentsForTopic(_ topicId: String,
                               page: Int = 1,
                               pageSize: Int = 100) async -> [Comment] {
        await SelfDBContext<Comment>.fetch(
            filterColumn: "topic_id",
            filterValue: topicId,
            manager: self,
            page: page,
            pageSize: pageSize
        ).sorted { $0.createdAt > $1.createdAt } // newest first
    }
}