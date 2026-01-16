import SwiftUI
import UIKit
import LinkPresentation

// MARK: - ImageViewerController

@MainActor @Observable
public final class ImageViewerController {
    public static let shared = ImageViewerController()

    private var overlayWindow: UIWindow?
    private var viewerViewController: ImageViewerViewController?

    public private(set) var activeImage: UIImage?

    private init() {}

    public func show(image: UIImage, sourceFrame: CGRect) {
        guard let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first else { return }

        activeImage = image

        let viewModel = ImageViewerViewModel(image: image, sourceFrame: sourceFrame)
        let viewerVC = ImageViewerViewController(viewModel: viewModel) { [weak self] in
            self?.dismiss()
        }

        let navController = UINavigationController(rootViewController: viewerVC)
        navController.view.backgroundColor = .clear

        let appearance = UINavigationBarAppearance()
        appearance.configureWithTransparentBackground()
        navController.navigationBar.standardAppearance = appearance
        navController.navigationBar.scrollEdgeAppearance = appearance
        navController.navigationBar.compactAppearance = appearance

        let window = UIWindow(windowScene: windowScene)
        window.windowLevel = .alert + 100
        window.backgroundColor = .clear
        window.overrideUserInterfaceStyle = .dark
        window.rootViewController = navController
        window.isHidden = false

        self.overlayWindow = window
        self.viewerViewController = viewerVC

        Task { @MainActor in
            viewModel.expand()
        }
    }

    private func dismiss() {
        withAnimation(.easeOut(duration: 0.1)) {
            activeImage = nil
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(150))
            overlayWindow?.isHidden = true
            overlayWindow = nil
            viewerViewController = nil
        }
    }
}

// MARK: - ImageViewerViewController

private class ImageViewerViewController: UIViewController {
    private let viewModel: ImageViewerViewModel
    private let onDismiss: @MainActor () -> Void
    private var hostingController: UIHostingController<ImageViewerOverlay>?

    override var prefersStatusBarHidden: Bool {
        !viewModel.showControls
    }

    override var preferredStatusBarUpdateAnimation: UIStatusBarAnimation {
        .fade
    }

    init(viewModel: ImageViewerViewModel, onDismiss: @escaping @MainActor () -> Void) {
        self.viewModel = viewModel
        self.onDismiss = onDismiss
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear

        let overlay = ImageViewerOverlay(viewModel: viewModel)
        let hosting = UIHostingController(rootView: overlay)
        hosting.view.backgroundColor = .clear

        addChild(hosting)
        view.addSubview(hosting.view)
        hosting.view.frame = view.bounds
        hosting.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        hosting.didMove(toParent: self)

        self.hostingController = hosting

        setupNavigationBar()
        setupToolbar()

        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        view.addGestureRecognizer(panGesture)

        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        view.addGestureRecognizer(tapGesture)
    }

    private func setupNavigationBar() {
        let closeButton = UIBarButtonItem(systemItem: .close, primaryAction: UIAction { [weak self] _ in
            guard let self else { return }
            viewModel.collapse(completion: onDismiss)
        })
        navigationItem.rightBarButtonItem = closeButton
        navigationController?.setNavigationBarHidden(!viewModel.showControls, animated: false)
    }

    private func setupToolbar() {
        let shareButton = UIBarButtonItem(systemItem: .action, primaryAction: UIAction { [weak self] _ in
            guard let self else { return }
            let itemSource = ImageActivityItemSource(image: viewModel.image)
            let activityVC = UIActivityViewController(activityItems: [itemSource], applicationActivities: nil)
            activityVC.popoverPresentationController?.barButtonItem = self.toolbarItems?.last
            present(activityVC, animated: true)
        })
        let spacer = UIBarButtonItem(systemItem: .flexibleSpace)
        toolbarItems = [spacer, shareButton]
        navigationController?.setToolbarHidden(!viewModel.showControls, animated: false)
        navigationController?.toolbar.backgroundColor = .clear
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        let translation = gesture.translation(in: view)

        switch gesture.state {
        case .changed:
            viewModel.dragOffset = translation.y
            viewModel.dragOffsetX = translation.x
        case .ended, .cancelled:
            let velocity = gesture.velocity(in: view).y
            let shouldDismiss = translation.y > 100 || velocity > 300

            if shouldDismiss {
                viewModel.collapse { [onDismiss] in
                    onDismiss()
                }
            } else {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    viewModel.dragOffset = 0
                    viewModel.dragOffsetX = 0
                }
            }
        default:
            break
        }
    }

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        viewModel.showControls.toggle()
        UIView.animate(withDuration: 0.2) {
            self.navigationController?.setNavigationBarHidden(!self.viewModel.showControls, animated: true)
            self.navigationController?.setToolbarHidden(!self.viewModel.showControls, animated: true)
            self.setNeedsStatusBarAppearanceUpdate()
        }
    }
}

// MARK: - ImageActivityItemSource

private final class ImageActivityItemSource: NSObject, UIActivityItemSource {
    private let image: UIImage

    init(image: UIImage) {
        self.image = image
        super.init()
    }

    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
        image
    }

    func activityViewController(_ activityViewController: UIActivityViewController, itemForActivityType activityType: UIActivity.ActivityType?) -> Any? {
        image
    }

    func activityViewControllerLinkMetadata(_ activityViewController: UIActivityViewController) -> LPLinkMetadata? {
        let metadata = LPLinkMetadata()
        metadata.title = "Image"
        metadata.imageProvider = NSItemProvider(object: image)
        return metadata
    }
}

// MARK: - ViewModel

@Observable @MainActor
private final class ImageViewerViewModel {
    let image: UIImage
    let sourceFrame: CGRect

    var currentFrame: CGRect
    var backgroundOpacity: Double = 0
    var showControls = false
    var dragOffset: CGFloat = 0
    var dragOffsetX: CGFloat = 0

    var isExpanded = false

    var dragProgress: CGFloat {
        min(max(dragOffset, 0) / 300, 1)
    }

    var dampedDragOffsetX: CGFloat {
        let maxResistance: CGFloat = 100
        return dragOffsetX / (1 + abs(dragOffsetX) / maxResistance)
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
            dragOffsetX = 0
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

    var body: some View {
        ZStack {
            Color.black
                .opacity(viewModel.backgroundOpacity * (1 - viewModel.dragProgress))
                .ignoresSafeArea()

            Image(uiImage: viewModel.image)
                .resizable()
                .frame(width: viewModel.currentFrame.width, height: viewModel.currentFrame.height)
                .scaleEffect(1 - viewModel.dragProgress * 0.1)
                .position(
                    x: viewModel.currentFrame.midX + viewModel.dampedDragOffsetX,
                    y: viewModel.currentFrame.midY + (viewModel.dragOffset > 0 ? viewModel.dragOffset : 0)
                )
        }
        .ignoresSafeArea()
    }
}

// MARK: - ZoomableImage

public struct ZoomableImage: View {
    private let uiImage: UIImage

    private var isActive: Bool {
        ImageViewerController.shared.activeImage === uiImage
    }

    public init(uiImage: UIImage) {
        self.uiImage = uiImage
    }

    public var body: some View {
        GeometryReader { geo in
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .opacity(isActive ? 0 : 1)
                .contentShape(Rectangle())
                .onTapGesture {
                    let frame = geo.frame(in: .global)
                    ImageViewerController.shared.show(image: uiImage, sourceFrame: frame)
                }
        }
        .aspectRatio(uiImage.size, contentMode: .fit)
    }
}
