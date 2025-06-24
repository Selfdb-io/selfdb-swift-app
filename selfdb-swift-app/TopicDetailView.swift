//
//  TopicDetailView.swift
//  selfd-swift
//
//  Created by rodgers magabo on 04/06/2025.
//

import SwiftUI

struct TopicDetailView: View {
    let topic: Topic
    @ObservedObject var selfDBManager: SelfDBManager
    @State private var comments: [Comment] = []
    @State private var isLoadingComments = false
    @State private var showingAddComment = false
    @State private var showingEditTopic = false
    @State private var editingComment: Comment? = nil
    @State private var updatedTopic: Topic? = nil
    @State private var topicFileViewerKey = UUID()
    @State private var commentFileViewerKeys: [String: UUID] = [:]
    @Environment(\.dismiss) private var dismiss
    
    var currentTopic: Topic {
        updatedTopic ?? topic
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView
            
            // Content
            ZStack(alignment: .bottomTrailing) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // Topic Content
                        topicContentView
                        
                        // Comments Section
                        commentsSection
                    }
                    .padding()
                    .padding(.bottom, 80) // Add padding for floating button
                }
                .refreshable {
                    await loadComments()
                }
                
                // Floating action button for adding comments
                Button {
                    showingAddComment = true
                } label: {
                    Image(systemName: "plus.message")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .frame(width: 56, height: 56)
                        .background(Color.blue)
                        .clipShape(Circle())
                        .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
                }
                .padding(.trailing, 20)
                .padding(.bottom, 20)
            }
        }
        .navigationBarHidden(true)
        .fullScreenCover(isPresented: $showingAddComment) {
            if let topicId = currentTopic.id {
                AddCommentView(
                    isPresented: $showingAddComment,
                    topicId: topicId,
                    selfDBManager: selfDBManager,
                    onCommentAdded: { _ in            // ⬅️ refresh from server
                        Task { await loadComments() }
                    }
                )
            }
        }
        .fullScreenCover(isPresented: $showingEditTopic) {
            CreateTopicView(
                isPresented: $showingEditTopic,
                selfDBManager: selfDBManager,
                onTopicAdded: { updatedTopicData in
                    self.updatedTopic = updatedTopicData
                    self.topicFileViewerKey = UUID()  // Force file viewer refresh
                },
                editingTopic: currentTopic
            )
        }
        .fullScreenCover(item: $editingComment) { comment in
            if let topicId = currentTopic.id {
                AddCommentView(
                    isPresented: .init(
                        get: { editingComment != nil },
                        set: { if !$0 { editingComment = nil } }
                    ),
                    topicId: topicId,
                    selfDBManager: selfDBManager,
                    onCommentAdded: { _ in            // ⬅️ refresh from server
                        Task {
                            // Force refresh the specific comment's file viewer
                            if let commentId = comment.id {
                                commentFileViewerKeys[commentId] = UUID()
                            }
                            await loadComments()
                        }
                    },
                    editingComment: comment,
                    onCommentDeleted: {               // ⬅️ refresh from server
                        Task { await loadComments() }
                    }
                )
            }
        }
        .task {
            await loadComments()
        }
    }
    
    private var headerView: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.title2)
                    .foregroundColor(.blue)
            }

            Spacer()

            // ✏️ Ellipsis opens the CreateTopicView (edit / delete handled there)
            if selfDBManager.isAuthenticated &&
               (currentTopic.userId == selfDBManager.currentUser?.id ||
                (selfDBManager.currentUser?.is_superuser ?? false)) {
                Button { showingEditTopic = true } label: {
                    Image(systemName: "ellipsis")
                        .font(.title2)
                        .foregroundColor(.blue)
                        .frame(width: 44, height: 44)
                        .rotationEffect(.degrees(90))   // vertical ellipsis
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(.systemBackground))
        .shadow(color: .black.opacity(0.1), radius: 1, x: 0, y: 1)
    }
    
    private var topicContentView: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Title
            Text(currentTopic.title)
                .font(.title2)
                .fontWeight(.bold)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            
            // 🖼 FILE PREVIEW -------------------------------------------------
            if currentTopic.hasFile, let fileId = currentTopic.fileId {
                FileViewer(fileId: fileId, selfDBManager: selfDBManager)
                    .id(topicFileViewerKey)  // Force refresh when key changes
                    .frame(maxHeight: 240)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            // Content
            Text(currentTopic.content)
                .font(.body)
                .foregroundColor(.primary)
                .multilineTextAlignment(.leading)
            
            // Meta information
            HStack {
                Text("By \(currentTopic.authorName)")
                    .font(.callout)
                    .foregroundColor(.blue)
                    .fontWeight(.medium)
                
                Spacer()
                
                Text(formatRelativeDate(currentTopic.createdAt))
                    .font(.callout)
                    .foregroundColor(.secondary)
            }
            
            Text("\(comments.count) comments")
                .font(.callout)
                .foregroundColor(.secondary)
                .italic()
        }
        .padding(16)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
    
    private func loadComments() async {
        guard let topicId = currentTopic.id else { return }
        isLoadingComments = true
        let fetchedComments = await selfDBManager
            .fetchCommentsForTopic(topicId)
        
        // Don't preload - let FileViewer handle it individually
         
         await MainActor.run {
             self.comments = fetchedComments.sorted { $0.createdAt < $1.createdAt }
            // Reset comment file viewer keys
            for comment in fetchedComments {
                if let commentId = comment.id, commentFileViewerKeys[commentId] == nil {
                    commentFileViewerKeys[commentId] = UUID()
                }
            }
             self.isLoadingComments = false
         }
     }
    
    private func deleteTopicAndDismiss() {
        Task {
            guard let topicId = currentTopic.id else { return }
            let deleteSuccess = await selfDBManager.deleteTopic(topicId: topicId)
            await MainActor.run {
                if deleteSuccess {
                    dismiss()
                } else {
                    // Could show an error alert here if needed
                    // For now, still dismiss since the UI expects it
                    dismiss()
                }
            }
        }
    }
}

