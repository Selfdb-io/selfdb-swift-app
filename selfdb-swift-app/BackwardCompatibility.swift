//
//  BackwardCompatibility.swift
//  selfd-swift
//
//  Created by rodgers magabo on 04/06/2025.
//

import SwiftUI
import PhotosUI

// MARK: - Backward Compatibility Modifiers

struct PhotoPickerChangeModifier: ViewModifier {
    let selectedPhotoItem: PhotosPickerItem?
    let onChange: (PhotosPickerItem?) -> Void
    
    func body(content: Content) -> some View {
        if #available(iOS 17.0, *) {
            content.onChange(of: selectedPhotoItem) { _, newValue in
                onChange(newValue)
            }
        } else {
            content.onChange(of: selectedPhotoItem) { newValue in
                onChange(newValue)
            }
        }
    }
}