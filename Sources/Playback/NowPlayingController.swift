import Foundation
import MediaPlayer
import UIKit

/// Lock screen / Control Center / CarPlay Now Playing info and remote commands
/// (steering-wheel buttons, Siri, headphones).
final class NowPlayingController {
    static let shared = NowPlayingController()

    private var artworkCache: [String: MPMediaItemArtwork] = [:]
    private var commandsRegistered = false

    func registerCommands(engine: PlaybackEngine = .shared) {
        guard !commandsRegistered else { return }
        commandsRegistered = true
        let c = MPRemoteCommandCenter.shared()

        c.playCommand.addTarget { _ in engine.resume(); return .success }
        c.pauseCommand.addTarget { _ in engine.pause(); return .success }
        c.togglePlayPauseCommand.addTarget { _ in engine.togglePlayPause(); return .success }
        c.stopCommand.addTarget { _ in engine.pause(); return .success }

        c.skipForwardCommand.preferredIntervals = [NSNumber(value: SettingsStore.shared.settings.skipInterval)]
        c.skipBackwardCommand.preferredIntervals = [NSNumber(value: SettingsStore.shared.settings.skipInterval)]
        c.skipForwardCommand.addTarget { event in
            let interval = (event as? MPSkipIntervalCommandEvent)?.interval ?? SettingsStore.shared.settings.skipInterval
            engine.skip(by: interval); return .success
        }
        c.skipBackwardCommand.addTarget { event in
            let interval = (event as? MPSkipIntervalCommandEvent)?.interval ?? SettingsStore.shared.settings.skipInterval
            engine.skip(by: -interval); return .success
        }

        c.nextTrackCommand.addTarget { _ in engine.next(); return .success }
        c.previousTrackCommand.addTarget { _ in engine.previous(); return .success }

        c.changePlaybackPositionCommand.addTarget { event in
            guard let e = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            engine.seek(to: e.positionTime)
            return .success
        }
        c.changePlaybackRateCommand.supportedPlaybackRates = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]
        c.changePlaybackRateCommand.addTarget { event in
            guard let e = event as? MPChangePlaybackRateCommandEvent else { return .commandFailed }
            engine.setRate(e.playbackRate)
            return .success
        }
    }

    func update(item: MediaItem?, elapsed: Double, duration: Double, rate: Float) {
        guard let item = item else { clear(); return }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: item.title,
            MPMediaItemPropertyArtist: item.kind.label,
            MPMediaItemPropertyAlbumTitle: "CarPlay Video",
            MPNowPlayingInfoPropertyElapsedPlaybackTime: elapsed.isFinite ? elapsed : 0,
            MPNowPlayingInfoPropertyPlaybackRate: rate,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.video.rawValue,
        ]
        if duration.isFinite, duration > 0 {
            info[MPMediaItemPropertyPlaybackDuration] = duration
        }
        if let art = artworkCache[item.reference] {
            info[MPMediaItemPropertyArtwork] = art
        } else {
            loadArtwork(for: item)
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        MPNowPlayingInfoCenter.default().playbackState = rate > 0 ? .playing : .paused
    }

    func clear() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        MPNowPlayingInfoCenter.default().playbackState = .stopped
    }

    private func loadArtwork(for item: MediaItem) {
        guard let url = item.youtubeThumbnailURL else { return }
        let key = item.reference
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data = data, let image = UIImage(data: data) else { return }
            let art = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.artworkCache[key] = art
                if var info = MPNowPlayingInfoCenter.default().nowPlayingInfo {
                    info[MPMediaItemPropertyArtwork] = art
                    MPNowPlayingInfoCenter.default().nowPlayingInfo = info
                }
            }
        }.resume()
    }
}
