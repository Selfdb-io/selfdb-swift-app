//
//  FileViewer.swift
//  selfd-swift
//
//  Created by rodgers magabo on 04/06/2025.
//

import AVKit
import SwiftUI

// MARK: - Video Playback Manager
final class VideoPlaybackManager {
    static let shared = VideoPlaybackManager()
    private var currentPlayer: AVPlayer?
    
    private init() {}
    
    func play(player: AVPlayer) {
        if currentPlayer !== player {
            currentPlayer?.pause()
        }
        currentPlayer = player
        currentPlayer?.play()
    }
    
    func pause(player: AVPlayer) {
        guard currentPlayer === player else { return }
        player.pause()
    }
}

// MARK: - URL Cache Manager
final class FileURLCache {
    static let shared = FileURLCache()
    private var cache: [String: CachedURL] = [:]
    private let cacheQueue = DispatchQueue(label: "com.selfdb.fileurlcache", attributes: .concurrent)
    private let expirationTime: TimeInterval = 3600 // 1 hour
    
    private struct CachedURL {
        let url: String
        let expirationDate: Date
        
        var isExpired: Bool {
            Date() > expirationDate
        }
    }
    
    private init() {}
    
    func getURL(for fileId: String) -> String? {
        cacheQueue.sync {
            guard let cached = cache[fileId], !cached.isExpired else {
                return nil
            }
            return cached.url
        }
    }
    
    func setURL(_ url: String, for fileId: String) {
        cacheQueue.async(flags: .barrier) {
            self.cache[fileId] = CachedURL(
                url: url,
                expirationDate: Date().addingTimeInterval(self.expirationTime)
            )
        }
    }
    
    func invalidate(fileId: String) {
        cacheQueue.async(flags: .barrier) {
            self.cache.removeValue(forKey: fileId)
        }
    }
    
    /// Clear cache and return immediately (for UI responsiveness)
    func invalidateImmediately(fileId: String) {
        // Use async to avoid blocking, but ensure it happens quickly
        cacheQueue.async(flags: .barrier) {
            self.cache.removeValue(forKey: fileId)
        }
    }
    
    func invalidateAll() {
        cacheQueue.async(flags: .barrier) {
            self.cache.removeAll()
        }
    }
}

// MARK: - FileViewer
struct FileViewer: View {
    let fileId: String
    @ObservedObject var selfDBManager: SelfDBManager
    
    @State private var fileUrl: String?
    @State private var isLoading = true
    @State private var loadTask: Task<Void, Never>?
    @State private var player: AVPlayer?
    @State private var isImageFullscreen = false
    @State private var isVideoFullscreen = false
    
    // Constants
    private let cardHeight: CGFloat = 200
    private let cornerRadius: CGFloat = 8
    
    var body: some View {
        CardContainer(
            height: cardHeight,
            cornerRadius: cornerRadius
        ) {
            contentView
        }
        .onAppear {
            loadTask = Task { await loadFileUrl() }
        }
        .onDisappear {
            loadTask?.cancel()
            player?.pause()
        }
        .fullScreenCover(isPresented: $isImageFullscreen) {
            FullscreenImageView(url: fileUrl, isPresented: $isImageFullscreen)
        }
        .fullScreenCover(isPresented: $isVideoFullscreen) {
            FullscreenVideoView(player: player, isPresented: $isVideoFullscreen)
        }
    }
    
    // MARK: - Content View
    @ViewBuilder
    private var contentView: some View {
        if isLoading {
            LoadingView()
        } else if let fileUrl = fileUrl {
            FileContentView(
                url: fileUrl,
                player: $player,
                onImageTap: { isImageFullscreen = true },
                onVideoTap: { isVideoFullscreen = true }
            )
        } else {
            EmptyFileView()
        }
    }
    
    // MARK: - Load File URL
    private func loadFileUrl() async {
        guard !fileId.isEmpty, fileId != "nil" else {
            print("🎬 FileViewer: Invalid fileId: '\(fileId)'")
            await MainActor.run { isLoading = false }
            return
        }
        
        // Check cache first
        if let cachedUrl = FileURLCache.shared.getURL(for: fileId) {
            print("🎬 FileViewer: Using cached URL for fileId: \(fileId)")
            await MainActor.run {
                self.fileUrl = cachedUrl
                self.isLoading = false
            }
            return
        }
        
        if fileUrl != nil {
            print("🎬 FileViewer: URL already loaded for fileId: \(fileId)")
            return
        }
        
        guard !Task.isCancelled else { return }
        
        let url = await selfDBManager.getFileDownloadURL(fileId: fileId)
        
        guard !Task.isCancelled else { return }
        
        // Cache the URL if successfully fetched
        if let url = url {
            FileURLCache.shared.setURL(url, for: fileId)
        }
        
        await MainActor.run {
            self.fileUrl = url
            self.isLoading = false
        }
    }
}

// MARK: - Card Container
struct CardContainer<Content: View>: View {
    let height: CGFloat
    let cornerRadius: CGFloat
    @ViewBuilder let content: Content
    
