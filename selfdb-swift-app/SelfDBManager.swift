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
    
    // MARK: - Internal state (accessible to extensions and context)
    internal var selfDB: SelfDB?
    internal var bucketId: String?
    
    // MARK: - Configuration --------------------------------------------------
    
    private let config = SelfDBConfig(
        apiURL: URL(string: "https://api.selfdb.io/api/v1")!,
        storageURL: URL(string: "https://storage.selfdb.io")!,
        apiKey: "cb14ecd3064c49478ce9b180f9aabdcd9375ae8f00a3cf33d7f6c95b737decca"
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
    
    internal func ensureUserBucket() async {
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
    internal func log(_ msg: String) { print("🪵 [SelfDBManager] \(msg)") }
    
    // MARK: - Topic helpers ---------------------------------------------------
    
    // Prevent concurrent topic calls
    internal var isFetchingTopics = false
    
    
    // MARK: - File helpers ----------------------------------------------------
    
    internal func uploadFile(data: Data, filename: String, bucketId: String) async -> String? {
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
    
    internal func resetError() { errorMessage = "" }
    
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
    
    // MARK: - Compatibility helpers for Views
    
    /// Old wrapper kept for UI compatibility.
    @MainActor
    func fetchAllData() async {
        await fetchTopics()
    }
    
    // These methods maintain compatibility with existing views
    // They now delegate to the model extensions that use the context pattern
    
    func createTopic(
        title: String,
        content: String,
        authorName: String,
        fileData: Data? = nil,
        filename: String? = nil
    ) async -> Topic? {
        await Topic.create(
            using: self,
            title: title,
            content: content,
            authorName: authorName,
            fileData: fileData,
            filename: filename
        )
    }
    
    func updateTopic(
        topicId: String,
        title: String,
        content: String,
        fileData: Data? = nil,
        filename: String? = nil,
        oldFileId: String? = nil,
        removeFile: Bool = false
    ) async -> Topic? {
        guard let topic = topics.first(where: { $0.id == topicId }) else { return nil }
        
        var updatedTopic = topic
        updatedTopic.title = title
        updatedTopic.content = content
        
        return await Topic.update(
            using: self,
            topic: updatedTopic,
            fileData: fileData,
            filename: filename,
            oldFileId: oldFileId,
            removeFile: removeFile
        )
    }
    
    func deleteTopic(topicId: String) async -> Bool {
        guard let topic = topics.first(where: { $0.id == topicId }) else { return false }
        return await Topic.delete(using: self, topic: topic)
    }
    
    func createComment(
        topicId: String,
        content: String,
        authorName: String,
        fileData: Data? = nil,
        filename: String? = nil
    ) async -> Comment? {
        await Comment.create(
            using: self,
            topicId: topicId,
            content: content,
            authorName: authorName,
            fileData: fileData,
            filename: filename
        )
    }
    
    func updateComment(
        commentId: String,
        content: String,
        fileData: Data? = nil,
        filename: String? = nil,
        oldFileId: String? = nil,
        removeFile: Bool = false
    ) async -> Comment? {
        // We need to fetch the comment first to get all its data
        let comments = await Comment.fetch(for: "", using: self)
        guard let comment = comments.first(where: { $0.id == commentId }) else { return nil }
        
        var updatedComment = comment
        updatedComment.content = content
        
        return await Comment.update(
            using: self,
            comment: updatedComment,
            fileData: fileData,
            filename: filename,
            oldFileId: oldFileId,
            removeFile: removeFile
        )
    }
    
    func deleteComment(commentId: String) async -> Bool {
        // We need to fetch the comment first
        let comments = await SelfDBContext<Comment>.fetch(filterColumn: "id", filterValue: commentId, manager: self)
        guard let comment = comments.first else { return false }
        return await Comment.delete(using: self, comment: comment)
    }
    

    // MARK: - Error handling
    internal func handle(error: SelfDBError, context: String) {
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
