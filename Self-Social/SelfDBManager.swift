//
//  SelfDBManager.swift
//  Self-Social
//
//  Single manager that wraps the SelfDB iOS SDK for all operations
//

import Foundation
import SelfDB
import Combine

// Import SortOrder explicitly from SelfDB to avoid ambiguity with Foundation
import enum SelfDB.SortOrder

// MARK: - SelfDB Manager

@MainActor
final class SelfDBManager: ObservableObject {
    static let shared = SelfDBManager()
    
    // MARK: - SelfDB Client
    
    let client = SelfDB(
        baseUrl: "http://localhost:8000",
        apiKey: "selfdb-your-api-key-here"
    )
    
    // MARK: - Table & Bucket Names
    
    enum Table: String, CaseIterable {
        case posts, postFiles = "post_files", likes, comments
        case deviceTokens = "device_tokens", notifications
    }
    
    enum Bucket: String { case postMedia = "post-media" }
    
    // MARK: - Published State
    
    @Published var currentUser: UserRead?
    @Published var isAuthenticated = false
    @Published var isInitializing = true
    @Published var isLoadingPosts = false
    @Published var posts: [PostWithDetails] = []
    @Published var error: String?
    @Published var notifications: [AppNotification] = []
    @Published var unreadNotificationCount: Int = 0
    
    var deviceToken: String?
    
    // MARK: - Caches
    
    private var tableIds: [Table: String] = [:]
    private var bucketIds: [Bucket: String] = [:]
    private var loadPostsTask: Task<Void, Never>?
    private let accessTokenKey = "self_social_access_token"
    private let refreshTokenKey = "self_social_refresh_token"
    
    private init() {}
    
    // MARK: - Token Management
    
    private var accessToken: String? { UserDefaults.standard.string(forKey: accessTokenKey) }
    private var refreshToken: String? { UserDefaults.standard.string(forKey: refreshTokenKey) }
    
    private func saveTokens(access: String, refresh: String) {
        UserDefaults.standard.set(access, forKey: accessTokenKey)
        UserDefaults.standard.set(refresh, forKey: refreshTokenKey)
    }
    
    private func clearTokens() {
        UserDefaults.standard.removeObject(forKey: accessTokenKey)
        UserDefaults.standard.removeObject(forKey: refreshTokenKey)
    }
    
    // MARK: - SDK Helpers (DRY wrappers around SDK)
    
    /// Get cached table ID or fetch and cache it
    private func tableId(_ table: Table) async throws -> String {
        if let id = tableIds[table] { return id }
        let tables = try await client.tables.list(search: table.rawValue)
        guard let found = tables.first(where: { $0.name == table.rawValue }) else {
            throw ManagerError.tableNotFound(table.rawValue)
        }
        tableIds[table] = found.id
        return found.id
    }
    
    /// Get cached bucket ID or fetch and cache it
    private func bucketId(_ bucket: Bucket) async throws -> String {
        if let id = bucketIds[bucket] { return id }
        let buckets = try await client.storage.buckets.list(search: bucket.rawValue)
        guard let found = buckets.first(where: { $0.name == bucket.rawValue }) else {
            throw ManagerError.bucketNotFound(bucket.rawValue)
        }
        bucketIds[bucket] = found.id
        return found.id
    }
    
