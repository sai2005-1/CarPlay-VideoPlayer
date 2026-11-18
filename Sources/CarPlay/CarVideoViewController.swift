import UIKit
import SwiftUI
import Combine

/// Root view controller of the CarPlay window: video + overlay widgets + driving lock.
final class CarVideoViewController: UIViewController {
    private let engine: PlaybackEngine
    private let settings: SettingsStore
    private let sensors: SensorHub

    private let playerView = PlayerLayerView()
    private let youtubeContainer = UIView()
    private let placeholder = UIStackView()
    private let placeholderTitle = UILabel()
    private let errorLabel = UILabel()
    private let driveLockView = UIView()
    private let bufferingIndicator = UIActivityIndicatorView(style: .large)
    private var overlayHost: UIHostingController<OverlayLayerView>!
    private var cancellables = Set<AnyCancellable>()

    init(engine: PlaybackEngine, settings: SettingsStore, sensors: SensorHub) {
        self.engine = engine
        self.settings = settings
        self.sensors = sensors
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        // Video surfaces fill the entire car screen.
        playerView.player = engine.player
        for v in [playerView, youtubeContainer] {
            v.frame = view.bounds
            v.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            v.backgroundColor = .black
            view.addSubview(v)
        }
        youtubeContainer.clipsToBounds = true

        buildPlaceholder()
        buildErrorLabel()
        buildDriveLock()

        bufferingIndicator.color = .white
        bufferingIndicator.hidesWhenStopped = true
        bufferingIndicator.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(bufferingIndicator)
        NSLayoutConstraint.activate([
            bufferingIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            bufferingIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])

        // Overlay widgets live inside the safe area (clear of the CarPlay status bar / buttons).
        overlayHost = UIHostingController(rootView: OverlayLayerView(settingsStore: settings, engine: engine, sensors: sensors))
        overlayHost.view.backgroundColor = .clear
        overlayHost.view.isUserInteractionEnabled = false
        addChild(overlayHost)
        overlayHost.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(overlayHost.view)
        NSLayoutConstraint.activate([
            overlayHost.view.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            overlayHost.view.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            overlayHost.view.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            overlayHost.view.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
        ])
        overlayHost.didMove(toParent: self)

        // Drive lock sits above everything.
        view.bringSubviewToFront(driveLockView)

        bind()
        refresh()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        refresh()
    }

    // MARK: Binding

    private func bind() {
        let trigger = PassthroughSubject<Void, Never>()
        engine.$backend.sink { _ in trigger.send() }.store(in: &cancellables)
        engine.$current.sink { _ in trigger.send() }.store(in: &cancellables)
        engine.$errorMessage.sink { _ in trigger.send() }.store(in: &cancellables)
        engine.$isBuffering.sink { _ in trigger.send() }.store(in: &cancellables)
        engine.$carConnected.sink { _ in trigger.send() }.store(in: &cancellables)
        sensors.$isMoving.sink { _ in trigger.send() }.store(in: &cancellables)
        settings.$settings.sink { _ in trigger.send() }.store(in: &cancellables)

        // @Published fires on willSet; hop to the next runloop so we read the new values.
        trigger
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.refresh() }
            .store(in: &cancellables)
    }

    private func refresh() {
        guard isViewLoaded else { return }
        let backend = engine.backend
        let s = settings.settings

        playerView.isHidden = backend != .av
        youtubeContainer.isHidden = backend != .youtube
        if backend == .youtube && engine.carConnected {
            engine.youtube.attach(to: youtubeContainer)
        }
        playerView.playerLayer.videoGravity = s.fillCarScreen ? .resizeAspectFill : .resizeAspect

        placeholder.isHidden = backend != .none || engine.errorMessage != nil
        placeholderTitle.text = LibraryStore.shared.lastPlayed.map { "Last watched: \($0.title)" }
            ?? "Pick a video on your iPhone or tap Library"

        errorLabel.text = engine.errorMessage
        errorLabel.isHidden = engine.errorMessage == nil

        if engine.isBuffering && backend != .none { bufferingIndicator.startAnimating() }
        else { bufferingIndicator.stopAnimating() }

        let locked = s.speedLockEnabled && sensors.isMoving && backend != .none
        driveLockView.alpha = 1
        driveLockView.isHidden = !locked
        if locked { view.bringSubviewToFront(driveLockView) }
    }

    // MARK: Subviews

    private func buildPlaceholder() {
        let icon = UIImageView(image: UIImage(systemName: "play.rectangle.on.rectangle"))
        icon.tintColor = .white
        icon.contentMode = .scaleAspectFit
        icon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 44, weight: .regular)

        let title = UILabel()
        title.text = "CarPlay Video"
        title.font = .systemFont(ofSize: 24, weight: .bold)
        title.textColor = .white

        placeholderTitle.font = .systemFont(ofSize: 15, weight: .regular)
        placeholderTitle.textColor = UIColor.white.withAlphaComponent(0.7)
        placeholderTitle.textAlignment = .center
        placeholderTitle.numberOfLines = 2

        placeholder.axis = .vertical
        placeholder.alignment = .center
        placeholder.spacing = 10
        [icon, title, placeholderTitle].forEach { placeholder.addArrangedSubview($0) }
        placeholder.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(placeholder)
        NSLayoutConstraint.activate([
            placeholder.centerXAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerXAnchor),
            placeholder.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerYAnchor),
            placeholder.leadingAnchor.constraint(greaterThanOrEqualTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 20),
        ])
    }

    private func buildErrorLabel() {
        errorLabel.textColor = .white
        errorLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        errorLabel.numberOfLines = 0
        errorLabel.textAlignment = .center
        errorLabel.backgroundColor = UIColor.systemRed.withAlphaComponent(0.85)
        errorLabel.layer.cornerRadius = 10
        errorLabel.layer.masksToBounds = true
        errorLabel.isHidden = true
        errorLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(errorLabel)
        NSLayoutConstraint.activate([
            errorLabel.centerXAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerXAnchor),
            errorLabel.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerYAnchor),
            errorLabel.widthAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.widthAnchor, multiplier: 0.8),
            errorLabel.heightAnchor.constraint(greaterThanOrEqualToConstant: 56),
        ])
    }

    private func buildDriveLock() {
        driveLockView.backgroundColor = UIColor.black.withAlphaComponent(0.92)
        driveLockView.frame = view.bounds
        driveLockView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        driveLockView.isHidden = true
        driveLockView.alpha = 0

        let icon = UIImageView(image: UIImage(systemName: "car.fill"))
        icon.tintColor = .white
        icon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 40, weight: .regular)
        let title = UILabel()
        title.text = "Video paused while driving"
        title.font = .systemFont(ofSize: 22, weight: .bold)
        title.textColor = .white
        let subtitle = UILabel()
        subtitle.text = "Audio keeps playing. Video returns when the car stops."
        subtitle.font = .systemFont(ofSize: 15)
        subtitle.textColor = UIColor.white.withAlphaComponent(0.75)
        subtitle.numberOfLines = 0
        subtitle.textAlignment = .center

        let stack = UIStackView(arrangedSubviews: [icon, title, subtitle])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        driveLockView.addSubview(stack)
        view.addSubview(driveLockView)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: driveLockView.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: driveLockView.centerYAnchor),
            stack.widthAnchor.constraint(lessThanOrEqualTo: driveLockView.widthAnchor, multiplier: 0.85),
        ])
    }
}
