import Foundation
import AVFoundation
import Combine
import UIKit

/// Single source of truth for playback. Both the phone UI and the CarPlay screen render
/// from this object, so they are always in sync.
final class PlaybackEngine: NSObject, ObservableObject {
    static let shared = PlaybackEngine()

    enum Backend: Equatable { case none, av, youtube }

    @Published private(set) var current: MediaItem?
    @Published private(set) var backend: Backend = .none
    @Published private(set) var isPlaying = false
    @Published private(set) var isBuffering = false
    @Published private(set) var currentTime: Double = 0
    @Published private(set) var duration: Double = 0
    @Published private(set) var errorMessage: String?
    @Published private(set) var playbackRate: Float = 1.0
    @Published var queue: [MediaItem] = []
    /// Set by the CarPlay scene delegate.
    @Published var carConnected = false

    let player = AVPlayer()
    let youtube = YouTubeBackend()

    private let library: LibraryStore
    private let settings: SettingsStore
    private var timeObserver: Any?
    private var statusObservation: NSKeyValueObservation?
    private var itemStatusObservation: NSKeyValueObservation?
    private var lastProgressSave = Date.distantPast
    private var pendingYouTubeTitleItemID: UUID?

    init(library: LibraryStore = .shared, settings: SettingsStore = .shared) {
        self.library = library
        self.settings = settings
        super.init()

        player.allowsExternalPlayback = true          // AirPlay video
        player.automaticallyWaitsToMinimizeStalling = true
        youtube.delegate = self

        configureAudioSession()

        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main
        ) { [weak self] time in
            self?.avTick(time)
        }

        statusObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] _, _ in
            DispatchQueue.main.async { self?.syncAVState() }
        }

        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(itemDidEnd(_:)), name: .AVPlayerItemDidPlayToEndTime, object: nil)
        nc.addObserver(self, selector: #selector(audioInterrupted(_:)), name: AVAudioSession.interruptionNotification, object: nil)
        nc.addObserver(self, selector: #selector(routeChanged(_:)), name: AVAudioSession.routeChangeNotification, object: nil)
        nc.addObserver(self, selector: #selector(appWillResignActive), name: UIApplication.willResignActiveNotification, object: nil)

        registerDarwinObservers()
    }

    // MARK: - Audio session

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .moviePlayback, options: [])
            try session.setActive(true)
        } catch {
            print("AudioSession error: \(error)")
        }
    }

    // MARK: - Public API

    /// Starts playing `item`. Resumes from the saved position unless `startAt` is given.
    func play(_ item: MediaItem, startAt: Double? = nil, autoplay: Bool = true) {
        saveProgress(force: true)
        errorMessage = nil

        let stored = library.add(item)
        var playing = library.item(withID: stored.id) ?? stored
        playing.lastPlayedAt = Date()
        library.markPlayed(id: playing.id)
        queue.removeAll { $0.id == playing.id }

        current = playing
        currentTime = 0
        duration = playing.duration
        let start = startAt ?? playing.resumePosition

        switch playing.kind {
        case .localFile, .remoteURL:
            youtube.pause()
            guard let url = resolveURL(for: playing) else {
                fail("Can't open this video. The file may have been removed.")
                return
            }
            backend = .av
            let asset = AVURLAsset(url: url)
            let item = AVPlayerItem(asset: asset)
            item.preferredForwardBufferDuration = 10
            itemStatusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
                DispatchQueue.main.async {
                    if item.status == .failed {
                        self?.fail(item.error?.localizedDescription ?? "Playback failed.")
                    } else if item.status == .readyToPlay {
                        let d = item.duration.seconds
                        if d.isFinite { self?.duration = d }
                        self?.publishNowPlaying()
                    }
                }
            }
            player.replaceCurrentItem(with: item)
            player.rate = 0
            if start > 1 {
                player.seek(to: CMTime(seconds: start, preferredTimescale: 600))
            }
            if autoplay {
                configureAudioSession()
                player.playImmediately(atRate: playbackRate)
            }

        case .youtube:
            player.pause()
            player.replaceCurrentItem(with: nil)
            backend = .youtube
            pendingYouTubeTitleItemID = playing.title.hasPrefix("YouTube ") ? playing.id : nil
            configureAudioSession()
            youtube.load(videoID: playing.reference, start: start, autoplay: autoplay)
            if playbackRate != 1 { youtube.setRate(Double(playbackRate)) }
        }

        publishNowPlaying()
        library.publishWidgetSnapshot(nowPlaying: playing, isPlaying: autoplay, progress: playing.progress)
    }

    func resume() {
        switch backend {
        case .av:
            configureAudioSession()
            player.playImmediately(atRate: playbackRate)
        case .youtube:
            youtube.play()
        case .none:
            if let last = current ?? library.lastPlayed { play(last) }
        }
    }

    func pause() {
        switch backend {
        case .av: player.pause()
        case .youtube: youtube.pause()
        case .none: break
        }
        saveProgress(force: true)
    }

    func togglePlayPause() {
        isPlaying ? pause() : resume()
    }

    func seek(to seconds: Double) {
        let target = max(0, duration > 0 ? min(seconds, duration - 0.5) : seconds)
        switch backend {
        case .av:
            player.seek(to: CMTime(seconds: target, preferredTimescale: 600),
                        toleranceBefore: .zero, toleranceAfter: .zero)
        case .youtube:
            youtube.seek(to: target)
        case .none:
            break
        }
        currentTime = target
        publishNowPlaying()
    }

    func skip(by delta: Double) { seek(to: currentTime + delta) }
    func skipForward() { skip(by: settings.settings.skipInterval) }
    func skipBackward() { skip(by: -settings.settings.skipInterval) }

    func next() {
        guard !queue.isEmpty else {
            seek(to: duration)
            return
        }
        let item = queue.removeFirst()
        play(item, startAt: 0)
    }

    func previous() {
        if currentTime > 5 || current == nil {
            seek(to: 0)
            return
        }
        // Jump to the most recently played item before this one.
        if let prev = library.recent.first(where: { $0.id != current?.id }) {
            if let cur = current { queue.insert(cur, at: 0) }
            play(prev)
        } else {
            seek(to: 0)
        }
    }

    func setRate(_ rate: Float) {
        playbackRate = rate
        switch backend {
        case .av: if isPlaying { player.rate = rate }
        case .youtube: youtube.setRate(Double(rate))
        case .none: break
        }
        publishNowPlaying()
    }

    func enqueue(_ item: MediaItem) {
        let stored = library.add(item)
        guard stored.id != current?.id, !queue.contains(where: { $0.id == stored.id }) else { return }
        queue.append(stored)
    }

    func playNext(_ item: MediaItem) {
        let stored = library.add(item)
        queue.removeAll { $0.id == stored.id }
        queue.insert(stored, at: 0)
    }

    func stop() {
        saveProgress(force: true)
        player.pause()
        player.replaceCurrentItem(with: nil)
        youtube.stop()
        backend = .none
        current = nil
        isPlaying = false
        currentTime = 0
        duration = 0
        NowPlayingController.shared.clear()
        library.publishWidgetSnapshot(isPlaying: false)
    }

    func clearError() { errorMessage = nil }

    /// Called when CarPlay connects: put something on screen right away.
    func prepareForCarConnection() {
        if let current {
            guard current.kind != .youtube,
                  settings.settings.autoPlayOnConnect,
                  !isPlaying else { return }
            resume()
            return
        }
        guard settings.settings.resumeOnConnect,
              let last = library.lastPlayed,
              last.kind != .youtube else { return }
        play(last, autoplay: settings.settings.autoPlayOnConnect)
    }

    // MARK: - Helpers

    private func resolveURL(for item: MediaItem) -> URL? {
        switch item.kind {
        case .localFile:
            guard let url = LibraryStore.localURL(for: item),
                  FileManager.default.fileExists(atPath: url.path) else { return nil }
            return url
        case .remoteURL:
            return URL(string: item.reference)
        case .youtube:
            return nil
        }
    }

    private func fail(_ message: String) {
        errorMessage = message
        isPlaying = false
        isBuffering = false
        publishNowPlaying()
    }

    private func avTick(_ time: CMTime) {
        guard backend == .av else { return }
        let t = time.seconds
        if t.isFinite { currentTime = t }
        if let d = player.currentItem?.duration.seconds, d.isFinite, d > 0 { duration = d }
        saveProgress(force: false)
    }

    private func syncAVState() {
        guard backend == .av else { return }
        let wasPlaying = isPlaying
        isPlaying = player.timeControlStatus != .paused
        isBuffering = player.timeControlStatus == .waitingToPlayAtSpecifiedRate
        if wasPlaying != isPlaying {
            publishNowPlaying()
            library.publishWidgetSnapshot(isPlaying: isPlaying, progress: duration > 0 ? currentTime / duration : 0)
        }
    }

    private func saveProgress(force: Bool) {
        guard let cur = current else { return }
        guard force || Date().timeIntervalSince(lastProgressSave) > 5 else { return }
        lastProgressSave = Date()
        library.updateProgress(id: cur.id, position: currentTime, duration: duration)
    }

    private func handleEnded() {
        saveProgress(force: true)
        isPlaying = false
        if settings.settings.autoAdvance, !queue.isEmpty {
            next()
        } else {
            publishNowPlaying()
            library.publishWidgetSnapshot(isPlaying: false, progress: 1)
        }
    }

    func publishNowPlaying() {
        NowPlayingController.shared.update(
            item: current,
            elapsed: currentTime,
            duration: duration,
            rate: isPlaying ? playbackRate : 0
        )
    }

    // MARK: - Notifications

    @objc private func itemDidEnd(_ note: Notification) {
        guard let item = note.object as? AVPlayerItem, item === player.currentItem else { return }
        DispatchQueue.main.async { self.handleEnded() }
    }

    @objc private func audioInterrupted(_ note: Notification) {
        guard let info = note.userInfo,
              let raw = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
        if type == .ended,
           let optRaw = info[AVAudioSessionInterruptionOptionKey] as? UInt,
           AVAudioSession.InterruptionOptions(rawValue: optRaw).contains(.shouldResume) {
            DispatchQueue.main.async { self.resume() }
        }
    }

    @objc private func routeChanged(_ note: Notification) {
        guard let raw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: raw) else { return }
        // Headphones / car audio unplugged -> pause, like every media app.
        if reason == .oldDeviceUnavailable {
            DispatchQueue.main.async { self.pause() }
        }
    }

    @objc private func appWillResignActive() {
        saveProgress(force: true)
        library.saveNow()
    }

    private func registerDarwinObservers() {
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        CFNotificationCenterAddObserver(center, nil, { _, _, _, _, _ in
            DispatchQueue.main.async { PlaybackEngine.shared.togglePlayPause() }
        }, AppConstants.darwinTogglePlayback as CFString, nil, .deliverImmediately)
        CFNotificationCenterAddObserver(center, nil, { _, _, _, _, _ in
            DispatchQueue.main.async { PlaybackEngine.shared.next() }
        }, AppConstants.darwinNext as CFString, nil, .deliverImmediately)
    }
}

