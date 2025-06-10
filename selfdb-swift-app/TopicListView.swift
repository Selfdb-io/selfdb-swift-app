//
//  TopicListView.swift
//  selfd-swift
//
//  Created by rodgers magabo on 04/06/2025.
//

import SwiftUI

struct TopicListView: View {
    @ObservedObject var selfDBManager: SelfDBManager
    let onShowAuthModal: () -> Void
    let onCreateTopic: () -> Void
    @State private var searchText = ""
    @State private var hasInitiallyLoaded = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header matching Expo design
            headerView
            
            // Content
            if !selfDBManager.isConfigured {
                initializationView
            } else {
                topicListView
            }
        }
        .background(Color(.systemGray6))
        .refreshable {
            FileURLCache.shared.invalidateAll() // Clear cache on refresh
            _ = await Topic.fetchAll(using: selfDBManager)
        }
        .task {
            // Only fetch once on initial load
            if !hasInitiallyLoaded && selfDBManager.isConfigured {
                hasInitiallyLoaded = true
                _ = await Topic.fetchAll(using: selfDBManager)
                // Preload file URLs for topics with files
                await preloadFileURLs()
            }
        }
    }
    
    private var initializationView: some View {
        VStack(spacing: 20) {
            if selfDBManager.isLoading {
                ProgressView("Connecting to SelfDB...")
                    .scaleEffect(1.2)
            } else if !selfDBManager.errorMessage.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 50))
                        .foregroundColor(.orange)
                    
                    Text("Connection Error")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text(selfDBManager.errorMessage)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    
                    Button("Retry") {
                        Task {
                            hasInitiallyLoaded = false
                            await selfDBManager.fetchAllData()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var headerView: some View {
        HStack {
            // Logo and title
            HStack(spacing: 12) {
                // Replaced placeholder with AppIcon image
                Image("icon")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 40, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                
                Text("Open Discussion Board")
                    .font(.title3)
                    .fontWeight(.semibold)
            }
            
            Spacer()
            
            // User/Auth button
            Button {
                if selfDBManager.isAuthenticated {
                    Task {
                        selfDBManager.signOut()
                    }
                } else {
                    onShowAuthModal()
                }
            } label: {
                if selfDBManager.isAuthenticated {
                    // User avatar
                    Circle()
                        .fill(Color.blue.opacity(0.2))
                        .frame(width: 32, height: 32)
                        .overlay {
                            Text(selfDBManager.currentUser?.email.prefix(1).uppercased() ?? "U")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.blue)
                        }
                } else {
                    // Login icon
                    Image(systemName: "person.circle")
                        .font(.title2)
                        .foregroundColor(.blue)
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(.systemBackground))
        .shadow(color: .black.opacity(0.1), radius: 1, x: 0, y: 1)
    }
    
    private var topicListView: some View {
        ZStack(alignment: .bottomTrailing) {
            VStack {
                if selfDBManager.isLoading && selfDBManager.topics.isEmpty {
                    ProgressView("Loading topics...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if selfDBManager.topics.isEmpty {
                    emptyStateView
                } else {
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            ForEach(filteredTopics) { topic in
                                NavigationLink(
                                    destination: TopicDetailView(topic: topic, selfDBManager: selfDBManager)
                                ) {
                                    TopicCardView(topic: topic, selfDBManager: selfDBManager)
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                        .padding(.horizontal)
                        .padding(.top)
                    }
                }
            }
            
            // Floating action button
            Button {
                onCreateTopic()
            } label: {
                Image(systemName: "plus")
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
        .overlay(alignment: .bottom) {
            if selfDBManager.isLoading && !selfDBManager.topics.isEmpty {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Refreshing...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(8)
                .background(.regularMaterial, in: Capsule())
                .padding(.bottom, 80)
            }
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: selfDBManager.errorMessage.isEmpty ? "text.bubble" : "exclamationmark.triangle")
                .font(.system(size: 60))
                .foregroundColor(selfDBManager.errorMessage.isEmpty ? .secondary : .orange)
            
            Text(selfDBManager.errorMessage.isEmpty ? "No Topics Yet" : "Welcome to SelfDB!")
                .font(.title2)
                .fontWeight(.semibold)
            
            if !selfDBManager.errorMessage.isEmpty {
                Text(selfDBManager.errorMessage)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                if !selfDBManager.isAuthenticated {
                    Button("Sign In") {
                        onShowAuthModal()
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else {
                Text("There are no topics available at the moment.")
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            Button("Refresh") {
                Task {
                    await selfDBManager.fetchAllData()
                }
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var filteredTopics: [Topic] {
        if searchText.isEmpty {
            return selfDBManager.topics
        } else {
            return selfDBManager.topics.filter { topic in
                topic.title.localizedCaseInsensitiveContains(searchText) ||
                topic.content.localizedCaseInsensitiveContains(searchText) ||
                topic.authorName.localizedCaseInsensitiveContains(searchText)
            }
        }
    }
    
    private func preloadFileURLs() async {
        // Preload URLs for the first 10 topics with files
        let topicsWithFiles = selfDBManager.topics
            .filter { $0.hasFile && $0.fileId != nil }
            .prefix(10)
        
        await withTaskGroup(of: Void.self) { group in
            for topic in topicsWithFiles {
                if let fileId = topic.fileId {
                    group.addTask {
                        // Check if already cached
                        if FileURLCache.shared.getURL(for: fileId) == nil {
                            if let url = await selfDBManager.getFileDownloadURL(fileId: fileId) {
                                FileURLCache.shared.setURL(url, for: fileId)
                            }
                        }
                    }
                }
            }
        }
    }
}

struct TopicCardView: View {
    let topic: Topic
    @ObservedObject var selfDBManager: SelfDBManager
    @State private var commentCount: Int = 0
    @State private var isLoadingCount: Bool = true
    @State private var loadTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Title
            Text(topic.title)
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            
            // 🖼 FILE PREVIEW -------------------------------------------------
            if topic.hasFile, let fileId = topic.fileId {
                FileViewer(fileId: fileId, selfDBManager: selfDBManager)
                    .frame(maxHeight: 200)   // keep in-sync with FileViewer.thumbnailHeight
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            // Content preview
            Text(topic.content)
                .font(.body)
                .foregroundColor(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            
            // Meta information
            HStack {
                // Author
                Text("By \(topic.authorName)")
                    .font(.caption)
                    .foregroundColor(.blue)
                    .fontWeight(.medium)
                
                Spacer()
                
                // Created date
                Text(formatRelativeDate(topic.createdAt))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            // Comments count
            if isLoadingCount {
                Text("Loading comments …")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .italic()
            } else {
                Text("\(commentCount) comment\(commentCount == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .italic()
            }
        }
        .padding(16)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
        .onAppear {
            loadTask?.cancel()
            loadTask = Task {
                let count = await selfDBManager.commentCount(for: topic.id)
                await MainActor.run {
                    self.commentCount = count
                    self.isLoadingCount = false
                }
            }
        }
        .onDisappear { loadTask?.cancel() }
    }
}

#Preview {
    TopicListView(
        selfDBManager: SelfDBManager(),
        onShowAuthModal: {},
        onCreateTopic: {}
    )
}
