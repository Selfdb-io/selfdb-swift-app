//
//  ProfileView.swift
//  Self-Social
//

import SwiftUI
import SelfDB

struct ProfileView: View {
    @EnvironmentObject var db: SelfDBManager
    let userId: String
    
    @State private var user: UserRead?
    @State private var userPosts: [PostWithDetails] = []
    @State private var isLoading = true
    @State private var showCreatePost = false
    
    private var isOwnProfile: Bool {
        db.currentUser?.id == userId
    }
    
    private var displayName: String {
        guard let user = user else { return "User" }
        return "\(user.firstName ?? "") \(user.lastName ?? "")"
    }
    
    private var initials: String {
        guard let user = user else { return "?" }
        let first = user.firstName?.prefix(1) ?? ""
        let last = user.lastName?.prefix(1) ?? ""
        return "\(first)\(last)".uppercased()
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Profile Header
                VStack(spacing: 16) {
                    // Avatar
                    Circle()
                        .fill(
                            LinearGradient(colors: [.orange, .pink], startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                        .frame(width: 100, height: 100)
                        .overlay(
                            Text(initials)
                                .font(.title)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                        )
                    
                    // Name
                    Text(displayName)
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    // Email
                    if let email = user?.email {
                        Text(email)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    
                    // Stats
                    HStack(spacing: 40) {
                        VStack {
                            Text("\(userPosts.count)")
                                .font(.headline)
                            Text("Posts")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        VStack {
                            Text("\(totalLikes)")
                                .font(.headline)
                            Text("Likes")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.top, 8)
                    
                    // Actions
                    if isOwnProfile {
                        Button {
                            Task { await db.logout() }
                        } label: {
                            Text("Sign Out")
                                .fontWeight(.medium)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color(.systemGray6))
                                .cornerRadius(12)
                        }
                        .padding(.horizontal, 40)
                    }
                }
                .padding()
                
                Divider()
                
                // Posts Grid
                if isLoading {
                    ProgressView()
                        .padding()
                } else if userPosts.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "camera")
                            .font(.system(size: 40))
                            .foregroundColor(.secondary)
                        Text("No Posts Yet")
                            .font(.headline)
                        
                        if isOwnProfile {
                            Button {
                                showCreatePost = true
                            } label: {
                                Text("Create Your First Post")
                                    .fontWeight(.medium)
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 10)
                                    .background(Color.blue)
                                    .foregroundColor(.white)
                                    .cornerRadius(8)
                            }
                        }
                    }
                    .padding(.vertical, 40)
                } else {
                    LazyVGrid(columns: [
                        GridItem(.flexible(), spacing: 2),
                        GridItem(.flexible(), spacing: 2),
                        GridItem(.flexible(), spacing: 2)
                    ], spacing: 2) {
                        ForEach(userPosts) { post in
                            PostGridItem(post: post)
                        }
                    }
                }
            }
        }
        .navigationTitle(isOwnProfile ? "Profile" : displayName)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadProfile()
        }
        .refreshable {
            await loadProfile()
        }
        .sheet(isPresented: $showCreatePost) {
            CreatePostView()
        }
    }
    
    private var totalLikes: Int {
        userPosts.reduce(0) { $0 + $1.likesCount }
    }
    
    private func loadProfile() async {
        isLoading = true
        
        // Load user
        if userId == db.currentUser?.id {
            user = db.currentUser
        } else {
            user = try? await db.getUser(userId)
        }
        
        // Filter posts by user
        userPosts = db.posts.filter { $0.userId == userId }
        
        isLoading = false
    }
}

struct PostGridItem: View {
    let post: PostWithDetails
    @State private var showPost = false
    
    var body: some View {
        Button {
            showPost = true
        } label: {
            GeometryReader { geometry in
                ZStack {
                    if let firstFile = post.files.first {
                        if let imageData = firstFile.imageData, let image = UIImage(data: imageData) {
                            Image(uiImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: geometry.size.width, height: geometry.size.width)
                                .clipped()
                        } else if let thumbData = firstFile.thumbnailData, let image = UIImage(data: thumbData) {
                            Image(uiImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: geometry.size.width, height: geometry.size.width)
                                .clipped()
                        } else {
                            placeholder(size: geometry.size.width)
                        }
                        
                        if firstFile.postFile.isVideo {
                            Image(systemName: "play.fill")
                                .foregroundColor(.white)
                                .shadow(radius: 5)
                        }
                        
                        if post.files.count > 1 {
                            VStack {
                                HStack {
                                    Spacer()
                                    Image(systemName: "square.fill.on.square.fill")
                                        .foregroundColor(.white)
                                        .shadow(radius: 5)
                                        .padding(8)
                                }
                                Spacer()
                            }
                        }
                    } else {
                        placeholder(size: geometry.size.width)
                    }
                }
            }
            .aspectRatio(1, contentMode: .fit)
        }
        .sheet(isPresented: $showPost) {
            NavigationStack {
                ScrollView {
                    PostCardView(post: post)
                }
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Close") { showPost = false }
                    }
                }
            }
        }
    }
    
    private func placeholder(size: CGFloat) -> some View {
        Rectangle()
            .fill(Color(.systemGray5))
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: "photo")
                    .foregroundColor(.secondary)
            )
    }
}

#Preview {
    NavigationStack {
        ProfileView(userId: "1")
            .environmentObject(SelfDBManager.shared)
    }
}
