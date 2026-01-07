//
//  CreatePostView.swift
//  Self-Social
//

import SwiftUI
import PhotosUI
import AVFoundation
import UniformTypeIdentifiers

// Unified wrapper for reorderable media items
enum EditableMedia: Identifiable, Equatable {
    case existing(PostFileWithData)
    case new(MediaItem)
    
    var id: String {
        switch self {
        case .existing(let file): return "existing-\(file.id)"
        case .new(let item): return "new-\(item.id.uuidString)"
        }
    }
    
    static func == (lhs: EditableMedia, rhs: EditableMedia) -> Bool {
        lhs.id == rhs.id
    }
}

struct CreatePostView: View {
    @EnvironmentObject var db: SelfDBManager
    @Environment(\.dismiss) private var dismiss
    
    // Edit mode - pass existing post to edit
    var existingPost: PostWithDetails?
    
    var isEditMode: Bool { existingPost != nil }
    
    @State private var description = ""
    @State private var mediaItems: [EditableMedia] = []  // Unified ordered list
    @State private var filesToDelete: [PostFileWithData] = []  // Files marked for deletion
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var isLoading = false
    @State private var isProcessingMedia = false
    @State private var error: String?
    @State private var uploadProgress = ""
    @State private var draggingItem: EditableMedia?
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Error
                    if let error = error {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.white)
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color.red.opacity(0.8))
                            .cornerRadius(10)
                    }
                    
                    // Progress
                    if !uploadProgress.isEmpty {
                        Text(uploadProgress)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    // Media Picker
                    PhotosPicker(
                        selection: $selectedPhotos,
                        maxSelectionCount: 10,
                        matching: .any(of: [.images, .videos])
                    ) {
                        VStack(spacing: 12) {
                            if mediaItems.isEmpty {
                                Image(systemName: "photo.on.rectangle.angled")
                                    .font(.system(size: 50))
                                    .foregroundColor(.secondary)
                                
                                Text("Add Photos or Videos")
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                
                                Text("Tap to select media from your library")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            } else {
                                Image(systemName: "plus.circle.fill")
                                    .font(.title)
                                    .foregroundColor(.blue)
                                Text("Add More")
                                    .foregroundColor(.blue)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: mediaItems.isEmpty ? 200 : 80)
                        .background(Color(.systemGray6))
                        .cornerRadius(16)
                    }
                    .onChange(of: selectedPhotos) { _, newItems in
                        Task { await processSelectedPhotos(newItems) }
                    }
                    
                    // Processing indicator
                    if isProcessingMedia {
                        HStack {
                            ProgressView()
                            Text("Processing media...")
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    // Media Previews with reordering
                    if !mediaItems.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Drag to reorder")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 12) {
                                    ForEach(mediaItems) { item in
                                        ReorderableMediaPreview(
                                            item: item,
                                            isBeingDragged: draggingItem?.id == item.id,
                                            onRemove: {
                                                removeMedia(item)
                                            }
                                        )
                                        .onDrag {
                                            draggingItem = item
                                            return NSItemProvider(object: item.id as NSString)
                                        }
                                        .onDrop(of: [UTType.text], delegate: MediaDropDelegate(
                                            item: item,
                                            items: $mediaItems,
                                            draggingItem: $draggingItem
                                        ))
                                    }
                                }
                                .padding(.horizontal)
                            }
                        }
                    }
                    
                    // Description
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Caption")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        TextEditor(text: $description)
                            .frame(minHeight: 100)
                            .padding(8)
                            .background(Color(.systemGray6))
                            .cornerRadius(12)
                    }
                }
                .padding()
            }
            .navigationTitle(isEditMode ? "Edit Post" : "New Post")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(isLoading)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        Task {
                            if isEditMode {
                                await updatePost()
                            } else {
                                await createPost()
                            }
                        }
                    } label: {
                        if isLoading {
                            ProgressView()
                        } else {
                            Text(isEditMode ? "Save" : "Share")
                                .fontWeight(.semibold)
                        }
                    }
                    .disabled(isLoading || (description.isEmpty && mediaItems.isEmpty))
                }
            }
            .onAppear {
                // Populate fields if editing
                if let post = existingPost {
                    description = post.description ?? ""
                    // Convert existing files to EditableMedia
                    mediaItems = post.files.map { .existing($0) }
                }
            }
        }
    }
    
    private func removeMedia(_ item: EditableMedia) {
        if case .existing(let file) = item {
            filesToDelete.append(file)
        }
        mediaItems.removeAll { $0.id == item.id }
    }
    
    private func processSelectedPhotos(_ items: [PhotosPickerItem]) async {
        isProcessingMedia = true
        
        for item in items {
            do {
                if let movie = try await item.loadTransferable(type: VideoTransferable.self) {
                    // Video
                    let videoData = try Data(contentsOf: movie.url)
                    let thumbnailData = await generateThumbnail(from: movie.url)
                    let thumbnail = thumbnailData.flatMap { UIImage(data: $0) }
                    
                    await MainActor.run {
                        mediaItems.append(.new(MediaItem(
                            type: .video,
                            data: videoData,
                            thumbnailData: thumbnailData,
                            previewImage: thumbnail
                        )))
                    }
                } else if let imageData = try await item.loadTransferable(type: Data.self) {
                    // Image
                    let image = UIImage(data: imageData)
                    
                    await MainActor.run {
                        mediaItems.append(.new(MediaItem(
                            type: .image,
                            data: imageData,
                            thumbnailData: nil,
                            previewImage: image
                        )))
                    }
                }
            } catch {
                print("Failed to load media: \(error)")
            }
        }
        
        selectedPhotos = []
        isProcessingMedia = false
    }
    
    private func generateThumbnail(from url: URL) async -> Data? {
        let asset = AVURLAsset(url: url)
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        
        do {
            let time = CMTime(seconds: 1, preferredTimescale: 60)
            let cgImage = try await imageGenerator.image(at: time).image
            let uiImage = UIImage(cgImage: cgImage)
            return uiImage.pngData()
        } catch {
            print("Failed to generate thumbnail: \(error)")
            return nil
        }
    }
    
    private func createPost() async {
        guard !description.isEmpty || !mediaItems.isEmpty else { return }
        
        isLoading = true
        error = nil
        uploadProgress = "Creating post..."
        
        do {
            // Extract new MediaItems in order
            let newItems = mediaItems.compactMap { item -> MediaItem? in
                if case .new(let mediaItem) = item { return mediaItem }
                return nil
            }
            
            try await db.createPost(
                description: description.isEmpty ? nil : description,
                mediaItems: newItems
            )
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
        
        isLoading = false
        uploadProgress = ""
    }
    
    private func updatePost() async {
        guard let post = existingPost else { return }
        guard !description.isEmpty || !mediaItems.isEmpty else { return }
        
        isLoading = true
        error = nil
        uploadProgress = "Updating post..."
        
        do {
            // Extract new MediaItems in order
            let newItems = mediaItems.compactMap { item -> MediaItem? in
                if case .new(let mediaItem) = item { return mediaItem }
                return nil
            }
            
            // Extract existing files that remain (in their new order)
            let remainingExistingFiles = mediaItems.compactMap { item -> PostFileWithData? in
                if case .existing(let file) = item { return file }
                return nil
            }
            
            try await db.updatePost(
                postId: post.id,
                description: description.isEmpty ? nil : description,
                newMediaItems: newItems,
                filesToDelete: filesToDelete,
                reorderedExistingFiles: remainingExistingFiles
            )
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
        
        isLoading = false
        uploadProgress = ""
    }
}

struct MediaPreviewView: View {
    let item: MediaItem
    var onRemove: () -> Void
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            if let image = item.previewImage {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 120, height: 120)
                    .clipped()
                    .cornerRadius(12)
            } else {
                Rectangle()
                    .fill(Color(.systemGray5))
                    .frame(width: 120, height: 120)
                    .cornerRadius(12)
                    .overlay(
                        Image(systemName: item.type == .video ? "video" : "photo")
                            .foregroundColor(.secondary)
                    )
            }
            
            if item.type == .video {
                Image(systemName: "play.circle.fill")
                    .font(.title)
                    .foregroundColor(.white)
                    .shadow(radius: 5)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            
            Button {
                onRemove()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundColor(.white)
                    .background(Circle().fill(Color.black.opacity(0.5)))
            }
            .padding(4)
        }
    }
}