    /// Generic decode from AnyCodable dictionary
    private func decode<T: Decodable>(_ dict: [String: AnyCodable]) -> T? {
        guard let data = try? JSONEncoder().encode(dict) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
    
    /// Fetch all rows from table, decode to type
    private func fetchRows<T: Decodable>(_ table: Table, limit: Int = 1000, sortBy: String? = nil, sortOrder: SortOrder = .desc) async throws -> [T] {
        let id = try await tableId(table)
        let response = try await client.tables.data.fetch(
            id,
            page: 1,
            pageSize: limit,
            sortBy: sortBy,
            sortOrder: sortBy == nil ? nil : sortOrder,
            search: nil
        )
        return response.data.compactMap { decode($0) }
    }
    
    /// Insert row into table
    private func insert(_ table: Table, data: [String: AnyCodable]) async throws -> String {
        let id = try await tableId(table)
        let response = try await client.tables.data.insert(id, data: data)
        return try extractId(response)
    }
    
    /// Update row in table
    private func update(_ table: Table, rowId: String, data: [String: AnyCodable]) async throws {
        let id = try await tableId(table)
        _ = try await client.tables.data.updateRow(id, rowId: rowId, updates: data)
    }
    
    /// Delete row from table
    private func delete(_ table: Table, rowId: String) async throws {
        let id = try await tableId(table)
        _ = try await client.tables.data.deleteRow(id, rowId: rowId)
    }
    
    /// Extract ID from response
    private func extractId(_ response: [String: AnyCodable]) throws -> String {
        if let id = response["id"]?.stringValue ?? (response["id"]?.value as? String) {
            return id
        }
        if let data = response["data"]?.dictionaryValue, let id = data["id"] as? String {
            return id
        }
        throw ManagerError.invalidResponse
    }
    
    /// Require authenticated user
    private func requireUser() throws -> UserRead {
        guard let user = currentUser else { throw ManagerError.notAuthenticated }
        return user
    }
    
    /// Delete storage files for a PostFile
    private func deleteStorageFiles(_ file: PostFile) async {
        try? await client.storage.files.delete(file.fileId)
        if let thumbId = file.thumbnailFileId { try? await client.storage.files.delete(thumbId) }
    }
    
    /// Upload media and create post_files record
    private func uploadMedia(postId: String, userId: String, media: MediaItem, order: Int) async throws {
        let bucket = try await bucketId(.postMedia)
        let ts = Int(Date().timeIntervalSince1970 * 1000)
        let filename = "\(postId)/\(ts)-\(order).\(media.fileExtension)"
        
        let upload = try await client.storage.files.upload(bucket, filename: filename, data: media.data, path: filename)
        let fileUrl = "\(client.baseUrl)/storage/files/download/\(Bucket.postMedia.rawValue)/\(filename)"
        
        var data: [String: AnyCodable] = [
            "post_id": AnyCodable(postId), "user_id": AnyCodable(userId),
            "file_id": AnyCodable(upload.fileId), "file_url": AnyCodable(fileUrl),
            "file_type": AnyCodable(media.type.rawValue), "display_order": AnyCodable(order)
        ]
        
        if media.type == .video, let thumbData = media.thumbnailData {
            let thumbName = "\(postId)/\(ts)-\(order)-thumb.png"
            let thumbUpload = try await client.storage.files.upload(bucket, filename: thumbName, data: thumbData, path: thumbName)
            data["thumbnail_file_id"] = AnyCodable(thumbUpload.fileId)
            data["thumbnail_url"] = AnyCodable("\(client.baseUrl)/storage/files/download/\(Bucket.postMedia.rawValue)/\(thumbName)")
        }
        
        _ = try await insert(.postFiles, data: data)
    }
    
    private func preloadIds() async {
        if let tables = try? await client.tables.list(limit: 250) {
            for t in tables {
                if let key = Table(rawValue: t.name) { tableIds[key] = t.id }
            }
        }

        if let buckets = try? await client.storage.buckets.list(limit: 250) {
            for b in buckets {
                if let key = Bucket(rawValue: b.name) { bucketIds[key] = b.id }
            }
        }
    }
    
    // MARK: - Auth Operations
    
    func initializeAuth() async {
        defer { isInitializing = false }
        guard accessToken != nil else { return }
        
        do {
            currentUser = try await client.auth.me()
            isAuthenticated = true
            await preloadIds()
        } catch {
            if let refresh = refreshToken,
               let tokens = try? await client.auth.refresh(refreshToken: refresh) {
                saveTokens(access: tokens.accessToken, refresh: tokens.refreshToken)
                currentUser = try? await client.auth.me()
                isAuthenticated = currentUser != nil
                if isAuthenticated { await preloadIds() }
            } else {
                clearTokens()
            }
        }
    }
    
    func login(email: String, password: String) async throws {
        let tokens = try await client.auth.login(email: email, password: password)
        saveTokens(access: tokens.accessToken, refresh: tokens.refreshToken)
        currentUser = try await client.auth.me()
        isAuthenticated = true
        await preloadIds()
        if let token = deviceToken { await registerDeviceToken(token) }
    }
    
    func register(email: String, password: String, firstName: String, lastName: String) async throws {
        _ = try await client.auth.users.create(payload: UserCreate(email: email, password: password, firstName: firstName, lastName: lastName))
        try await login(email: email, password: password)
    }
    
    func logout() async {
        if let token = deviceToken { await removeDeviceToken(token) }
        if let refresh = refreshToken { _ = try? await client.auth.logout(refreshToken: refresh) }
        clearTokens()
        tableIds.removeAll()
        bucketIds.removeAll()
        currentUser = nil
        isAuthenticated = false
        posts = []
        notifications = []
        unreadNotificationCount = 0
    }
    
    /// Fetch a user by ID
    func getUser(_ userId: String) async throws -> UserRead {
        return try await client.auth.users.get(userId)
    }
    
    // MARK: - Posts Operations
    
    func loadPosts() async {
        loadPostsTask?.cancel()
        guard let user = currentUser, !isLoadingPosts else { return }
        
        isLoadingPosts = true
        error = nil
        
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.isLoadingPosts = false }
            
            do {
                try Task.checkCancellation()
                
                let recentPosts: [Post] = try await self.fetchRows(.posts, limit: 50, sortBy: "created_at", sortOrder: .desc)
                let allFiles: [PostFile] = try await self.fetchRows(.postFiles)
                let allLikes: [Like] = try await self.fetchRows(.likes)
                let allComments: [Comment] = try await self.fetchRows(.comments)

                let filesByPostId = Dictionary(grouping: allFiles, by: \.postId)
                let likesByPostId = Dictionary(grouping: allLikes, by: \.postId)
                let commentsByPostId = Dictionary(grouping: allComments, by: \.postId)
                let likedPostIds = Set(allLikes.filter { $0.userId == user.id }.map { $0.postId })
                
                try Task.checkCancellation()
                
                var results: [PostWithDetails] = []
                for post in recentPosts {
                    try Task.checkCancellation()
                    
                    let postFiles = (filesByPostId[post.id] ?? []).sorted { $0.displayOrder < $1.displayOrder }
                    var filesWithData: [PostFileWithData] = []
                    
                    for pf in postFiles {
                        var fd = PostFileWithData(postFile: pf)
                        if pf.isImage, let data = try? await self.downloadFile(url: pf.fileUrl) {
                            fd.imageData = data
                        } else if pf.isVideo, let thumb = pf.thumbnailUrl, let data = try? await self.downloadFile(url: thumb) {
                            fd.thumbnailData = data
                        }
                        filesWithData.append(fd)
                    }
                    
                    let postLikes = likesByPostId[post.id] ?? []
                    results.append(PostWithDetails(
                        post: post,
                        files: filesWithData,
                        likesCount: postLikes.count,
                        commentsCount: commentsByPostId[post.id]?.count ?? 0,
                        userHasLiked: likedPostIds.contains(post.id),
                        author: try? await self.client.auth.users.get(post.userId)
                    ))
                }
                
                try Task.checkCancellation()
                self.posts = results
            } catch is CancellationError {
                print("Load posts cancelled")
            } catch {
                self.error = error.localizedDescription
            }
        }
        
