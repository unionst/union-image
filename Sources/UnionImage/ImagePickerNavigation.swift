//
//  ImagePickerNavigation.swift
//  Protector
//
//  Created by Ben Sage on 6/24/24.
//

import SwiftUI

struct ImagePickerNavigation: View {
    @Binding var image: UIImage?
    @Environment(\.dismiss) var dismiss
    
    var presentCrop: Binding<Bool> {
        Binding {
            image != nil
        } `set`: { newValue in
            if !newValue {
                image = nil
            }
        }
    }
    
    var body: some View {
        NavigationStack {
            ImagePickerView(image: $image) {
                dismiss()
            }
            .navigationDestination(isPresented: presentCrop) {
                CropImageView(image: $image) {
                    dismiss()
                }
                .ignoresSafeArea()
            }
            .ignoresSafeArea()
        }
        .ignoresSafeArea()
    }
}

#Preview {
    ImagePickerNavigation(image: .constant(nil))
}
