//
//  MediaItem.swift
//  Self-Social
//

import Foundation
import UIKit

enum MediaType: String {
    case image
    case video
}

struct MediaItem: Identifiable {
    let id = UUID()
    let type: MediaType
    let data: Data
    let thumbnailData: Data?
    let previewImage: UIImage?

    var fileExtension: String {
        type == .image ? "jpg" : "mp4"
    }
}
