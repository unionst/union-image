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

        let viewerVC = ImageViewerViewController(
            image: image,
            sourceFrame: sourceFrame,
            sourceCornerRadius: sourceCornerRadius,
            expandedCornerRadius: expandedCornerRadius,
            showsControls: showsControls,
            onDismiss: { [weak self] in
                self?.dismiss()
            }
        )

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
            viewerVC.expandImage()
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

private class ImageViewerViewController: UIViewController, UIScrollViewDelegate, UIGestureRecognizerDelegate {
    private let image: UIImage
    private let sourceFrame: CGRect
    private let sourceCornerRadius: CGFloat
    private let expandedCornerRadius: CGFloat
    private let showsControls: Bool
    private let onDismiss: @MainActor () -> Void

    private let backgroundView = UIView()
    private let imageView = UIImageView()
    private var scrollView: UIScrollView?
    private var panGesture: UIPanGestureRecognizer!
    private var singleTapGesture: UITapGestureRecognizer!
    private var saveButton: UIBarButtonItem?
    private var controlsVisible = false
    private var isDismissing = false

    private var expandedFrame: CGRect {
        let screenSize = UIScreen.main.bounds.size
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

    override var prefersStatusBarHidden: Bool {
        !controlsVisible && !isDismissing
    }

    override var preferredStatusBarUpdateAnimation: UIStatusBarAnimation {
        .fade
    }

    init(
        image: UIImage,
        sourceFrame: CGRect,
        sourceCornerRadius: CGFloat,
        expandedCornerRadius: CGFloat,
        showsControls: Bool,
        onDismiss: @escaping @MainActor () -> Void
    ) {
        self.image = image
        self.sourceFrame = sourceFrame
        self.sourceCornerRadius = sourceCornerRadius
        self.expandedCornerRadius = expandedCornerRadius
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

        backgroundView.backgroundColor = .black
        backgroundView.alpha = 0
        backgroundView.frame = view.bounds
        backgroundView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(backgroundView)

        imageView.image = image
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.bounds = CGRect(origin: .zero, size: sourceFrame.size)
        imageView.center = CGPoint(x: sourceFrame.midX, y: sourceFrame.midY)
        imageView.layer.cornerRadius = sourceCornerRadius
        view.addSubview(imageView)

        setupNavigationBar()
        if showsControls { setupToolbar() }

        panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        panGesture.delegate = self
        view.addGestureRecognizer(panGesture)

        singleTapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        singleTapGesture.numberOfTapsRequired = 1
        view.addGestureRecognizer(singleTapGesture)
    }

    func expandImage() {
        let expanded = expandedFrame
        UIView.animate(
            withDuration: 0.5,
            delay: 0,
            usingSpringWithDamping: 0.85,
            initialSpringVelocity: 0,
            options: [],
            animations: {
                self.imageView.bounds.size = expanded.size
                self.imageView.center = CGPoint(x: expanded.midX, y: expanded.midY)
                self.imageView.layer.cornerRadius = self.expandedCornerRadius
                self.backgroundView.alpha = 1
            },
            completion: { _ in
                self.installScrollView()
            }
        )
    }

    private func installScrollView() {
        let sv = UIScrollView(frame: view.bounds)
        sv.delegate = self
        sv.minimumZoomScale = 1.0
        sv.maximumZoomScale = 5.0
        sv.showsHorizontalScrollIndicator = false
        sv.showsVerticalScrollIndicator = false
        sv.contentInsetAdjustmentBehavior = .never
        sv.bouncesZoom = true

        let expanded = expandedFrame
        imageView.removeFromSuperview()
        imageView.transform = .identity
        imageView.frame = CGRect(origin: .zero, size: expanded.size)
        sv.addSubview(imageView)
        sv.contentSize = expanded.size

        view.insertSubview(sv, aboveSubview: backgroundView)
        self.scrollView = sv

        scrollViewDidZoom(sv)

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        sv.addGestureRecognizer(doubleTap)
        singleTapGesture.require(toFail: doubleTap)
    }

    private func uninstallScrollView() {
        guard let sv = scrollView else { return }
        sv.setZoomScale(1.0, animated: false)
        let expanded = expandedFrame
        imageView.removeFromSuperview()
        imageView.transform = .identity
        imageView.bounds.size = expanded.size
        imageView.center = CGPoint(x: expanded.midX, y: expanded.midY)
        view.addSubview(imageView)
        sv.removeFromSuperview()
        self.scrollView = nil
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        imageView
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        let imageSize = imageView.frame.size
        let scrollSize = scrollView.bounds.size
        let verticalInset = max(0, (scrollSize.height - imageSize.height) / 2)
        let horizontalInset = max(0, (scrollSize.width - imageSize.width) / 2)
        scrollView.contentInset = UIEdgeInsets(
            top: verticalInset, left: horizontalInset,
            bottom: verticalInset, right: horizontalInset
        )
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer === panGesture {
            return scrollView?.zoomScale ?? 1.0 <= 1.01
        }
        return true
    }

    private func collapseImage(completion: @escaping @MainActor () -> Void) {
        uninstallScrollView()
        isDismissing = true
        setNeedsStatusBarAppearanceUpdate()

        if imageView.transform != .identity {
            let t = imageView.transform
            let scale = sqrt(t.a * t.a + t.c * t.c)
            let visualWidth = imageView.bounds.width * scale
            let visualHeight = imageView.bounds.height * scale
            let visualCenter = CGPoint(
                x: imageView.center.x + t.tx,
                y: imageView.center.y + t.ty
            )
            UIView.performWithoutAnimation {
                self.imageView.transform = .identity
                self.imageView.bounds.size = CGSize(width: visualWidth, height: visualHeight)
                self.imageView.center = visualCenter
            }
        }

        UIView.animate(
            withDuration: 0.35,
            delay: 0,
            usingSpringWithDamping: 0.85,
            initialSpringVelocity: 0,
            options: [.beginFromCurrentState],
            animations: {
                self.imageView.bounds.size = self.sourceFrame.size
                self.imageView.center = CGPoint(x: self.sourceFrame.midX, y: self.sourceFrame.midY)
                self.imageView.layer.cornerRadius = self.sourceCornerRadius
                self.backgroundView.alpha = 0
            },
            completion: { _ in
                completion()
            }
        )
    }

    private func setupNavigationBar() {
        let closeButton = UIBarButtonItem(systemItem: .close, primaryAction: UIAction { [weak self] _ in
            guard let self else { return }
            collapseImage(completion: onDismiss)
        })
        navigationItem.rightBarButtonItem = closeButton
        navigationController?.setNavigationBarHidden(!controlsVisible, animated: false)
    }

    private func setupToolbar() {
        let saveButton = UIBarButtonItem(image: UIImage(systemName: "square.and.arrow.down"), primaryAction: UIAction { [weak self] _ in
            guard let self else { return }
            UIImageWriteToSavedPhotosAlbum(image, self, #selector(imageSaveCompleted(_:didFinishSavingWithError:contextInfo:)), nil)
        })
        self.saveButton = saveButton
        let shareButton = UIBarButtonItem(systemItem: .action, primaryAction: UIAction { [weak self] _ in
            guard let self else { return }
            let itemSource = ImageActivityItemSource(image: image)
            let activityVC = UIActivityViewController(activityItems: [itemSource], applicationActivities: nil)
            activityVC.popoverPresentationController?.barButtonItem = self.toolbarItems?.last
            present(activityVC, animated: true)
        })
        let spacer = UIBarButtonItem(systemItem: .flexibleSpace)
        toolbarItems = [spacer, saveButton, shareButton]
        navigationController?.setToolbarHidden(!controlsVisible, animated: false)
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

    @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        guard let sv = scrollView else { return }
        if sv.zoomScale > sv.minimumZoomScale {
            sv.setZoomScale(sv.minimumZoomScale, animated: true)
        } else {
            let point = gesture.location(in: imageView)
            let targetScale: CGFloat = 3.0
            let width = sv.bounds.width / targetScale
            let height = sv.bounds.height / targetScale
            let rect = CGRect(
                x: point.x - width / 2,
                y: point.y - height / 2,
                width: width,
                height: height
            )
            sv.zoom(to: rect, animated: true)
        }
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        let translation = gesture.translation(in: view)

        switch gesture.state {
        case .began:
            uninstallScrollView()

        case .changed:
            let progress = min(max(translation.y, 0) / 300, 1)
            let dampedX = translation.x / (1 + abs(translation.x) / 100)
            let offsetY = translation.y > 0 ? translation.y : 0
            let scale = 1 - progress * 0.1

            imageView.transform = CGAffineTransform(translationX: dampedX, y: offsetY)
                .scaledBy(x: scale, y: scale)
            backgroundView.alpha = 1 - progress

        case .ended, .cancelled:
            let velocity = gesture.velocity(in: view).y
            let shouldDismiss = translation.y > 100 || velocity > 300

            if shouldDismiss {
                collapseImage(completion: onDismiss)
            } else {
                UIView.animate(
                    withDuration: 0.4,
                    delay: 0,
                    usingSpringWithDamping: 0.85,
                    initialSpringVelocity: 0,
                    options: [],
                    animations: {
                        self.imageView.transform = .identity
                        self.backgroundView.alpha = 1
                    },
                    completion: { _ in
                        self.installScrollView()
                    }
                )
            }

        default:
            break
        }
    }

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        guard showsControls else { return }
        controlsVisible.toggle()
        UIView.animate(withDuration: 0.2) {
            self.navigationController?.setNavigationBarHidden(!self.controlsVisible, animated: true)
            self.navigationController?.setToolbarHidden(!self.controlsVisible, animated: true)
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