    var body: some View {
        ZStack {
            Color(UIColor.systemGray6).opacity(0.5)
            content
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .cornerRadius(cornerRadius)
        .clipped()
    }
}

// MARK: - Loading View
struct LoadingView: View {
    var body: some View {
        ProgressView()
            .progressViewStyle(CircularProgressViewStyle(tint: .gray))
            .scaleEffect(0.8)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Empty File View
struct EmptyFileView: View {
    var body: some View {
        Text("File not available")
            .foregroundColor(.secondary)
            .font(.caption)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - File Content View
struct FileContentView: View {
    let url: String
    @Binding var player: AVPlayer?
    let onImageTap: () -> Void
    let onVideoTap: () -> Void
    
    var body: some View {
        if isImageFile(url: url) {
            ImageThumbnailView(url: url, onTap: onImageTap)
        } else if isVideoFile(url: url) {
            VideoThumbnailView(
                url: url,
                player: $player,
                onTap: onVideoTap
            )
        } else {
            FileDownloadView(url: url, filename: "Download File")
                .padding(.horizontal, 16)
        }
    }
    
    private func isImageFile(url: String) -> Bool {
        let imageExtensions = ["jpg", "jpeg", "png", "gif", "webp"]
        return imageExtensions.contains { url.lowercased().contains($0) }
    }
    
    private func isVideoFile(url: String) -> Bool {
        let videoExtensions = ["mp4", "mov", "avi", "mkv"]
        return videoExtensions.contains { url.lowercased().contains($0) }
    }
}

// MARK: - Image Thumbnail View
struct ImageThumbnailView: View {
    let url: String
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            GeometryReader { geometry in
                AsyncImage(url: URL(string: url)) { phase in
                    switch phase {
                    case .empty:
                        LoadingView()
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .clipped()
                    case .failure:
                        Image(systemName: "photo")
                            .foregroundColor(.gray)
                            .font(.largeTitle)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    @unknown default:
                        EmptyView()
                    }
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Video Thumbnail View
struct VideoThumbnailView: View {
    let url: String
    @Binding var player: AVPlayer?
    let onTap: () -> Void
    
    var body: some View {
        ZStack {
            Color.black
            
            if let player = player {
                VideoPlayer(player: player)
                    .disabled(true)
            } else {
                LoadingView()
                    .onAppear {
                        if let videoURL = URL(string: url) {
                            player = AVPlayer(url: videoURL)
                        }
                    }
            }
            
            // Play button overlay
            Image(systemName: "play.circle.fill")
                .font(.system(size: 50))
                .foregroundColor(.white)
                .shadow(radius: 3)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }
}

// MARK: - File Download View
struct FileDownloadView: View {
    let url: String
    let filename: String
    
    var body: some View {
        Button(action: {
            if let downloadUrl = URL(string: url) {
                #if os(iOS)
                UIApplication.shared.open(downloadUrl)
                #endif
            }
        }) {
            HStack(spacing: 12) {
                Image(systemName: "doc.fill")
                    .foregroundColor(.blue)
                    .font(.title3)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(filename)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                    Text("Tap to download")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Image(systemName: "arrow.down.circle")
                    .foregroundColor(.blue)
                    .font(.title3)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.blue.opacity(0.1))
            .cornerRadius(8)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Fullscreen Image View
struct FullscreenImageView: View {
    let url: String?
    @Binding var isPresented: Bool
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            if let url = url, let imageURL = URL(string: url) {
                AsyncImage(url: imageURL) { image in
                    image
                        .resizable()
                        .scaledToFit()
                } placeholder: {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                }
            }
            
            // Close button
            VStack {
                HStack {
                    Spacer()
                    Button(action: { isPresented = false }) {
                        Image(systemName: "xmark")
                            .font(.title2.bold())
                            .foregroundColor(.white)
                            .padding(12)
                            .background(Color.black.opacity(0.6))
                            .clipShape(Circle())
                    }
                }
                .padding(.top, 50)
                .padding(.horizontal, 20)
                Spacer()
            }
        }
    }
}

// MARK: - Fullscreen Video View
struct FullscreenVideoView: View {
    let player: AVPlayer?
    @Binding var isPresented: Bool
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            if let player = player {
                VideoPlayer(player: player)
                    .ignoresSafeArea()
                    .onAppear {
                        VideoPlaybackManager.shared.play(player: player)
                    }
                    .onDisappear {
                        VideoPlaybackManager.shared.pause(player: player)
                    }
            }
            
            // Close button
            VStack {
                HStack {
                    Spacer()
                    Button(action: { isPresented = false }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title)
                            .foregroundColor(.white)
                            .background(Color.black.opacity(0.5))
                            .clipShape(Circle())
                    }
                    .padding()
                }
                Spacer()
            }
        }
    }
}

// MARK: - Preview
#Preview {
    FileViewer(fileId: "sample-file-id", selfDBManager: SelfDBManager())
}
