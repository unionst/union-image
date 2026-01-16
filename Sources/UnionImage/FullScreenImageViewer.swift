import SwiftUI
import UIKit

// MARK: - ImageViewerController

@MainActor
public final class ImageViewerController {
    public static let shared = ImageViewerController()

    private var overlayWindow: PassThroughWindow?
    private var hostingController: UIHostingController<ImageViewerOverlay>?

    private init() {}

    public func show(image: UIImage, sourceFrame: CGRect) {
        guard let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first else { return }

        let viewModel = ImageViewerViewModel(image: image, sourceFrame: sourceFrame)

        let overlay = ImageViewerOverlay(viewModel: viewModel) { @MainActor [weak self] in
            self?.dismiss()
        }

        let hosting = UIHostingController(rootView: overlay)
        hosting.view.backgroundColor = .clear

        let window = PassThroughWindow(windowScene: windowScene)
        window.windowLevel = .alert + 100
        window.rootViewController = hosting
        window.isHidden = false
        window.isUserInteractionEnabled = true

        self.overlayWindow = window
        self.hostingController = hosting

        Task { @MainActor in
            viewModel.expand()
        }
    }

    private func dismiss() {
        overlayWindow?.isHidden = true
        overlayWindow = nil
        hostingController = nil
    }
}

// MARK: - PassThroughWindow

private class PassThroughWindow: UIWindow {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard let hitView = super.hitTest(point, with: event),
              let rootView = rootViewController?.view else {
            return nil
        }

        if hitView !== rootView {
            return hitView
        }

        for subview in rootView.subviews.reversed() {
            let pointInSubview = subview.convert(point, from: rootView)
            if subview.hitTest(pointInSubview, with: event) != nil {
                return hitView
            }
        }
        return nil
    }
}

// MARK: - ViewModel

@Observable
private final class ImageViewerViewModel {
    let image: UIImage
    let sourceFrame: CGRect

    var currentFrame: CGRect
    var backgroundOpacity: Double = 0
    var showControls = false
    var dragOffset: CGFloat = 0

    var isExpanded = false

    var dragProgress: CGFloat {
        min(max(dragOffset, 0) / 300, 1)
    }

    var screenBounds: CGRect {
        UIScreen.main.bounds
    }

    var expandedFrame: CGRect {
        let imageSize = image.size
        let screenSize = screenBounds.size

        let widthRatio = screenSize.width / imageSize.width
        let heightRatio = screenSize.height / imageSize.height
        let scale = min(widthRatio, heightRatio)

        let scaledWidth = imageSize.width * scale
        let scaledHeight = imageSize.height * scale

        return CGRect(
            x: (screenSize.width - scaledWidth) / 2,
            y: (screenSize.height - scaledHeight) / 2,
            width: scaledWidth,
            height: scaledHeight
        )
    }

    init(image: UIImage, sourceFrame: CGRect) {
        self.image = image
        self.sourceFrame = sourceFrame
        self.currentFrame = sourceFrame
    }

    func expand() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            currentFrame = expandedFrame
            backgroundOpacity = 1
            isExpanded = true
        }
    }

    func collapse(completion: @escaping @MainActor () -> Void) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            currentFrame = sourceFrame
            backgroundOpacity = 0
            dragOffset = 0
            showControls = false
            isExpanded = false
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.3))
            completion()
        }
    }
}

// MARK: - Overlay View

private struct ImageViewerOverlay: View {
    @Bindable var viewModel: ImageViewerViewModel
    let onDismiss: @MainActor () -> Void

    var body: some View {
        ZStack {
            Color.black
                .opacity(viewModel.backgroundOpacity * (1 - viewModel.dragProgress))
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        viewModel.showControls.toggle()
                    }
                }

            Image(uiImage: viewModel.image)
                .resizable()
                .frame(width: viewModel.currentFrame.width, height: viewModel.currentFrame.height)
                .scaleEffect(1 - viewModel.dragProgress * 0.1)
                .position(
                    x: viewModel.currentFrame.midX,
                    y: viewModel.currentFrame.midY + (viewModel.dragOffset > 0 ? viewModel.dragOffset : 0)
                )
                .gesture(dismissGesture)
        }
        .overlay(alignment: .topTrailing) {
            if viewModel.showControls {
                Button(role: .close) {
                    viewModel.collapse(completion: onDismiss)
                }
                .padding(.trailing, 16)
                .padding(.top, 56)
                .transition(.opacity)
            }
        }
        .ignoresSafeArea()
        .statusBarHidden(!viewModel.showControls)
        .preferredColorScheme(.dark)
    }

    private var dismissGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                viewModel.dragOffset = value.translation.height
            }
            .onEnded { value in
                let translation = value.translation.height
                let velocity = value.predictedEndTranslation.height - translation
                let shouldDismiss = translation > 100 || velocity > 300

                if shouldDismiss {
                    viewModel.collapse(completion: onDismiss)
                } else {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        viewModel.dragOffset = 0
                    }
                }
            }
    }
}

// MARK: - ZoomableImage

public struct ZoomableImage: View {
    private let uiImage: UIImage

    public init(uiImage: UIImage) {
        self.uiImage = uiImage
    }

    public var body: some View {
        GeometryReader { geo in
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .onTapGesture {
                    let frame = geo.frame(in: .global)
                    ImageViewerController.shared.show(image: uiImage, sourceFrame: frame)
                }
        }
        .aspectRatio(uiImage.size, contentMode: .fit)
    }
}
