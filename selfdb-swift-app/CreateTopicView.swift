//
//  CreateTopicView.swift
//  selfd-swift
//
//  Created by rodgers magabo on 04/06/2025.
//

import SwiftUI
import PhotosUI
import AVFoundation

struct CreateTopicView: View {
    @Binding var isPresented: Bool
    @ObservedObject var selfDBManager: SelfDBManager
    let onTopicAdded: (Topic) -> Void
    
    // Edit mode properties
    var editingTopic: Topic? = nil
    var isEditMode: Bool { editingTopic != nil }
    
    @State private var title = ""
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
    @State private var remoteFileId: String? = nil        // 🔹 keep only the id
    @State private var remoteFileRemoved = false
    @State private var fileViewerKey = UUID()              // 🔹 NEW: force refresh
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Form fields
                VStack(spacing: 16) {
                    TextField("Topic title", text: $title)
                        .textFieldStyle(CustomTextFieldStyle())
                    
                    // Show name field only when user is not logged in
                    if !selfDBManager.isAuthenticated {
                        TextField("Your name", text: $authorName)
                            .textFieldStyle(CustomTextFieldStyle())
                    }
                    
                    TextField("What would you like to discuss?", text: $content, axis: .vertical)
                        .textFieldStyle(CustomTextFieldStyle())
                        .lineLimit(4...8)
                }
                .padding(.horizontal)
                
                // Media upload section
                VStack(spacing: 12) {
                    if remoteFileId != nil && selectedMediaData == nil && !remoteFileRemoved {
                        // 🔸 show remote file preview
                        VStack {
                            if let fid = remoteFileId {
                                FileViewer(fileId: fid, selfDBManager: selfDBManager)
                                    .id(fileViewerKey)     // 🔹 force recreation when key changes
                                    .frame(maxHeight: 200)
                                    .cornerRadius(12)
                                
                                Button("Remove File") {
                                    Task {
                                        _ = await selfDBManager.deleteRemoteFile(fid)
                                        remoteFileRemoved = true
                                        remoteFileId = nil
                                        FileURLCache.shared.invalidate(fileId: fid)
                                        fileViewerKey = UUID()     // 🔹 force FileViewer refresh
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
                            
                            Text(selectedFileName ?? "Media")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
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
                        updateTopic()
                    } else {
                        postTopic()
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
            .navigationTitle(isEditMode ? "Edit Topic" : "Create New Topic")
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
                            deleteTopic()
                        } label: {
                            Image(systemName: "trash")
                                .foregroundColor(.red)
                        }
                    }
                }
            }
        }
        .onAppear {
            // Pre-fill fields when editing
            if let topic = editingTopic {
                title       = topic.title
                content     = topic.content
                authorName  = topic.authorName
                remoteFileId = topic.fileId

                // If you really need the download URL later, fetch it asynchronously
                if let fid = topic.fileId {
                    Task { _ = await selfDBManager.getFileDownloadURL(fileId: fid) }
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
                    selectedFileName = "captured_image_\(UUID().uuidString).jpg"
                    selectedMediaType = "image/jpeg"
                }
                showingCamera = false
            }
        }
    }
    
    private var isFormValid: Bool {
        let titleValid = !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let contentValid = !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let nameValid = selfDBManager.isAuthenticated || !authorName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        
        return titleValid && contentValid && nameValid
    }
    
    private func loadPhotoData(from item: PhotosPickerItem) async {
        do {
            if let data = try await item.loadTransferable(type: Data.self) {
                await MainActor.run {
                    selectedMediaData = data
                    
                    // Determine the media type
                    if item.supportedContentTypes.contains(where: { $0.conforms(to: .image) }) {
                        selectedMediaType = "image/jpeg"
                        selectedFileName = "selected_image_\(UUID().uuidString).jpg"
                    } else if item.supportedContentTypes.contains(where: { $0.conforms(to: .movie) }) {
                        selectedMediaType = "video/mp4"
                        selectedFileName = "selected_video_\(UUID().uuidString).mp4"
                    } else {
                        selectedMediaType = "application/octet-stream"
                        selectedFileName = "selected_media_\(UUID().uuidString)"
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
    
    private func postTopic() {
        guard isFormValid else { return }
        
        isLoading = true
        errorMessage = ""
        
        Task {
            let finalAuthorName = selfDBManager.isAuthenticated ? 
                (selfDBManager.currentUser?.email ?? "Anonymous") : 
                authorName.trimmingCharacters(in: .whitespacesAndNewlines)
            
            await selfDBManager.createTopic(
                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                content: content.trimmingCharacters(in: .whitespacesAndNewlines),
                authorName: finalAuthorName,
                fileData: selectedMediaData,
                filename: selectedFileName
            )
            
            await MainActor.run {
                if selfDBManager.errorMessage.isEmpty {
                    // Create a temporary topic for immediate UI update
                    let tempTopic = Topic(
                        id: UUID().uuidString,
                        title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                        content: content.trimmingCharacters(in: .whitespacesAndNewlines),
                        authorName: finalAuthorName,
                        userId: selfDBManager.currentUser?.id,
                        fileId: nil,
                        createdAt: ISO8601DateFormatter().string(from: Date()),
                        updatedAt: ISO8601DateFormatter().string(from: Date())
                    )
                    onTopicAdded(tempTopic)
                    isPresented = false
                } else {
                    errorMessage = selfDBManager.errorMessage
                }
                isLoading = false
            }
        }
    }
    
    private func updateTopic() {
        guard isFormValid, let topicId = editingTopic?.id, let originalTopic = editingTopic else { return }
        
        isLoading = true
        errorMessage = ""
        
        Task {
            await selfDBManager.updateTopic(
                 topicId: topicId,
                 title: title.trimmed(),
                 content: content.trimmed(),
                 fileData: selectedMediaData,
                 filename: selectedFileName,
                oldFileId: originalTopic.fileId,
                removeFile: remoteFileRemoved && selectedMediaData == nil
            )
            
            await MainActor.run {
                if selfDBManager.errorMessage.isEmpty {
                    // Create updated topic for immediate UI update
                    let updatedTopic = Topic(
                        id: originalTopic.id,
                        title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                        content: content.trimmingCharacters(in: .whitespacesAndNewlines),
                        authorName: originalTopic.authorName,
                        userId: originalTopic.userId,
                        fileId: originalTopic.fileId,
                        createdAt: originalTopic.createdAt,
                        updatedAt: ISO8601DateFormatter().string(from: Date())
                    )
                    onTopicAdded(updatedTopic)
                    isPresented = false
                } else {
                    errorMessage = selfDBManager.errorMessage
                }
                isLoading = false
            }
        }
    }
    
    private func deleteTopic() {
        guard let topicId = editingTopic?.id else { return }
        
        isLoading = true
        errorMessage = ""
        
        Task {
            await selfDBManager.deleteTopic(topicId: topicId)
            
            await MainActor.run {
                if selfDBManager.errorMessage.isEmpty {
                    isPresented = false
                } else {
                    errorMessage = selfDBManager.errorMessage
                }
                isLoading = false
            }
        }
    }
}

struct CameraView: UIViewControllerRepresentable {
    let onImageCaptured: (UIImage) -> Void
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraView
        
        init(_ parent: CameraView) {
            self.parent = parent
        }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.onImageCaptured(image)
            }
            picker.dismiss(animated: true)
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }
    }
}


#Preview {
    CreateTopicView(
        isPresented: .constant(true),
        selfDBManager: SelfDBManager(),
        onTopicAdded: { _ in }
    )
}
