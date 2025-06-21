//
//  CropImageView.swift
//  Protector
//
//  Created by Ben Sage on 6/24/24.
//

import SwiftUI
import CropViewController

struct CropImageView: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    var dismiss: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIViewController(context: Context) -> CropViewController {
        guard let image = image else {
            let emptyViewController = UIViewController()
            emptyViewController.view.backgroundColor = .red
            return CropViewController(image: UIImage())
        }
        
        let cropController = CropViewController(
            croppingStyle: CropViewCroppingStyle.circular, image: image)
        cropController.customAspectRatio = CGSize(width: 1, height: 1)
        cropController.aspectRatioLockEnabled = true
        cropController.aspectRatioPickerButtonHidden = true
        cropController.cancelButtonColor = .white
        cropController.resetButtonHidden = true
        cropController.delegate = context.coordinator
        return cropController
    }

    func updateUIViewController(_ uiViewController: CropViewController, context: Context) {

    }

    class Coordinator: NSObject, CropViewControllerDelegate {
        var parent: CropImageView

        init(_ parent: CropImageView) {
            self.parent = parent
        }
        
        public func cropViewController(
            _ cropViewController: CropViewController, didCropToImage image: UIImage,
            withRect cropRect: CGRect, angle: Int
        ) {
            parent.image = image
            parent.dismiss()
        }
        
        public func cropViewController(
            _ cropViewController: CropViewController, didFinishCancelled cancelled: Bool
        ) {
            if cancelled {
                parent.image = nil
            }
        }
    }
}
