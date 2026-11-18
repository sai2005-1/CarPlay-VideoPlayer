import Foundation
import SwiftUI
import Combine

// MARK: - Overlay widget configuration (widgets drawn on top of the CarPlay video)

enum OverlayWidgetKind: String, Codable, CaseIterable, Identifiable {
    case clock, date, speed, battery, nowPlaying, weather

    var id: String { rawValue }

    var title: String {
        switch self {
        case .clock: return "Clock"
        case .date: return "Date"
        case .speed: return "Speed"
        case .battery: return "Phone Battery"
        case .nowPlaying: return "Now Playing"
        case .weather: return "Weather"
        }
    }

    var symbol: String {
        switch self {
        case .clock: return "clock"
        case .date: return "calendar"
        case .speed: return "speedometer"
        case .battery: return "battery.75"
        case .nowPlaying: return "play.circle"
        case .weather: return "cloud.sun"
        }
    }
}

enum OverlayPosition: String, Codable, CaseIterable, Identifiable {
    case topLeading, top, topTrailing, bottomLeading, bottom, bottomTrailing

    var id: String { rawValue }

    var title: String {
        switch self {
        case .topLeading: return "Top Left"
        case .top: return "Top Center"
        case .topTrailing: return "Top Right"
        case .bottomLeading: return "Bottom Left"
        case .bottom: return "Bottom Center"
        case .bottomTrailing: return "Bottom Right"
        }
    }

    var alignment: Alignment {
        switch self {
        case .topLeading: return .topLeading
        case .top: return .top
        case .topTrailing: return .topTrailing
        case .bottomLeading: return .bottomLeading
        case .bottom: return .bottom
        case .bottomTrailing: return .bottomTrailing
        }
    }

    var isTop: Bool { [.topLeading, .top, .topTrailing].contains(self) }
}

struct OverlayWidgetConfig: Codable, Hashable, Identifiable {
    var kind: OverlayWidgetKind
    var enabled: Bool
    var position: OverlayPosition
    /// 0.6 ... 1.8
    var scale: Double = 1.0
    /// Background opacity 0 ... 1
    var opacity: Double = 0.55

    var id: String { kind.rawValue }

    static let defaults: [OverlayWidgetConfig] = [
        OverlayWidgetConfig(kind: .clock, enabled: true, position: .topTrailing),
        OverlayWidgetConfig(kind: .date, enabled: false, position: .topTrailing),
        OverlayWidgetConfig(kind: .speed, enabled: false, position: .topLeading),
        OverlayWidgetConfig(kind: .battery, enabled: false, position: .topLeading),
        OverlayWidgetConfig(kind: .nowPlaying, enabled: true, position: .bottomLeading),
        OverlayWidgetConfig(kind: .weather, enabled: false, position: .topLeading),
    ]
}

enum OverlayAccent: String, Codable, CaseIterable, Identifiable {
    case white, blue, green, orange, pink, purple, yellow

    var id: String { rawValue }
    var color: Color {
        switch self {
        case .white: return .white
        case .blue: return .blue
        case .green: return .green
        case .orange: return .orange
        case .pink: return .pink
        case .purple: return .purple
        case .yellow: return .yellow
        }
    }
}

// MARK: - App settings

struct AppSettings: Codable, Equatable {
    /// Pause video (keep audio) on the car screen while the vehicle is moving.
    var speedLockEnabled: Bool = true
    /// Threshold in km/h above which the car is considered moving.
    var speedThresholdKmh: Double = 8
    var useMetricUnits: Bool = Locale.current.measurementSystem == .metric
    /// Aspect-fill (crop) instead of aspect-fit (letterbox) on the car screen.
    var fillCarScreen: Bool = false
    /// Restore the last video when CarPlay connects.
    var resumeOnConnect: Bool = true
    /// Automatically start playback when CarPlay connects.
    var autoPlayOnConnect: Bool = false
    /// Continue to the next item in the queue when a video ends.
    var autoAdvance: Bool = true
    var skipInterval: Double = 15
    var showOverlays: Bool = true
    var overlays: [OverlayWidgetConfig] = OverlayWidgetConfig.defaults
    var overlayAccent: OverlayAccent = .white
    var use24HourClock: Bool = false

    init() {}

    // Tolerant decoding so new settings never wipe saved ones.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings()
        speedLockEnabled = (try? c.decode(Bool.self, forKey: .speedLockEnabled)) ?? d.speedLockEnabled
        speedThresholdKmh = (try? c.decode(Double.self, forKey: .speedThresholdKmh)) ?? d.speedThresholdKmh
        useMetricUnits = (try? c.decode(Bool.self, forKey: .useMetricUnits)) ?? d.useMetricUnits
        fillCarScreen = (try? c.decode(Bool.self, forKey: .fillCarScreen)) ?? d.fillCarScreen
        resumeOnConnect = (try? c.decode(Bool.self, forKey: .resumeOnConnect)) ?? d.resumeOnConnect
        autoPlayOnConnect = (try? c.decode(Bool.self, forKey: .autoPlayOnConnect)) ?? d.autoPlayOnConnect
        autoAdvance = (try? c.decode(Bool.self, forKey: .autoAdvance)) ?? d.autoAdvance
        skipInterval = (try? c.decode(Double.self, forKey: .skipInterval)) ?? d.skipInterval
        showOverlays = (try? c.decode(Bool.self, forKey: .showOverlays)) ?? d.showOverlays
        overlayAccent = (try? c.decode(OverlayAccent.self, forKey: .overlayAccent)) ?? d.overlayAccent
        use24HourClock = (try? c.decode(Bool.self, forKey: .use24HourClock)) ?? d.use24HourClock
        var saved = (try? c.decode([OverlayWidgetConfig].self, forKey: .overlays)) ?? d.overlays
        // Add any widget kinds introduced after the settings were saved.
        for def in OverlayWidgetConfig.defaults where !saved.contains(where: { $0.kind == def.kind }) {
            saved.append(def)
        }
        overlays = saved
    }
}

final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()
    private static let key = "appSettings.v1"

    @Published var settings: AppSettings {
        didSet {
            guard settings != oldValue else { return }
            save()
        }
    }

    init(defaults: UserDefaults = AppConstants.sharedDefaults) {
        if let data = defaults.data(forKey: Self.key),
           let s = try? JSONDecoder().decode(AppSettings.self, from: data) {
            settings = s
        } else {
            settings = AppSettings()
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(settings) {
            AppConstants.sharedDefaults.set(data, forKey: Self.key)
        }
    }

    func binding(for kind: OverlayWidgetKind) -> Binding<OverlayWidgetConfig> {
        Binding(
            get: { self.settings.overlays.first(where: { $0.kind == kind })
                ?? OverlayWidgetConfig(kind: kind, enabled: false, position: .topLeading) },
            set: { newValue in
                if let i = self.settings.overlays.firstIndex(where: { $0.kind == kind }) {
                    self.settings.overlays[i] = newValue
                } else {
                    self.settings.overlays.append(newValue)
                }
            }
        )
    }

    func resetOverlays() {
        settings.overlays = OverlayWidgetConfig.defaults
        settings.overlayAccent = .white
    }
}