// Unified reorderable preview that handles both existing and new media
struct ReorderableMediaPreview: View {
    let item: EditableMedia
    let isBeingDragged: Bool
    var onRemove: () -> Void
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Preview image
            Group {
                switch item {
                case .existing(let file):
                    if let imageData = file.imageData, let image = UIImage(data: imageData) {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else if let thumbData = file.thumbnailData, let image = UIImage(data: thumbData) {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        placeholderView(isVideo: file.postFile.isVideo)
                    }
                    
                case .new(let mediaItem):
                    if let image = mediaItem.previewImage {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        placeholderView(isVideo: mediaItem.type == .video)
                    }
                }
            }
            .frame(width: 120, height: 120)
            .clipped()
            .cornerRadius(12)
            
            // Video indicator
            if isVideo {
                Image(systemName: "play.circle.fill")
                    .font(.title)
                    .foregroundColor(.white)
                    .shadow(radius: 5)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            
            // Order indicator
            VStack {
                Spacer()
                HStack {
                    Image(systemName: "line.3.horizontal")
                        .font(.caption)
                        .foregroundColor(.white)
                        .padding(4)
                        .background(Circle().fill(Color.black.opacity(0.5)))
                    Spacer()
                }
            }
            .padding(4)
            
            // Remove button
            Button {
                onRemove()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundColor(.white)
                    .background(Circle().fill(Color.black.opacity(0.5)))
            }
            .padding(4)
        }
        .opacity(isBeingDragged ? 0.5 : 1.0)
        .scaleEffect(isBeingDragged ? 1.05 : 1.0)
        .animation(.easeInOut(duration: 0.2), value: isBeingDragged)
    }
    
