//
//  MediaCarouselView.swift
//  Self-Social
//

import SwiftUI
import AVKit

struct MediaCarouselView: View {
    let files: [PostFileWithData]
    @State private var currentIndex = 0
    
    var body: some View {
        if files.count == 1 {
            MediaItemView(file: files[0])
        } else {
            TabView(selection: $currentIndex) {
                ForEach(Array(files.enumerated()), id: \.element.id) { index, file in
                    MediaItemView(file: file)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .automatic))
            .frame(height: 400)
        }
    }
}

struct MediaItemView: View {
    let file: PostFileWithData
    @State private var isPlayingVideo = false
    @State private var videoData: Data?
    @State private var isLoadingVideo = false
    
    var body: some View {
        GeometryReader { geometry in
            Group {
                if file.postFile.isImage {
                    if let imageData = file.imageData, let uiImage = UIImage(data: imageData) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .clipped()
                    } else {
                        placeholderView
                    }
                } else if file.postFile.isVideo {
                    ZStack {
                        if let thumbData = file.thumbnailData, let uiImage = UIImage(data: thumbData) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: geometry.size.width, height: geometry.size.height)
                                .clipped()
                        } else {
                            Color.black
                        }
                        
                        if isLoadingVideo {
                            ProgressView()
                                .scaleEffect(1.5)
                                .tint(.white)
                        } else {
                            Button {
                                loadAndPlayVideo()
                            } label: {
                                Image(systemName: "play.circle.fill")
                                    .font(.system(size: 60))
                                    .foregroundColor(.white)
                                    .shadow(radius: 10)
                            }
                        }
                    }
                    .contentShape(Rectangle())
                    .fullScreenCover(isPresented: $isPlayingVideo) {
                        VideoPlayerView(videoData: videoData, isPresented: $isPlayingVideo)
                    }
                }
            }
        }
        .frame(height: 400)
        .clipped()
    }
    
    private var placeholderView: some View {
        Rectangle()
            .fill(Color(.systemGray5))
            .overlay(
                Image(systemName: "photo")
                    .font(.largeTitle)
                    .foregroundColor(.secondary)
            )
    }
    
    private func loadAndPlayVideo() {
        guard videoData == nil else {
            isPlayingVideo = true
            return
        }
        
        isLoadingVideo = true
        
        Task {
            do {
                let data = try await SelfDBManager.shared.downloadFile(url: file.postFile.fileUrl)
                await MainActor.run {
                    videoData = data
                    isLoadingVideo = false
                    isPlayingVideo = true
                }
            } catch {
                print("Failed to load video: \(error)")
                await MainActor.run {
                    isLoadingVideo = false
                }
            }
        }
    }
}

struct VideoPlayerView: View {
    let videoData: Data?
    @Binding var isPresented: Bool
    @State private var player: AVPlayer?
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            if let player = player {
                VideoPlayer(player: player)
                    .ignoresSafeArea()
            }
            
            VStack {
                HStack {
                    Spacer()
                    Button {
                        isPresented = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title)
                            .foregroundColor(.white)
                            .padding()
                    }
                }
                Spacer()
            }
        }
        .onAppear {
            setupPlayer()
        }
        .onDisappear {
            player?.pause()
            player = nil
        }
    }
    
    private func setupPlayer() {
        guard let videoData = videoData else { return }
        
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp4")
        
        do {
            try videoData.write(to: tempURL)
            player = AVPlayer(url: tempURL)
            player?.play()
        } catch {
            print("Failed to write video: \(error)")
        }
    }
}

#Preview {
    MediaCarouselView(files: [])
}
