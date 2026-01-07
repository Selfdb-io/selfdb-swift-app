//
//  FeedView.swift
//  Self-Social
//

import SwiftUI
import UserNotifications
import UIKit

struct FeedView: View {
    @EnvironmentObject var db: SelfDBManager
    @Binding var showCreatePost: Bool
    @State private var selectedProfileUserId: String?
    @State private var showNotifications = false
    @AppStorage("didRequestNotificationPermission") private var didRequestNotificationPermission = false
    
    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                Group {
                    if db.isLoadingPosts && db.posts.isEmpty {
                        VStack(spacing: 16) {
                            ProgressView()
                                .scaleEffect(1.5)
                            Text("Loading your feed...")
                                .foregroundColor(.secondary)
                        }
                    } else if let error = db.error {
                        VStack(spacing: 16) {
                            Text(error)
                                .foregroundColor(.red)
                            Button("Try Again") {
                                Task { await db.loadPosts() }
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        .padding()
                    } else if db.posts.isEmpty {
                        VStack(spacing: 16) {
                            Image(systemName: "photo.on.rectangle.angled")
                                .font(.system(size: 60))
                                .foregroundColor(.orange)
                            
                            Text("No posts yet")
                                .font(.title2)
                                .fontWeight(.semibold)
                            
                            Text("Create your first post to get started!")
                                .foregroundColor(.secondary)
                            
                            Button {
                                showCreatePost = true
                            } label: {
                                Text("Create a Post")
                                    .fontWeight(.semibold)
                                    .padding(.horizontal, 24)
                                    .padding(.vertical, 12)
                                    .background(
                                        LinearGradient(colors: [.orange, .blue], startPoint: .leading, endPoint: .trailing)
                                    )
                                    .foregroundColor(.white)
                                    .cornerRadius(12)
                            }
                        }
                        .padding()
                    } else {
                        ScrollView {
                            HStack {
                                Text("Self-Social")
                                    .font(.title)
                                    .fontWeight(.bold)
                                    .foregroundStyle(
                                        LinearGradient(colors: [.orange, .blue], startPoint: .leading, endPoint: .trailing)
                                    )
                                Spacer()
                                
                                // Notification Bell
                                Button {
                                    showNotifications = true
                                } label: {
                                    ZStack(alignment: .topTrailing) {
                                        Image(systemName: "bell.fill")
                                            .font(.title2)
                                            .foregroundStyle(
                                                LinearGradient(colors: [.orange, .blue], startPoint: .leading, endPoint: .trailing)
                                            )
                                        
                                        if db.unreadNotificationCount > 0 {
                                            Text(db.unreadNotificationCount > 99 ? "99+" : "\(db.unreadNotificationCount)")
                                                .font(.caption2)
                                                .fontWeight(.bold)
                                                .foregroundColor(.white)
                                                .padding(4)
                                                .background(Color.red)
                                                .clipShape(Circle())
                                                .offset(x: 8, y: -8)
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal)
                            LazyVStack(spacing: 16) {
                                ForEach(db.posts) { post in
                                    PostCardView(
                                        post: post,
                                        onUserTap: { userId in
                                            selectedProfileUserId = userId
                                        }
                                    )
                                    .id(post.refreshId)
                                }
                                
                                VStack(spacing: 8) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 40))
                                        .foregroundColor(.gray.opacity(0.5))
                                    Text("You're all caught up!")
                                        .foregroundColor(.secondary)
                                }
                                .padding(.vertical, 40)
                            }
                            .padding(.vertical)
                        }
                    }
                    
                    // Floating Action Button
                    if !db.posts.isEmpty {
                        Button {
                            showCreatePost = true
                        } label: {
                            Image(systemName: "plus")
                                .font(.title2)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                                .frame(width: 56, height: 56)
                                .background(
                                    LinearGradient(colors: [.orange, .blue], startPoint: .leading, endPoint: .trailing)
                                )
                                .clipShape(Circle())
                                .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
                        }
                        .padding(.trailing, 20)
                        .padding(.bottom, 20)
                    }
                }
                .refreshable {
                    await db.loadPosts()
                }
                .task {
                    if db.posts.isEmpty {
                        await db.loadPosts()
                    }
                    await requestNotificationPermissionIfNeeded()
                    await db.loadNotifications()
                }
                .sheet(isPresented: $showNotifications) {
                    NotificationsSheet()
                }
                .sheet(item: Binding(
                    get: { selectedProfileUserId.map { ProfileId(id: $0) } },
                    set: { selectedProfileUserId = $0?.id }
                )) { userId in
                    NavigationStack {
                        ProfileView(userId: userId.id)
                            .toolbar {
                                ToolbarItem(placement: .navigationBarLeading) {
                                    Button("Close") {
                                        selectedProfileUserId = nil
                                    }
                                }
                            }
                    }
                }
            }
        }
    }

    private func requestNotificationPermissionIfNeeded() async {
        guard db.isAuthenticated else { return }
        guard !didRequestNotificationPermission else { return }
        didRequestNotificationPermission = true

        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
            if granted {
                await MainActor.run {
                    UIApplication.shared.registerForRemoteNotifications()
                }
            }
        } catch {
            print("Notification permission error: \(error)")
        }
    }
}

// MARK: - Notifications Sheet

struct NotificationsSheet: View {
    @EnvironmentObject var db: SelfDBManager
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationStack {
            Group {
                if db.notifications.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "bell.slash")
                            .font(.system(size: 50))
                            .foregroundColor(.gray)
                        Text("No notifications yet")
                            .font(.headline)
                            .foregroundColor(.secondary)
                    }
                } else {
                    List {
                        ForEach(db.notifications) { notification in
                            NotificationRow(notification: notification)
                                .onTapGesture {
                                    Task {
                                        await db.markNotificationAsRead(notification.id)
                                    }
                                }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Notifications")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                }
                
                if !db.notifications.isEmpty && db.unreadNotificationCount > 0 {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Mark All Read") {
                            Task {
                                await db.markAllNotificationsAsRead()
                            }
                        }
                        .font(.caption)
                    }
                }
            }
            .task {
                await db.loadNotifications()
            }
        }
    }
}

struct NotificationRow: View {
    let notification: AppNotification
    
    var body: some View {
        HStack(spacing: 12) {
            // Icon based on type
            Image(systemName: iconName)
                .font(.title2)
                .foregroundStyle(
                    LinearGradient(colors: [.orange, .blue], startPoint: .leading, endPoint: .trailing)
                )
                .frame(width: 40, height: 40)
                .background(Color(.systemGray6))
                .clipShape(Circle())
            
            VStack(alignment: .leading, spacing: 4) {
                Text(notification.title)
                    .font(.subheadline)
                    .fontWeight(notification.isRead ? .regular : .semibold)
                
                Text(notification.body)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                
                Text(notification.createdAt.timeAgo())
                    .font(.caption2)
                    .foregroundColor(.gray)
            }
            
            Spacer()
            
            if !notification.isRead {
                Circle()
                    .fill(Color.blue)
                    .frame(width: 8, height: 8)
            }
        }
        .padding(.vertical, 4)
        .opacity(notification.isRead ? 0.7 : 1)
    }
    
    private var iconName: String {
        switch notification.type {
        case "like":
            return "heart.fill"
        case "comment":
            return "bubble.left.fill"
        case "new_post":
            return "photo.fill"
        default:
            return "bell.fill"
        }
    }
}

struct ProfileId: Identifiable {
    let id: String
}

#Preview {
    FeedView(showCreatePost: .constant(false))
        .environmentObject(SelfDBManager.shared)
}
