//
//  ImagePickerView.swift
//  Protector
//
//  Created by Ben Sage on 6/24/24.
//

import SwiftUI
import PhotosUI

struct ImagePickerView: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    let dismiss: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = 1
        config.preferredAssetRepresentationMode = .current

        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) { }
    
    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        var parent: ImagePickerView
        
        init(_ parent: ImagePickerView) {
            self.parent = parent
        }
        
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            guard let provider = results.first?.itemProvider else {
                parent.dismiss()
                return
            }
            
            guard provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) else {
                print("Selected file is not an image.")
                parent.dismiss()
                return
            }
            
            provider.loadFileRepresentation(forTypeIdentifier: UTType.image.identifier) { url, error in
                if let error = error {
                    print("Failed to load file representation: \(error)")
                    DispatchQueue.main.async {
                        print("Failed to load image: \(error.localizedDescription)")
                        self.parent.dismiss()
                    }
                    return
                }
                
                guard let sourceURL = url else {
                    DispatchQueue.main.async {
                        print("Failed to get URL for image.")
                        self.parent.dismiss()
                    }
                    return
                }
                
                let uniqueFilename = UUID().uuidString + "." + sourceURL.pathExtension
                let temporaryFileURL = FileManager.default.temporaryDirectory.appendingPathComponent(uniqueFilename)

                do {
                    try FileManager.default.copyItem(at: sourceURL, to: temporaryFileURL)
                } catch {
                    print("Failed to copy file: \(error)")
                    DispatchQueue.main.async {
                        print("Failed to load image: \(error.localizedDescription)")
                        self.parent.dismiss()
                    }
                    return
                }


                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        let data = try Data(contentsOf: temporaryFileURL)
                        if let image = UIImage(data: data) {
                            DispatchQueue.main.async {
                                self.parent.image = image
                            }
                        } else {
                            DispatchQueue.main.async {
                                print("Failed to convert data to image.")
                                self.parent.dismiss()
                            }
                        }
                    } catch {
                        DispatchQueue.main.async {
                            print("Failed to load image: \(error.localizedDescription)")
                            self.parent.dismiss()
                        }
                    }
                }
            }
        }
    }
}
