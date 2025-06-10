//
//  AddCommentView.swift
//  selfd-swift
//
//  Created by rodgers magabo on 04/06/2025.
//

import SwiftUI
import PhotosUI

struct AddCommentView: View {
    @Binding var isPresented: Bool
    let topicId: String
    @ObservedObject var selfDBManager: SelfDBManager
    let onCommentAdded: (Comment) -> Void
    
    // Edit mode properties
    var editingComment: Comment? = nil
    var isEditMode: Bool { editingComment != nil }
    
    // Delete callback for edit mode (optional)
    var onCommentDeleted: (() -> Void)? = nil
    
    @State private var content = ""
    @State private var authorName = ""
    @State private var isLoading = false
    @State private var errorMessage = ""
    
    // Media upload
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var selectedMediaData: Data?
    @State private var selectedFileName: String?
    @State private var showingCamera = false
    @State private var capturedImage: UIImage?
    @State private var selectedMediaType: String?
    @State private var remoteFileId: String? = nil
    @State private var remoteFileRemoved = false
    @State private var fileViewerKey = UUID()

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Form fields
                VStack(spacing: 16) {
                    // Show name field only when user is not logged in and not editing
                    if !selfDBManager.isAuthenticated && !isEditMode {
                        TextField("Your name", text: $authorName)
                            .textFieldStyle(CustomTextFieldStyle())
                    }
                    
                    TextField("Write your comment...", text: $content, axis: .vertical)
                        .textFieldStyle(CustomTextFieldStyle())
                        .lineLimit(4...8)
                }
                .padding(.horizontal)
                