    private var isVideo: Bool {
        switch item {
        case .existing(let file): return file.postFile.isVideo
        case .new(let mediaItem): return mediaItem.type == .video
        }
    }
    
    private func placeholderView(isVideo: Bool) -> some View {
        Rectangle()
            .fill(Color(.systemGray5))
            .overlay(
                Image(systemName: isVideo ? "video" : "photo")
                    .foregroundColor(.secondary)
            )
    }
}

// Drop delegate for reordering
struct MediaDropDelegate: DropDelegate {
    let item: EditableMedia
    @Binding var items: [EditableMedia]
    @Binding var draggingItem: EditableMedia?
    
    func performDrop(info: DropInfo) -> Bool {
        draggingItem = nil
        return true
    }
    
    func dropEntered(info: DropInfo) {
        guard let draggingItem = draggingItem,
              draggingItem.id != item.id,
              let fromIndex = items.firstIndex(where: { $0.id == draggingItem.id }),
              let toIndex = items.firstIndex(where: { $0.id == item.id }) else {
            return
        }
        
        withAnimation(.easeInOut(duration: 0.2)) {
            items.move(fromOffsets: IndexSet(integer: fromIndex), toOffset: toIndex > fromIndex ? toIndex + 1 : toIndex)
        }
    }
    
    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }
}

// Preview for existing files (from edit mode) - kept for backwards compatibility
struct ExistingMediaPreviewView: View {
    let file: PostFileWithData
    var onRemove: () -> Void
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            if let imageData = file.imageData, let image = UIImage(data: imageData) {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 120, height: 120)
                    .clipped()
                    .cornerRadius(12)
            } else if let thumbData = file.thumbnailData, let image = UIImage(data: thumbData) {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 120, height: 120)
                    .clipped()
                    .cornerRadius(12)
            } else {
                Rectangle()
                    .fill(Color(.systemGray5))
                    .frame(width: 120, height: 120)
                    .cornerRadius(12)
                    .overlay(
                        Image(systemName: file.postFile.isVideo ? "video" : "photo")
                            .foregroundColor(.secondary)
                    )
            }
            
            if file.postFile.isVideo {
                Image(systemName: "play.circle.fill")
                    .font(.title)
                    .foregroundColor(.white)
                    .shadow(radius: 5)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            
            Button {
                onRemove()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundColor(.white)
                    .background(Circle().fill(Color.black.opacity(0.5)))
            }
            .padding(4)
        }
    }
}

struct VideoTransferable: Transferable {
    let url: URL
    
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { video in
            SentTransferredFile(video.url)
        } importing: { received in
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp4")
            try FileManager.default.copyItem(at: received.file, to: tempURL)
            return VideoTransferable(url: tempURL)
        }
    }
}

#Preview {
    CreatePostView()
        .environmentObject(SelfDBManager.shared)
}
