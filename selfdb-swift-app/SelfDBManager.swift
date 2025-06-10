//
//  SelfDBManager.swift
//  selfd-swift
//
//  Created by rodgers magabo on 04/06/2025.
//

import Foundation
import SwiftUI
import SelfDB

@MainActor
final class SelfDBManager: ObservableObject {
    
    // MARK: - Public @Published state
    @Published var isConfigured      = false
    @Published var isAuthenticated   = false
    @Published var isLoading         = false
    @Published var errorMessage      = ""
    @Published var currentUser: User?
    @Published var topics: [Topic]   = []
    
    // MARK: - Private state
    private var selfDB: SelfDB?
    private var bucketId: String?
    
    // MARK: - Configuration --------------------------------------------------
    
    private let config = SelfDBConfig(
        apiURL: URL(string: "http://localhost:8000/api/v1")!,
        storageURL: URL(string: "http://localhost:8001")!,
        apiKey: "your-anon-key-here"
    )
    
    init() {
        configure()
    }
    
    private func configure() {
        selfDB = SelfDB(config: config)
        isConfigured = true
    }
    
    // MARK: - Authentication --------------------------------------------------
    
    func signUp(email: String, password: String) async {
        guard let sdk = selfDB else { return }
        resetError()
        isLoading = true
        
        // 1. Register user
        let registerResult = await sdk.auth.register(email: email, password: password)
        
        if registerResult.isSuccess {
            // 2. Immediately login to obtain tokens
            let loginResult = await sdk.auth.login(email: email, password: password)
            handleAuth(loginResult)
        } else {
            isLoading   = false
            errorMessage = registerResult.error?.localizedDescription ?? "Unknown error"
        }
    }
    
    func signIn(email: String, password: String) async {
        guard let sdk = selfDB else { return }
        resetError()
        isLoading = true
        
        let result = await sdk.auth.login(email: email, password: password)
        handleAuth(result)
    }
    
    func signOut() {
        guard let sdk = selfDB else { return }
        sdk.auth.signOut()
        currentUser      = nil
        isAuthenticated  = false
    }
    
    private func handleAuth(_ response: SelfDBResponse<AuthResponse>) {
        defer { isLoading = false }
        
        if response.isSuccess, let auth = response.data {
            currentUser     = User(
                id:          auth.user_id ?? "",
                email:       auth.email ?? "",
                is_active:   true,
                is_superuser: auth.is_superuser,
                created_at:  ISO8601DateFormatter().string(from: .init()),
                updated_at:  nil
            )
            isAuthenticated = true
            Task { await ensureUserBucket() }
        } else {
            errorMessage = response.error?.localizedDescription ?? "Unknown error"
        }
    }
    
    // MARK: - Bucket helpers --------------------------------------------------
    
    private func ensureUserBucket() async {
        guard let sdk = selfDB else { return }
        
        // 🚀 Always use the shared main bucket
        let bucketName = "discussion"
        
        let createReq  = CreateBucketRequest(name: bucketName, isPublic: true)
        
        let createRes  = await sdk.storage.createBucket(createReq)
        if createRes.isSuccess, let bucket = createRes.data {
            bucketId = bucket.id
            return
        }
        
        // If already exists → look it up
        let listRes = await sdk.storage.listBuckets()
        bucketId = listRes.data?.first(where: { $0.name == bucketName })?.id
    }
    
    // MARK: - Tiny logger ----------------------------------------------------
    private func log(_ msg: String) { print("🪵 [SelfDBManager] \(msg)") }
    
    // MARK: - Topic helpers ---------------------------------------------------
    
    // Prevent concurrent topic calls
    private var isFetchingTopics = false
    
    func fetchTopics() async {
        guard let sdk = selfDB else { return }
        // 🛑 already running?
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
        
        let res = await sdk.database.getTableData("topics", page: 1, pageSize: 100)
        
        if res.isSuccess, let table = res.data {
            let unsorted = table.data.compactMap(convertRowToTopic)
            // 🔽 newest first
            topics = unsorted.sorted { $0.createdAt > $1.createdAt }
            log("✅ fetched \(topics.count) topics (sorted newest-first)")
            
            // 🚫 No automatic comment-count fetch here – keep it to ONE topic call
            // If callers need comments they can call `fetchCommentsForTopic` explicitly.
        } else if let err = res.error {
            print(err.localizedDescription)
        } else {
            log("Unknown error in fetchTopics")
            errorMessage = "Unknown error while fetching topics."
        }
    }
    
