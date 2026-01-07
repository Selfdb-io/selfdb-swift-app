//
//  CommentsView.swift
//  Self-Social
//

import SwiftUI
import SelfDB


struct CommentsView: View {
    @EnvironmentObject var db: SelfDBManager
    @Environment(\.dismiss) private var dismiss
    
    let postId: String
    
    @State private var comments: [CommentWithAuthor] = []
    @State private var newComment = ""
    @State private var isLoading = true
    @State private var isSubmitting = false
    @State private var editingCommentId: String?
    @State private var editContent = ""
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if isLoading {
                    Spacer()
                    ProgressView()
                    Spacer()
                } else if comments.isEmpty {
                    Spacer()
                    VStack(spacing: 12) {
                        Image(systemName: "bubble.left.and.bubble.right")
                            .font(.system(size: 50))
                            .foregroundColor(.secondary)
                        Text("No comments yet")
                            .font(.headline)
                        Text("Be the first to comment!")
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                } else {
                    List {
                        ForEach(comments) { item in
                            CommentRowView(
                                comment: item,
                                isOwner: db.currentUser?.id == item.comment.userId,
                                isEditing: editingCommentId == item.id,
                                editContent: $editContent,
                                onEdit: {
                                    editingCommentId = item.id
                                    editContent = item.comment.content
                                },
                                onSaveEdit: {
                                    Task {
                                        try? await db.updateComment(commentId: item.id, content: editContent)
                                        editingCommentId = nil
                                        await loadComments()
                                    }
                                },
                                onCancelEdit: {
                                    editingCommentId = nil
                                },
                                onDelete: {
                                    Task {
                                        try? await db.deleteComment(commentId: item.id, postId: postId)
                                        await loadComments()
                                    }
                                }
                            )
                        }
                    }
                    .listStyle(.plain)
                }
                
                Divider()
                
                // Input
                HStack(spacing: 12) {
                    TextField("Add a comment...", text: $newComment)
                        .textFieldStyle(.roundedBorder)
                    
                    Button {
                        Task { await addComment() }
                    } label: {
                        if isSubmitting {
                            ProgressView()
                        } else {
                            Image(systemName: "paperplane.fill")
                                .foregroundColor(newComment.isEmpty ? .secondary : .blue)
                        }
                    }
                    .disabled(newComment.isEmpty || isSubmitting)
                }
                .padding()
            }
            .navigationTitle("Comments")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") { dismiss() }
                }
            }
            .task {
                await loadComments()
            }
        }
    }
    
    private func loadComments() async {
        isLoading = true
        do {
            comments = try await db.loadComments(postId: postId)
        } catch {
            print("Failed to load comments: \(error)")
        }
        isLoading = false
    }
    
    private func addComment() async {
        guard !newComment.isEmpty else { return }
        
        isSubmitting = true
        do {
            try await db.addComment(postId: postId, content: newComment)
            newComment = ""
            await loadComments()
        } catch {
            print("Failed to add comment: \(error)")
        }
        isSubmitting = false
    }
}

struct CommentRowView: View {
    let comment: CommentWithAuthor
    let isOwner: Bool
    let isEditing: Bool
    @Binding var editContent: String
    var onEdit: () -> Void
    var onSaveEdit: () -> Void
    var onCancelEdit: () -> Void
    var onDelete: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(comment.authorName)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                
                Text(comment.comment.createdAt.timeAgo())
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                if isOwner && !isEditing {
                    Menu {
                        Button { onEdit() } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        Button(role: .destructive) { onDelete() } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            if isEditing {
                HStack {
                    TextField("Edit comment", text: $editContent)
                        .textFieldStyle(.roundedBorder)
                    
                    Button { onSaveEdit() } label: {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    }
                    
                    Button { onCancelEdit() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.red)
                    }
                }
            } else {
                Text(comment.comment.content)
                    .font(.subheadline)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    CommentsView(postId: "1")
        .environmentObject(SelfDBManager.shared)
}
