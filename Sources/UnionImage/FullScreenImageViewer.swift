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

    public func show(
        image: UIImage,
        sourceFrame: CGRect,
        sourceCornerRadius: CGFloat = 0,
        expandedCornerRadius: CGFloat = 0,
        showsControls: Bool = true
    ) {
        guard let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first else { return }

        activeImage = image

        let viewModel = ImageViewerViewModel(
            image: image,
            sourceFrame: sourceFrame,
            sourceCornerRadius: sourceCornerRadius,
            expandedCornerRadius: expandedCornerRadius
        )
        let viewerVC = ImageViewerViewController(viewModel: viewModel, showsControls: showsControls) { [weak self] in
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

        window.layoutIfNeeded()

        DispatchQueue.main.async {
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
    private let showsControls: Bool
    private let onDismiss: @MainActor () -> Void
    private var hostingController: UIHostingController<ImageViewerOverlay>?
    private var saveButton: UIBarButtonItem?

    override var prefersStatusBarHidden: Bool {
        !viewModel.showControls && !viewModel.isDismissing
    }

    override var preferredStatusBarUpdateAnimation: UIStatusBarAnimation {
        .fade
    }

    init(viewModel: ImageViewerViewModel, showsControls: Bool, onDismiss: @escaping @MainActor () -> Void) {
        self.viewModel = viewModel
        self.showsControls = showsControls
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

        if showsControls {
            setupToolbar()
        }

        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        view.addGestureRecognizer(panGesture)

        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        view.addGestureRecognizer(tapGesture)
    }

    private func setupNavigationBar() {
        let closeButton = UIBarButtonItem(systemItem: .close, primaryAction: UIAction { [weak self] _ in
            guard let self else { return }
            viewModel.collapse(completion: onDismiss)
            setNeedsStatusBarAppearanceUpdate()
        })
        navigationItem.rightBarButtonItem = closeButton
        navigationController?.setNavigationBarHidden(!viewModel.showControls, animated: false)
    }

    private func setupToolbar() {
        let saveButton = UIBarButtonItem(image: UIImage(systemName: "square.and.arrow.down"), primaryAction: UIAction { [weak self] _ in
            guard let self else { return }
            UIImageWriteToSavedPhotosAlbum(viewModel.image, self, #selector(imageSaveCompleted(_:didFinishSavingWithError:contextInfo:)), nil)
        })
        self.saveButton = saveButton
        let shareButton = UIBarButtonItem(systemItem: .action, primaryAction: UIAction { [weak self] _ in
            guard let self else { return }
            let itemSource = ImageActivityItemSource(image: viewModel.image)
            let activityVC = UIActivityViewController(activityItems: [itemSource], applicationActivities: nil)
            activityVC.popoverPresentationController?.barButtonItem = self.toolbarItems?.last
            present(activityVC, animated: true)
        })
        let spacer = UIBarButtonItem(systemItem: .flexibleSpace)
        toolbarItems = [spacer, saveButton, shareButton]
        navigationController?.setToolbarHidden(!viewModel.showControls, animated: false)
        navigationController?.toolbar.backgroundColor = .clear
    }

    @objc private func imageSaveCompleted(_ image: UIImage, didFinishSavingWithError error: Error?, contextInfo: UnsafeRawPointer) {
        if error == nil {
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
            saveButton?.image = UIImage(systemName: "square.and.arrow.down.fill")
            saveButton?.isEnabled = false
        }
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
                setNeedsStatusBarAppearanceUpdate()
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
        guard showsControls else { return }
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
    let sourceCornerRadius: CGFloat
    let expandedCornerRadius: CGFloat

    var currentFrame: CGRect
    var currentCornerRadius: CGFloat
    var backgroundOpacity: Double = 0
    var showControls = false
    var dragOffset: CGFloat = 0
    var dragOffsetX: CGFloat = 0

    var isExpanded = false
    var isDismissing = false

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
        let screenSize = screenBounds.size

        let sourceAspect = sourceFrame.width / sourceFrame.height
        let isSourceSquare = abs(sourceAspect - 1.0) < 0.1

        if isSourceSquare {
            let size = min(screenSize.width, screenSize.height)
            return CGRect(
                x: (screenSize.width - size) / 2,
                y: (screenSize.height - size) / 2,
                width: size,
                height: size
            )
        } else {
            let imageSize = image.size
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
    }

    var currentAspectRatio: CGFloat {
        guard currentFrame.height > 0 else { return 1 }
        return currentFrame.width / currentFrame.height
    }

    var shouldUseFillMode: Bool {
        abs(currentAspectRatio - 1.0) < 0.1
    }

    init(image: UIImage, sourceFrame: CGRect, sourceCornerRadius: CGFloat = 0, expandedCornerRadius: CGFloat = 0) {
        self.image = image
        self.sourceFrame = sourceFrame
        self.sourceCornerRadius = sourceCornerRadius
        self.expandedCornerRadius = expandedCornerRadius
        self.currentFrame = sourceFrame
        self.currentCornerRadius = sourceCornerRadius
    }

    func expand() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            currentFrame = expandedFrame
            currentCornerRadius = expandedCornerRadius
            backgroundOpacity = 1
            isExpanded = true
        }
    }

    func collapse(completion: @escaping @MainActor () -> Void) {
        isDismissing = true

        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            currentFrame = sourceFrame
            currentCornerRadius = sourceCornerRadius
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
                .aspectRatio(contentMode: viewModel.shouldUseFillMode ? .fill : .fit)
                .frame(width: viewModel.currentFrame.width, height: viewModel.currentFrame.height)
                .clipShape(RoundedRectangle(cornerRadius: viewModel.currentCornerRadius))
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
    private let sourceCornerRadius: CGFloat
    private let expandedCornerRadius: CGFloat
    private let showsControls: Bool

    private var isActive: Bool {
        ImageViewerController.shared.activeImage === uiImage
    }

    public init(uiImage: UIImage, sourceCornerRadius: CGFloat = 0, expandedCornerRadius: CGFloat = 0, showsControls: Bool = true) {
        self.uiImage = uiImage
        self.sourceCornerRadius = sourceCornerRadius
        self.expandedCornerRadius = expandedCornerRadius
        self.showsControls = showsControls
    }

    public var body: some View {
        GeometryReader { geo in
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .frame(width: geo.size.width, height: geo.size.height)
                .opacity(isActive ? 0 : 1)
                .contentShape(Rectangle())
                .onTapGesture {
                    let frame = geo.frame(in: .global)
                    ImageViewerController.shared.show(
                        image: uiImage,
                        sourceFrame: frame,
                        sourceCornerRadius: sourceCornerRadius,
                        expandedCornerRadius: expandedCornerRadius,
                        showsControls: showsControls
                    )
                }
        }
    }
}