    // MARK: –  Topics  -------------------------------------------------------
    
    /// Create and immediately append the new topic, then refresh full list
    @discardableResult
    func createTopic(
        title: String,
        content: String,
        authorName: String,
        fileData: Data? = nil,
        filename: String? = nil
    ) async -> Topic? {
        guard let sdk = selfDB else { return nil }
        resetError()
        
        // Ensure bucket exists for file uploads
        if fileData != nil && bucketId == nil {
            await ensureUserBucket()
        }
        
        var insert: [String: Any] = [
            "title":       title,
            "content":     content,
            "author_name": authorName
        ]
        // ⬇️ only attach user_id when we actually have one
        if let uid = currentUser?.id, !uid.isEmpty {
            insert["user_id"] = uid
        }

        if let data = fileData,
           let name = filename,
           let bucket = bucketId,
           let fileId = await uploadFile(data: data, filename: name, bucketId: bucket) {
            insert["file_id"] = fileId
        }
        
        let res = await sdk.database.insertRow("topics", data: insert)
        
        guard res.isSuccess,
              let row = res.data,
              let newTopic = convertRowToTopic(row)
        else {
            errorMessage = res.error?.localizedDescription ?? "Insert failed"
            return nil
        }
        
        await MainActor.run {
            // keep newest-first order
            topics.insert(newTopic, at: 0)
        }
        // 🚀 always refresh from server so counts & ordering stay correct
        Task { await fetchTopics() }
        return newTopic
    }
    
    /// Update on server and refresh list
    @discardableResult
    func updateTopic(
        topicId: String,
        title: String,
        content: String,
        fileData: Data? = nil,
        filename: String? = nil,
        oldFileId: String? = nil,
        removeFile: Bool = false                 // 🔹 NEW
    ) async -> Topic? {
        guard let sdk = selfDB else { return nil }
        
        // Ensure bucket exists for file uploads
        if fileData != nil && bucketId == nil {
            await ensureUserBucket()
        }
        
        var update: [String: Any] = [
            "title": title,
            "content": content
        ]
        if removeFile {                     // clear DB reference
            update["file_id"] = NSNull()
        }
        
        if let data = fileData {
            // 🔸 remove previous file first (ignore result)
            if let oldId = oldFileId {
                _ = await sdk.storage.deleteFile(oldId)
                FileURLCache.shared.invalidate(fileId: oldId)
            }
            if let name = filename,
               let bucket = bucketId,
               let fileId = await uploadFile(data: data, filename: name, bucketId: bucket) {
                update["file_id"] = fileId
            }
        }
        
        let res = await sdk.database.updateRow("topics", rowId: topicId, data: update)
        
        guard res.isSuccess,
              let row = res.data,                               // <- DICT, not array
              let updated = convertRowToTopic(row)
        else {
            errorMessage = res.error?.localizedDescription ?? "Update failed"
            return nil
        }
        
        await MainActor.run {
            if let idx = topics.firstIndex(where: { $0.id == topicId }) {
                topics[idx] = updated
            }
        }
        Task { await fetchTopics() }        // 🔄 pull fresh list
        return updated
    }
    
    /// Delete topic then *also* delete all attached comments & files
    @discardableResult
    func deleteTopic(topicId: String) async -> Bool {
        guard let sdk = selfDB else { return false }

        // 1️⃣ Load all comments belonging to the topic
        let commentsRes = await sdk.database.getTableData(
            "comments",
            page: 1,
            pageSize: 1_000,                 // plenty
            filterColumn: "topic_id",
            filterValue: topicId
        )
        if let commentRows = commentsRes.data?.data {
            for row in commentRows {
                if let fid = row["file_id"]?.value as? String {
                    _ = await sdk.storage.deleteFile(fid)   // ignore result
                    FileURLCache.shared.invalidate(fileId: fid)
                }
                if let cid = row["id"]?.value as? String {
                    _ = await sdk.database.deleteRow("comments", rowId: cid)
                }
            }
        }

        // 2️⃣ Delete topic-level file (if any)
        if let topicRow = (await sdk.database.getTableData(
            "topics",
            page: 1,
            pageSize: 1,
            filterColumn: "id",
            filterValue: topicId
        )).data?.data.first,
           let fid = topicRow["file_id"]?.value as? String {
            _ = await sdk.storage.deleteFile(fid)
            FileURLCache.shared.invalidate(fileId: fid)
        }

        // 3️⃣ Delete the topic itself
        let res = await sdk.database.deleteRow("topics", rowId: topicId)
        if res.isSuccess {
            await MainActor.run { topics.removeAll { $0.id == topicId } }
            return true
        }
        errorMessage = res.error?.localizedDescription ?? "Delete failed"
        return false
    }
    
