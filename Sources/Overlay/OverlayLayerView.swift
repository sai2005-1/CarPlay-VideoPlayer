import SwiftUI

/// Draws the user's enabled overlay widgets on top of the video.
/// Used on the CarPlay screen and in the phone's live Widget Editor preview.
struct OverlayLayerView: View {
    @ObservedObject var settingsStore: SettingsStore
    @ObservedObject var engine: PlaybackEngine
    @ObservedObject var sensors: SensorHub
    /// Scales everything (the editor preview is smaller than the car screen).
    var baseScale: CGFloat = 1.0

    var body: some View {
        let s = settingsStore.settings
        ZStack {
            if s.showOverlays {
                ForEach(OverlayPosition.allCases) { position in
                    let widgets = s.overlays.filter { $0.enabled && $0.position == position }
                    if !widgets.isEmpty {
                        VStack(alignment: horizontalAlignment(position), spacing: 6 * baseScale) {
                            ForEach(widgets) { config in
                                OverlayChip(config: config, accent: s.overlayAccent.color, baseScale: baseScale) {
                                    content(for: config.kind, settings: s)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: position.alignment)
                        .padding(10 * baseScale)
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func horizontalAlignment(_ p: OverlayPosition) -> HorizontalAlignment {
        switch p {
        case .topLeading, .bottomLeading: return .leading
        case .top, .bottom: return .center
        case .topTrailing, .bottomTrailing: return .trailing
        }
    }

    @ViewBuilder
    private func content(for kind: OverlayWidgetKind, settings s: AppSettings) -> some View {
        switch kind {
        case .clock:
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                Text(Self.clockString(ctx.date, use24h: s.use24HourClock))
                    .font(.system(size: 20 * baseScale, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }
        case .date:
            TimelineView(.periodic(from: .now, by: 60)) { ctx in
                Text(ctx.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                    .font(.system(size: 15 * baseScale, weight: .medium, design: .rounded))
            }
        case .speed:
            let value = s.useMetricUnits ? sensors.speedKmh : sensors.speedKmh / 1.609_344
            HStack(alignment: .firstTextBaseline, spacing: 3 * baseScale) {
                Text("\(Int(value.rounded()))")
                    .font(.system(size: 22 * baseScale, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text(s.useMetricUnits ? "km/h" : "mph")
                    .font(.system(size: 11 * baseScale, weight: .medium))
                    .opacity(0.8)
            }
        case .battery:
            HStack(spacing: 5 * baseScale) {
                Image(systemName: batterySymbol)
                Text(sensors.batteryLevel >= 0 ? "\(Int(sensors.batteryLevel * 100))%" : "--")
                    .monospacedDigit()
            }
            .font(.system(size: 15 * baseScale, weight: .semibold, design: .rounded))
        case .nowPlaying:
            VStack(alignment: .leading, spacing: 4 * baseScale) {
                HStack(spacing: 6 * baseScale) {
                    Image(systemName: engine.isPlaying ? "play.fill" : "pause.fill")
                        .font(.system(size: 11 * baseScale))
                    Text(engine.current?.title ?? "Nothing playing")
                        .font(.system(size: 14 * baseScale, weight: .semibold))
                        .lineLimit(1)
                }
                if engine.duration > 0 {
                    ProgressView(value: min(max(engine.currentTime / engine.duration, 0), 1))
                        .progressViewStyle(.linear)
                        .tint(s.overlayAccent.color)
                        .frame(width: 180 * baseScale)
                    Text("\(Self.time(engine.currentTime)) / \(Self.time(engine.duration))")
                        .font(.system(size: 11 * baseScale, weight: .medium))
                        .monospacedDigit()
                        .opacity(0.8)
                }
            }
            .frame(maxWidth: 240 * baseScale, alignment: .leading)
        case .weather:
            HStack(spacing: 5 * baseScale) {
                Image(systemName: SensorHub.weatherSymbol(for: sensors.weatherCode))
                    .symbolRenderingMode(.multicolor)
                if let c = sensors.temperatureC {
                    let value = s.useMetricUnits ? c : c * 9 / 5 + 32
                    Text("\(Int(value.rounded()))°")
                } else {
                    Text("--°")
                }
            }
            .font(.system(size: 16 * baseScale, weight: .semibold, design: .rounded))
        }
    }

    private var batterySymbol: String {
        if sensors.isCharging { return "battery.100.bolt" }
        let l = sensors.batteryLevel
        switch l {
        case ..<0: return "battery.50"
        case ..<0.15: return "battery.0"
        case ..<0.4: return "battery.25"
        case ..<0.65: return "battery.50"
        case ..<0.9: return "battery.75"
        default: return "battery.100"
        }
    }

    static func clockString(_ date: Date, use24h: Bool) -> String {
        let f = DateFormatter()
        f.dateFormat = use24h ? "HH:mm" : "h:mm a"
        return f.string(from: date)
    }

    static func time(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}

/// Rounded translucent container for a single overlay widget.
struct OverlayChip<Content: View>: View {
    let config: OverlayWidgetConfig
    let accent: Color
    let baseScale: CGFloat
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .foregroundColor(accent)
            .padding(.horizontal, 10 * baseScale)
            .padding(.vertical, 6 * baseScale)
            .background(
                RoundedRectangle(cornerRadius: 10 * baseScale, style: .continuous)
                    .fill(Color.black.opacity(config.opacity))
            )
            .scaleEffect(config.scale, anchor: anchor)
            .padding(scalePadding)
            .shadow(color: .black.opacity(0.4), radius: 3)
    }

    private var anchor: UnitPoint {
        switch config.position {
        case .topLeading: return .topLeading
        case .top: return .top
        case .topTrailing: return .topTrailing
        case .bottomLeading: return .bottomLeading
        case .bottom: return .bottom
        case .bottomTrailing: return .bottomTrailing
        }
    }

    /// scaleEffect doesn't change layout size; add padding so scaled chips don't overlap.
    private var scalePadding: EdgeInsets {
        let extra = max(0, (config.scale - 1)) * 18 * baseScale
        return config.position.isTop
            ? EdgeInsets(top: 0, leading: 0, bottom: extra, trailing: 0)
            : EdgeInsets(top: extra, leading: 0, bottom: 0, trailing: 0)
    }
}