                // Media upload section
                VStack(spacing: 12) {
                    if remoteFileId != nil && selectedMediaData == nil && !remoteFileRemoved {
                        VStack {
                            if let fid = remoteFileId {
                                FileViewer(fileId: fid, selfDBManager: selfDBManager)
                                    .id(fileViewerKey)
                                    .frame(maxHeight: 200)
                                    .cornerRadius(12)
                                
                                Button("Remove File") {
                                    Task {
                                        _ = await selfDBManager.deleteRemoteFile(fid)
                                        remoteFileRemoved = true
                                        remoteFileId = nil
                                        FileURLCache.shared.invalidate(fileId: fid)
                                        fileViewerKey = UUID()
                                    }
                                }
                                .foregroundColor(.red)
                                .font(.caption)
                            }
                        }
                        .padding()
                        .background(Color.gray.opacity(0.05))
                        .cornerRadius(12)
                        .padding(.horizontal)
                    } else if let mediaData = selectedMediaData {
                        // Show selected media
                        VStack {
                            if selectedMediaType?.starts(with: "image/") == true, let uiImage = UIImage(data: mediaData) {
                                // Display image
                                Image(uiImage: uiImage)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(maxHeight: 200)
                                    .cornerRadius(12)
                            } else if selectedMediaType?.starts(with: "video/") == true {
                                // Display video placeholder
                                VStack {
                                    Image(systemName: "video.fill")
                                        .font(.system(size: 50))
                                        .foregroundColor(.blue)
                                    Text("Video Selected")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .frame(height: 150)
                                .frame(maxWidth: .infinity)
                                .background(Color.gray.opacity(0.1))
                                .cornerRadius(12)
                            }
                            
                            Button("Remove Media") {
                                clearSelectedMedia()
                            }
                            .foregroundColor(.red)
                            .font(.caption)
                        }
                        .padding()
                        .background(Color.gray.opacity(0.05))
                        .cornerRadius(12)
                        .padding(.horizontal)
                    } else {
                        // Media upload buttons
                        HStack(spacing: 16) {
                            Button {
                                showingCamera = true
                            } label: {
                                VStack {
                                    Image(systemName: "camera")
                                        .font(.title2)
                                        .foregroundColor(.blue)
                                    Text("Camera")
                                        .font(.caption)
                                        .foregroundColor(.primary)
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.gray.opacity(0.1))
                                .cornerRadius(12)
                            }
                            
                            PhotosPicker(selection: $selectedPhotoItem, matching: .any(of: [.images, .videos])) {
                                VStack {
                                    Image(systemName: "photo.on.rectangle")
                                        .font(.title2)
                                        .foregroundColor(.blue)
                                    Text("Photos & Videos")
                                        .font(.caption)
                                        .foregroundColor(.primary)
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.gray.opacity(0.1))
                                .cornerRadius(12)
                            }
                        }
                        .padding(.horizontal)
                    }
                }
                
                // Error message
                if !errorMessage.isEmpty {
                    Text(errorMessage)
                        .foregroundColor(.red)
                        .font(.caption)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                
                Spacer()
                
                // Post/Update button
                Button {
                    if isEditMode {
                        updateComment()
                    } else {
                        postComment()
                    }
                } label: {
                    HStack {
                        if isLoading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(0.8)
                        }
                        Text(isEditMode ? "Update" : "Post")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(isFormValid ? Color.blue : Color.gray)
                    .foregroundColor(.white)
                    .cornerRadius(25)
                }
                .disabled(!isFormValid || isLoading)
                .padding(.horizontal)
                .padding(.bottom)
            }
            .navigationTitle(isEditMode ? "Edit Comment" : "Add Comment")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        isPresented = false
                    } label: {
                        Image(systemName: "xmark")
                            .foregroundColor(.blue)
                    }
                }
                
                if isEditMode {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            deleteComment()
                        } label: {
                            Image(systemName: "trash")
                                .foregroundColor(.red)
                        }
                    }
                }
            }
        }
        .modifier(PhotoPickerChangeModifier(selectedPhotoItem: selectedPhotoItem) { newItem in
            Task {
                if let newItem = newItem {
                    await loadPhotoData(from: newItem)
                }
            }
        })
        .fullScreenCover(isPresented: $showingCamera) {
            CameraView { image in
                capturedImage = image
                if let imageData = image.jpegData(compressionQuality: 0.8) {
                    selectedMediaData = imageData
                    selectedFileName = "captured_comment_\(UUID().uuidString).jpg"
                    selectedMediaType = "image/jpeg"
                }
                showingCamera = false
            }
        }
        .onAppear {
            // Pre-fill fields if editing
            if let comment = editingComment {
                content = comment.content
                authorName = comment.authorName
                remoteFileId = comment.fileId
            }
        }
    }
    
    private var isFormValid: Bool {
        let contentValid = !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let nameValid = selfDBManager.isAuthenticated || !authorName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        
        return contentValid && nameValid
    }
    
    private func loadPhotoData(from item: PhotosPickerItem) async {
        do {
            if let data = try await item.loadTransferable(type: Data.self) {
                await MainActor.run {
                    selectedMediaData = data
                    
                    // Determine the media type
                    if item.supportedContentTypes.contains(where: { $0.conforms(to: .image) }) {
                        selectedMediaType = "image/jpeg"
                        selectedFileName = "selected_comment_\(UUID().uuidString).jpg"
                    } else if item.supportedContentTypes.contains(where: { $0.conforms(to: .movie) }) {
                        selectedMediaType = "video/mp4"
                        selectedFileName = "selected_comment_\(UUID().uuidString).mp4"
                    } else {
                        selectedMediaType = "application/octet-stream"
                        selectedFileName = "selected_comment_\(UUID().uuidString)"
                    }
                }
            }
        } catch {
            await MainActor.run {
                errorMessage = "Failed to load media: \(error.localizedDescription)"
            }
        }
    }
    
    private func clearSelectedMedia() {
        selectedMediaData = nil
        selectedFileName = nil
        selectedMediaType = nil
        selectedPhotoItem = nil
        capturedImage = nil
    }
    
    private func postComment() {
        guard isFormValid else { return }
        
        isLoading = true
        errorMessage = ""
        
        Task {
            let finalAuthorName = selfDBManager.isAuthenticated ? 
                (selfDBManager.currentUser?.email ?? "Anonymous") : 
                authorName.trimmingCharacters(in: .whitespacesAndNewlines)
            
            await selfDBManager.createComment(
                topicId: topicId,
                content: content.trimmingCharacters(in: .whitespacesAndNewlines),
                authorName: finalAuthorName,
                fileData: selectedMediaData,
                filename: selectedFileName
            )
            
            await MainActor.run {
                if selfDBManager.errorMessage.isEmpty {
                    // Create a temporary comment for immediate UI update
                    let tempComment = Comment(
                        id: UUID().uuidString,
                        topicId: topicId,
                        content: content.trimmingCharacters(in: .whitespacesAndNewlines),
                        authorName: finalAuthorName,
                        userId: selfDBManager.currentUser?.id,
                        fileId: nil,
                        createdAt: ISO8601DateFormatter().string(from: Date()),
                        updatedAt: ISO8601DateFormatter().string(from: Date())
                    )
                    onCommentAdded(tempComment)
                    isPresented = false
                } else {
                    errorMessage = selfDBManager.errorMessage
                }
                isLoading = false
            }
        }
    }
    
    private func updateComment() {
        guard isFormValid, let commentId = editingComment?.id, let originalComment = editingComment else { return }
        
        isLoading = true
        errorMessage = ""
        
        Task {
            await selfDBManager.updateComment(
                commentId: commentId,
                content: content.trimmed(),
                fileData: selectedMediaData,
                filename: selectedFileName,
                oldFileId: originalComment.fileId,
                removeFile: remoteFileRemoved && selectedMediaData == nil
            )
            
            await MainActor.run {
                if selfDBManager.errorMessage.isEmpty {
                    // Create updated comment for immediate UI update
                    let updatedComment = Comment(
                        id: originalComment.id,
                        topicId: originalComment.topicId,
                        content: content.trimmingCharacters(in: .whitespacesAndNewlines),
                        authorName: originalComment.authorName,
                        userId: originalComment.userId,
                        fileId: originalComment.fileId,
                        createdAt: originalComment.createdAt,
                        updatedAt: ISO8601DateFormatter().string(from: Date())
                    )
                    onCommentAdded(updatedComment)
                    isPresented = false
                } else {
                    errorMessage = selfDBManager.errorMessage
                }
                isLoading = false
            }
        }
    }
    
    private func deleteComment() {
        guard let commentId = editingComment?.id else { return }
        
        isLoading = true
        errorMessage = ""
        
        Task {
            await selfDBManager.deleteComment(commentId: commentId)
            
            await MainActor.run {
                if selfDBManager.errorMessage.isEmpty {
                    onCommentDeleted?() // Call the delete callback
                    isPresented = false
                } else {
                    errorMessage = selfDBManager.errorMessage
                }
                isLoading = false
            }
        }
    }
}


#Preview {
    AddCommentView(
        isPresented: .constant(true),
        topicId: "sample-topic-id",
        selfDBManager: SelfDBManager(),
        onCommentAdded: { _ in }
    )
}