struct CommentView: View {
    let comment: Comment
    @ObservedObject var selfDBManager: SelfDBManager
    var onEdit: ((Comment) -> Void)? = nil
    var onDelete: ((Comment) -> Void)? = nil
    let fileViewerKey: UUID
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Comment content with edit menu
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    // Comment content
                    Text(comment.content)
                        .font(.body)
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                // Edit button for comment (only show if user is authenticated and owns the comment)
                if selfDBManager.isAuthenticated &&
                   (comment.userId == selfDBManager.currentUser?.id ||
                    (selfDBManager.currentUser?.is_superuser ?? false)) {
                    Button { onEdit?(comment) } label: {
                        Image(systemName: "ellipsis")
                            .font(.callout)
                            .foregroundColor(.secondary)
                            .frame(width: 30, height: 30)
                            .rotationEffect(.degrees(90)) // Make it vertical
                    }
                }
            }
            
            // File attachment (if exists)
            if comment.hasFile, let fileId = comment.fileId {
                FileViewer(fileId: fileId, selfDBManager: selfDBManager)
                    .id(fileViewerKey)  // Force refresh when key changes
                    .frame(maxHeight: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            
            // Meta information
            HStack {
                Text("By \(comment.authorName)")
                    .font(.caption)
                    .foregroundColor(.blue)
                    .fontWeight(.medium)
                
                Spacer()
                
                Text(formatRelativeDate(comment.createdAt))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(12)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(color: .black.opacity(0.03), radius: 1, x: 0, y: 1)
        // …previous UI restored – delete happens inside the AddComment sheet
    }
}

// Update the commentsSection to use the new CommentView
extension TopicDetailView {
    private var commentsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Comments (\(comments.count))")
                .font(.title3)
                .fontWeight(.semibold)
            
            if isLoadingComments {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Loading comments...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding()
            } else if comments.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "message")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    
                    Text("No comments yet")
                        .font(.headline)
                        .fontWeight(.medium)
                    
                    Text("Be the first to share your thoughts!")
                        .font(.callout)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(32)
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(comments) { comment in
                        CommentView(
                            comment: comment,
                            selfDBManager: selfDBManager,
                            onEdit: { editingComment = $0 },
                            onDelete: { deletedComment in
                                comments.removeAll { $0.id == deletedComment.id }
                            },
                            fileViewerKey: commentFileViewerKeys[comment.id ?? ""] ?? UUID()
                        )
                    }
                }
            }
        }
    }
}

#Preview {
    NavigationView {
        TopicDetailView(
            topic: Topic(
                id: "sample-id",
                title: "Sample Topic",
                content: "This is a sample topic content for preview purposes.",
                authorName: "John Doe",
                userId: nil,
                fileId: nil,
                createdAt: "2025-06-04T10:30:00.000000Z",
                updatedAt: "2025-06-04T10:30:00.000000Z"
            ),
            selfDBManager: SelfDBManager()
        )
    }
}
