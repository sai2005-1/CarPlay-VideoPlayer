import Foundation

/// Identifiers shared between the app and the widget extension.
enum AppConstants {
    static let appGroup = "group.com.saibh.carplayvideo"
    static let urlScheme = "carplayvideo"
    static let darwinTogglePlayback = "com.saibh.carplayvideo.togglePlayback"
    static let darwinNext = "com.saibh.carplayvideo.next"
    static let widgetSnapshotKey = "widgetSnapshot.v1"
    static let widgetKindContinue = "ContinueWatchingWidget"
    static let widgetKindControls = "PlaybackControlsWidget"

    /// UserDefaults shared through the App Group (falls back to standard if the group is unavailable,
    /// e.g. when sideloaded without the entitlement).
    static var sharedDefaults: UserDefaults {
        UserDefaults(suiteName: appGroup) ?? .standard
    }

    /// Shared container directory (falls back to the app's Application Support directory).
    static var sharedContainer: URL {
        if let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup) {
            return url
        }
        let fallback = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: fallback, withIntermediateDirectories: true)
        return fallback
    }
}

// MARK: - Media

enum MediaKind: String, Codable, CaseIterable {
    /// A video file copied into the app's Documents/Videos folder.
    case localFile
    /// Any http(s) URL AVPlayer can open (mp4, mov, m3u8 HLS, ...).
    case remoteURL
    /// A YouTube video, played via the official IFrame player.
    case youtube

    var label: String {
        switch self {
        case .localFile: return "On Device"
        case .remoteURL: return "Stream"
        case .youtube: return "YouTube"
        }
    }

    var symbol: String {
        switch self {
        case .localFile: return "film"
        case .remoteURL: return "link"
        case .youtube: return "play.rectangle.fill"
        }
    }
}

struct MediaItem: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var title: String
    var kind: MediaKind
    /// For `.localFile`: file name relative to Documents/Videos. For `.remoteURL`: absolute URL. For `.youtube`: video ID.
    var reference: String
    var addedAt: Date = Date()
    var lastPlayedAt: Date?
    /// Resume position in seconds.
    var resumePosition: Double = 0
    var duration: Double = 0

    var progress: Double {
        guard duration > 0 else { return 0 }
        return min(max(resumePosition / duration, 0), 1)
    }

    var youtubeThumbnailURL: URL? {
        guard kind == .youtube else { return nil }
        return URL(string: "https://i.ytimg.com/vi/\(reference)/hqdefault.jpg")
    }
}

// MARK: - Widget snapshot (written by the app, read by the widget extension)

struct WidgetSnapshot: Codable {
    struct Entry: Codable, Hashable, Identifiable {
        var id: UUID
        var title: String
        var kind: MediaKind
        var progress: Double
    }

    var nowPlayingTitle: String?
    var nowPlayingKind: MediaKind?
    var isPlaying: Bool = false
    var progress: Double = 0
    var recent: [Entry] = []
    var updatedAt: Date = Date()

    static func load() -> WidgetSnapshot {
        guard let data = AppConstants.sharedDefaults.data(forKey: AppConstants.widgetSnapshotKey),
              let snap = try? JSONDecoder().decode(WidgetSnapshot.self, from: data) else {
            return WidgetSnapshot()
        }
        return snap
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            AppConstants.sharedDefaults.set(data, forKey: AppConstants.widgetSnapshotKey)
        }
    }
}

// MARK: - Cross-process signalling (widget buttons -> app)

enum DarwinNotifier {
    static func post(_ name: String) {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(name as CFString),
            nil, nil, true
        )
    }
}