        loadPostsTask = task
        await task.value
    }
    
    func createPost(description: String?, mediaItems: [MediaItem]) async throws {
        let user = try requireUser()
        let postId = try await insert(.posts, data: [
            "user_id": AnyCodable(user.id),
            "description": AnyCodable(description as Any)
        ])
        for (i, media) in mediaItems.enumerated() {
            try await uploadMedia(postId: postId, userId: user.id, media: media, order: i)
        }
        await loadPosts()
    }
    
    func updatePost(postId: String, description: String?, newMediaItems: [MediaItem], filesToDelete: [PostFileWithData], reorderedExistingFiles: [PostFileWithData] = []) async throws {
        let user = try requireUser()
        
        try await update(.posts, rowId: postId, data: ["description": AnyCodable(description as Any)])
        
        for file in filesToDelete {
            await deleteStorageFiles(file.postFile)
            try? await delete(.postFiles, rowId: file.id)
        }
        
        for (i, file) in reorderedExistingFiles.enumerated() {
            try? await update(.postFiles, rowId: file.id, data: ["display_order": AnyCodable(i)])
        }
        
        for (i, media) in newMediaItems.enumerated() {
            try await uploadMedia(postId: postId, userId: user.id, media: media, order: reorderedExistingFiles.count + i)
        }
        
        await loadPosts()
    }
    
    func deletePost(_ postId: String) async throws {
        let files: [PostFile] = try await fetchRows(Table.postFiles)
        for file in files.filter({ $0.postId == postId }) { await deleteStorageFiles(file) }
        try await delete(Table.posts, rowId: postId)
        posts.removeAll { $0.id == postId }
    }
    
    // MARK: - Likes Operations
    
    func toggleLike(postId: String) async {
        guard let user = currentUser, let idx = posts.firstIndex(where: { $0.id == postId }) else { return }
        
        let wasLiked = posts[idx].userHasLiked
        posts[idx].userHasLiked = !wasLiked
        posts[idx].likesCount += wasLiked ? -1 : 1
        
        do {
            if wasLiked {
                let likes: [Like] = try await fetchRows(Table.likes)
                if let like = likes.first(where: { $0.postId == postId && $0.userId == user.id }) {
                    try await delete(Table.likes, rowId: like.id)
                }
            } else {
                _ = try await insert(.likes, data: ["post_id": AnyCodable(postId), "user_id": AnyCodable(user.id)])
            }
        } catch {
            posts[idx].userHasLiked = wasLiked
            posts[idx].likesCount += wasLiked ? 1 : -1
        }
    }
    
    // MARK: - Comments Operations
    
    func loadComments(postId: String) async throws -> [CommentWithAuthor] {
        let comments: [Comment] = try await fetchRows(Table.comments)
        var results: [CommentWithAuthor] = []
        for c in comments.filter({ $0.postId == postId }).sorted(by: { $0.createdAt > $1.createdAt }) {
            let name = (try? await client.auth.users.get(c.userId)).map { "\($0.firstName ?? "") \($0.lastName ?? "")" } ?? "Unknown"
            results.append(CommentWithAuthor(comment: c, authorName: name))
        }
        return results
    }
    
    func addComment(postId: String, content: String) async throws {
        let user = try requireUser()
        _ = try await insert(.comments, data: ["post_id": AnyCodable(postId), "user_id": AnyCodable(user.id), "content": AnyCodable(content)])
        if let idx = posts.firstIndex(where: { $0.id == postId }) { posts[idx].commentsCount += 1 }
    }
    
    func updateComment(commentId: String, content: String) async throws {
        try await update(.comments, rowId: commentId, data: ["content": AnyCodable(content)])
    }
    
    func deleteComment(commentId: String, postId: String) async throws {
        try await delete(.comments, rowId: commentId)
        if let idx = posts.firstIndex(where: { $0.id == postId }) { posts[idx].commentsCount -= 1 }
    }
    
    // MARK: - File Download
    
    func downloadFile(url: String) async throws -> Data {
        let marker = "/download/\(Bucket.postMedia.rawValue)/"
        guard let range = url.range(of: marker) else { throw ManagerError.invalidResponse }
        return try await client.storage.files.download(bucketName: Bucket.postMedia.rawValue, path: String(url[range.upperBound...]))
    }
    
    // MARK: - Device Token & Notifications
    
    func registerDeviceToken(_ token: String) async {
        guard let user = currentUser else { return }
        deviceToken = token
        
        do {
            let tokens: [DeviceToken] = try await fetchRows(.deviceTokens, limit: 1000)

            if let existing = tokens.first(where: { $0.deviceToken == token }) {
                try await update(.deviceTokens, rowId: existing.id, data: [
                    "user_id": AnyCodable(user.id),
                    "updated_at": AnyCodable(ISO8601DateFormatter().string(from: Date()))
                ])
            } else {
                _ = try await insert(.deviceTokens, data: [
                    "user_id": AnyCodable(user.id),
                    "device_token": AnyCodable(token),
                    "platform": AnyCodable("ios")
                ])
            }
        } catch { print("Failed to register device token: \(error)") }
    }
    
    func removeDeviceToken(_ token: String) async {
        do {
            let tokens: [DeviceToken] = try await fetchRows(.deviceTokens, limit: 1000)
            if let existing = tokens.first(where: { $0.deviceToken == token }) {
                try await delete(.deviceTokens, rowId: existing.id)
            }
        } catch { print("Failed to remove device token: \(error)") }
    }
    
    func loadNotifications() async {
        guard let user = currentUser else { return }
        do {
            let all: [AppNotification] = try await fetchRows(Table.notifications, limit: 50, sortBy: "created_at")
            notifications = all.filter { $0.userId == user.id }
            unreadNotificationCount = notifications.filter { !$0.isRead }.count
        } catch { print("Failed to load notifications: \(error)") }
    }
    
    func markNotificationAsRead(_ notificationId: String) async {
        do {
            try await update(.notifications, rowId: notificationId, data: ["is_read": AnyCodable(true)])
            if let idx = notifications.firstIndex(where: { $0.id == notificationId }) {
                notifications[idx].isRead = true
                unreadNotificationCount = notifications.filter { !$0.isRead }.count
            }
        } catch { print("Failed to mark notification as read: \(error)") }
    }
    
    func markAllNotificationsAsRead() async {
        guard currentUser != nil else { return }
        for n in notifications where !n.isRead { try? await update(.notifications, rowId: n.id, data: ["is_read": AnyCodable(true)]) }
        for i in notifications.indices { notifications[i].isRead = true }
        unreadNotificationCount = 0
    }
}

// MARK: - Error Types

enum ManagerError: LocalizedError {
    case tableNotFound(String), bucketNotFound(String), notAuthenticated, invalidResponse
    
    var errorDescription: String? {
        switch self {
        case .tableNotFound(let n): return "Table '\(n)' not found."
        case .bucketNotFound(let n): return "Bucket '\(n)' not found."
        case .notAuthenticated: return "You must be logged in."
        case .invalidResponse: return "Invalid response from server."
        }
    }
}