// MARK: - YouTube delegate

extension PlaybackEngine: YouTubeBackendDelegate {
    func youtubeDidBecomeReady() {}

    func youtubeStateChanged(_ state: YouTubeBackend.PlayerState) {
        guard backend == .youtube else { return }
        let wasPlaying = isPlaying
        isPlaying = state == .playing
        isBuffering = state == .buffering
        if state == .playing { errorMessage = nil }
        if state == .ended { handleEnded(); return }
        if wasPlaying != isPlaying {
            publishNowPlaying()
            library.publishWidgetSnapshot(isPlaying: isPlaying, progress: duration > 0 ? currentTime / duration : 0)
        }
    }

    func youtubeTimeUpdated(current: Double, duration: Double) {
        guard backend == .youtube else { return }
        currentTime = current
        if duration > 0 { self.duration = duration }
        saveProgress(force: false)
    }

    func youtubeTitleUpdated(_ title: String) {
        guard backend == .youtube, let cur = current else { return }
        guard pendingYouTubeTitleItemID == cur.id || cur.title.hasPrefix("YouTube ") else { return }
        pendingYouTubeTitleItemID = nil
        library.rename(id: cur.id, to: title)
        var updated = cur
        updated.title = title
        self.current = updated
        publishNowPlaying()
        library.publishWidgetSnapshot(nowPlaying: updated)
    }

    func youtubeFailed(code: Int, message: String) {
        guard backend == .youtube else { return }
        fail(message)
    }
}
