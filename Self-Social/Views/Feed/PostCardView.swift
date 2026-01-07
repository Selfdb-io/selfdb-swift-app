//
//  PostCardView.swift
//  Self-Social
//

import SwiftUI
import SelfDB

struct PostCardView: View {
    @EnvironmentObject var db: SelfDBManager
    let post: PostWithDetails
    var onUserTap: ((String) -> Void)?
    
    @State private var showComments = false
    @State private var showDeleteConfirm = false
    @State private var showEditPost = false
    @State private var isDeleting = false
    @State private var isLikeAnimating = false
    
    private var isOwner: Bool {
        db.currentUser?.id == post.userId
    }
    
    private var authorName: String {
        guard let author = post.author else { return "Unknown User" }
        return "\(author.firstName ?? "") \(author.lastName ?? "")"
    }
    
    private var authorInitials: String {
        guard let author = post.author else { return "?" }
        let first = author.firstName?.prefix(1) ?? ""
        let last = author.lastName?.prefix(1) ?? ""
        return "\(first)\(last)".uppercased()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Button {
                    onUserTap?(post.userId)
                } label: {
                    HStack(spacing: 12) {
                        Circle()
                            .fill(
                                LinearGradient(colors: [.orange, .pink], startPoint: .topLeading, endPoint: .bottomTrailing)
                            )
                            .frame(width: 40, height: 40)
                            .overlay(
                                Text(authorInitials)
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                            )
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(authorName)
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(.primary)
                            
                            Text(post.createdAt.timeAgo())
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                Spacer()
                
                if isOwner {
                    Menu {
                        Button {
                            showEditPost = true
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        
                        Button(role: .destructive) {
                            showDeleteConfirm = true
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .rotationEffect(.degrees(90))
                            .font(.title3)
                            .foregroundColor(.secondary)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
            .zIndex(1)  // Ensure header is above media
            
            // Media
            if !post.files.isEmpty {
                MediaCarouselView(files: post.files)
                    .zIndex(0)
                    .onTapGesture(count: 2) {
                        if !post.userHasLiked {
                            Task { await db.toggleLike(postId: post.id) }
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                                isLikeAnimating = true
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                isLikeAnimating = false
                            }
                        }
                    }
                    .overlay(
                        Image(systemName: "heart.fill")
                            .font(.system(size: 80))
                            .foregroundColor(.white)
                            .opacity(isLikeAnimating ? 1 : 0)
                            .scaleEffect(isLikeAnimating ? 1 : 0.5)
                            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isLikeAnimating)
                    )
            }
            
            // Actions
            HStack(spacing: 20) {
                Button {
                    Task { await db.toggleLike(postId: post.id) }
                } label: {
                    Image(systemName: post.userHasLiked ? "heart.fill" : "heart")
                        .font(.title2)
                        .foregroundColor(post.userHasLiked ? .red : .primary)
                }
                
                Button {
                    showComments = true
                } label: {
                    Image(systemName: "bubble.right")
                        .font(.title2)
                        .foregroundColor(.primary)
                }
                
                Spacer()
            }
            .padding(.horizontal)
            .padding(.top, 12)
            
            // Likes
            Text("\(post.likesCount) \(post.likesCount == 1 ? "like" : "likes")")
                .font(.subheadline)
                .fontWeight(.semibold)
                .padding(.horizontal)
                .padding(.top, 8)
            
            // Description
            if let description = post.description, !description.isEmpty {
                HStack(alignment: .top, spacing: 4) {
                    Text(authorName)
                        .fontWeight(.semibold)
                    Text(description)
                }
                .font(.subheadline)
                .padding(.horizontal)
                .padding(.top, 4)
            }
            
            // Comments
            if post.commentsCount > 0 {
                Button {
                    showComments = true
                } label: {
                    Text("View all \(post.commentsCount) comments")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal)
                .padding(.top, 4)
            }
        }
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 5)
        .padding(.horizontal)
        .sheet(isPresented: $showComments) {
            CommentsView(postId: post.id)
        }
        .sheet(isPresented: $showEditPost) {
            CreatePostView(existingPost: post)
        }
        .alert("Delete Post?", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                Task {
                    isDeleting = true
                    try? await db.deletePost(post.id)
                    isDeleting = false
                }
            }
        } message: {
            Text("This will permanently delete this post and all its media files.")
        }
    }
}

#Preview {
    PostCardView(
        post: PostWithDetails(
            post: Post(id: "1", userId: "1", description: "Test post", createdAt: "2026-01-04T12:00:00Z", updatedAt: "2026-01-04T12:00:00Z"),
            files: [],
            likesCount: 5,
            commentsCount: 3,
            userHasLiked: false,
            author: nil
        )
    )
    .environmentObject(SelfDBManager.shared)
}