    // MARK: - File helpers ----------------------------------------------------
    
    private func uploadFile(data: Data, filename: String, bucketId: String) async -> String? {
        guard let sdk = selfDB else { return nil }
        let req = InitiateUploadRequest(
            filename: filename,
            contentType: mimeType(for: filename),
            size: data.count,
            bucketId: bucketId
        )
        
        let initRes = await sdk.storage.initiateUpload(req)
        guard let info = initRes.data else { return nil }
        
        let uploadRes = await sdk.storage.uploadData(
            data,
            to: info.presigned_upload_info.upload_url,
            contentType: mimeType(for: filename)
        )
        return uploadRes.isSuccess ? info.file_metadata.id : nil
    }
    
    // MARK: - Utilities -------------------------------------------------------

    private func convertRowToTopic(_ row: [String: AnyCodable]) -> Topic? {
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

    // 🔽  NEW: maps raw row dictionary → Comment model
    private func convertRowToComment(_ row: [String: AnyCodable]) -> Comment? {
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

    private func mimeType(for filename: String) -> String {
        switch (filename as NSString).pathExtension.lowercased() {
        case "jpg", "jpeg": return "image/jpeg"
        case "png":         return "image/png"
        case "gif":         return "image/gif"
        case "mp4":         return "video/mp4"
        case "mov":         return "video/quicktime"
        case "pdf":         return "application/pdf"
        case "txt":         return "text/plain"
        default:            return "application/octet-stream"
        }
    }
    
    private func resetError() { errorMessage = "" }
    
    // -----------------------------------------------------------------------
    // MARK: - Compatibility helpers – used by the SwiftUI views
    // -----------------------------------------------------------------------
    
    /// Re-initialize the manager (called by the Retry button)
    func initialize() {
        configure()
        // Ensure bucket is ready for non-authenticated users
        Task { await ensureUserBucket() }
    }
    
    /// Refresh auth state when the app starts.
    func checkAuthState() {
        Task {
            guard let sdk = selfDB else { return }
            if sdk.auth.accessToken != nil {
                let res = await sdk.auth.getCurrentUser()
                if res.isSuccess, let user = res.data {
                    await MainActor.run {
                        self.currentUser     = user
                        self.isAuthenticated = true
                    }
                    await ensureUserBucket()
                }
            }
        }
    }
    
    // MARK: –  Topics --------------------------------------------------------
    
    /// Old wrapper kept for UI compatibility.
    @MainActor
    func fetchAllData() async {
        await fetchTopics()
    }
    
    // MARK: –  Comments ------------------------------------------------------
    /// Fetch comments for a topic (newest → oldest)
    func fetchCommentsForTopic(_ topicId: String,
                               page: Int = 1,
                               pageSize: Int = 100) async -> [Comment] {
        guard let sdk = selfDB else { return [] }

        let res = await sdk.database.getTableData(
            "comments",
            page: page,
            pageSize: pageSize,
            filterColumn: "topic_id",
            filterValue: topicId
        )

        guard res.isSuccess, let table = res.data else {
            if let err = res.error { self.handle(error: err, context: "fetchCommentsForTopic") }
            return []
        }

        return table.data
            .compactMap(convertRowToComment)
            .sorted { $0.createdAt > $1.createdAt }        // newest first
    }

    /// Quick helper – returns total number of comments for a topic
    func commentCount(for topicId: String) async -> Int {
        guard let sdk = selfDB else { return 0 }
        let res = await sdk.database.getTableData(
            "comments",
            page: 1,
            pageSize: 1,              // we only need metadata
            filterColumn: "topic_id",
            filterValue: topicId
        )
        if let meta = res.data?.metadata {
            return meta.total_count
        }
        return 0
    }

    /// Insert a new comment and refresh topics list (for live comment-counts)
    @discardableResult
    func createComment(topicId: String,
                       content: String,
                       authorName: String,
                       fileData: Data? = nil,
                       filename: String? = nil) async -> Comment? {
        guard let sdk = selfDB else { return nil }
        
        // Ensure bucket exists for file uploads
        if fileData != nil && bucketId == nil {
            await ensureUserBucket()
        }
        
        var insert: [String: Any] = [
            "topic_id":    topicId,
            "content":     content,
            "author_name": authorName
        ]
        // ⬇️ only attach user_id when we actually have one
        if let uid = currentUser?.id, !uid.isEmpty {
            insert["user_id"] = uid
        }

        if let data = fileData,
           let name = filename,
           let bucket = bucketId,
           let fileId = await uploadFile(data: data, filename: name, bucketId: bucket) {
            insert["file_id"] = fileId
        }

        let res = await sdk.database.insertRow("comments", data: insert)
        guard res.isSuccess, let row = res.data else { errorMessage = res.error?.localizedDescription ?? ""; return nil }
        // refresh topics so counts & ordering update in list view
        Task { await fetchTopics() }
        return convertRowToComment(row)
    }

    /// Update an existing comment
    @discardableResult
    func updateComment(
        commentId: String,
        content: String,
        fileData: Data? = nil,
        filename: String? = nil,
        oldFileId: String? = nil,
        removeFile: Bool = false
    ) async -> Comment? {
        guard let sdk = selfDB else { return nil }
        
        // Ensure bucket exists for file uploads
        if fileData != nil && bucketId == nil {
            await ensureUserBucket()
        }
        
        var update: [String: Any] = [
            "content": content
        ]
        if removeFile { update["file_id"] = NSNull() }
        
        if let data = fileData {
            if let oldId = oldFileId {
                _ = await sdk.storage.deleteFile(oldId)
                FileURLCache.shared.invalidate(fileId: oldId)
            }
            if let name = filename,
               let bucket = bucketId,
               let fileId = await uploadFile(data: data, filename: name, bucketId: bucket) {
                update["file_id"] = fileId
            }
        }

        let res = await sdk.database.updateRow("comments", rowId: commentId, data: update)
        guard res.isSuccess, let row = res.data else { errorMessage = res.error?.localizedDescription ?? ""; return nil }
        Task { await fetchTopics() }
        return convertRowToComment(row)
    }

    /// Delete a comment and its file (if present)
    @discardableResult
    func deleteComment(commentId: String) async -> Bool {
        guard let sdk = selfDB else { return false }

        // 1️⃣ Grab the comment to discover file_id
        let rowRes = await sdk.database.getTableData(
            "comments",
            page: 1,
            pageSize: 1,
            filterColumn: "id",
            filterValue: commentId
        )
        if let row = rowRes.data?.data.first,
           let fid = row["file_id"]?.value as? String {
            _ = await sdk.storage.deleteFile(fid)
            FileURLCache.shared.invalidate(fileId: fid)
        }

        // 2️⃣ Delete row
        let res = await sdk.database.deleteRow("comments", rowId: commentId)
        if res.isSuccess { Task { await fetchTopics() } }
        else { errorMessage = res.error?.localizedDescription ?? "" }
        return res.isSuccess
    }

    // MARK: - Centralised error handling -------------------------------------
    private func handle(error: SelfDBError, context: String) {
        // Ignore cancelled tasks – they are expected when views disappear
        if case .networkError(let nsError as NSError) = error,
           nsError.code == NSURLErrorCancelled {
            log("⚠️ \(context): Task cancelled, ignoring")
            return
        }

        log("❌ \(context): \(error.localizedDescription)")
        errorMessage = error.localizedDescription
    }

    // MARK: –  File helpers ---------------------------------------------------
    /// Return a download URL for a file (handles public / private logic)
    func getFileDownloadURL(fileId: String) async -> String? {
        guard let sdk = selfDB else { return nil }
        let res: SelfDBResponse<FileDownloadInfo>

        if isAuthenticated {
            res = await sdk.storage.getFileDownloadInfo(fileId)
        } else {
            res = await sdk.storage.getPublicFileDownloadInfo(fileId)
        }

        if !res.isSuccess, let err = res.error {
            handle(error: err, context: "getFileDownloadURL")
        }
        return res.data?.download_url
    }
    
    /// Helper – delete a remote file directly
    @discardableResult
    func deleteRemoteFile(_ fileId: String) async -> Bool {
        guard let sdk = selfDB else { return false }
        let result = await sdk.storage.deleteFile(fileId)
        if result.isSuccess {
            FileURLCache.shared.invalidate(fileId: fileId)
        }
        return result.isSuccess
    }
}
