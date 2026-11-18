import WidgetKit
import SwiftUI
import AppIntents

struct WidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

struct ContinueTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> WidgetEntry {
        WidgetEntry(date: Date(), snapshot: .init())
    }

    func getSnapshot(in context: Context, completion: @escaping (WidgetEntry) -> Void) {
        completion(WidgetEntry(date: Date(), snapshot: WidgetSnapshot.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WidgetEntry>) -> Void) {
        let entry = WidgetEntry(date: Date(), snapshot: WidgetSnapshot.load())
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(15 * 60))))
    }
}

struct ContinueWidgetView: View {
    let snapshot: WidgetSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(snapshot.nowPlayingTitle ?? "Nothing Playing")
                .font(.headline)
                .lineLimit(2)
            if let kind = snapshot.nowPlayingKind {
                Label(kind.label, systemImage: kind.symbol)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: snapshot.progress)
            if !snapshot.recent.isEmpty {
                Divider()
                ForEach(snapshot.recent.prefix(3)) { entry in
                    HStack {
                        Text(entry.title)
                            .lineLimit(1)
                        Spacer()
                        Text("\(Int(entry.progress * 100))%")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding()
        .background(.ultraThickMaterial)
    }
}

struct ContinueWatchingWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: AppConstants.widgetKindContinue, provider: ContinueTimelineProvider()) { entry in
            ContinueWidgetView(snapshot: entry.snapshot)
        }
        .configurationDisplayName("Continue Watching")
        .description("Resume your recent videos.")
    }
}

struct ControlsTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> WidgetEntry {
        WidgetEntry(date: Date(), snapshot: .init())
    }

    func getSnapshot(in context: Context, completion: @escaping (WidgetEntry) -> Void) {
        completion(WidgetEntry(date: Date(), snapshot: WidgetSnapshot.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WidgetEntry>) -> Void) {
        let entry = WidgetEntry(date: Date(), snapshot: WidgetSnapshot.load())
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(60))))
    }
}

struct ControlsWidgetView: View {
    let snapshot: WidgetSnapshot

    var body: some View {
        HStack {
            if #available(iOS 17.0, *) {
                Button(intent: TogglePlaybackIntent()) {
                    Image(systemName: snapshot.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title)
                }
                .buttonStyle(.bordered)
                Button(intent: NextVideoIntent()) {
                    Image(systemName: "forward.end.fill")
                        .font(.title)
                }
                .buttonStyle(.bordered)
            } else {
                Link(destination: URL(string: "\(AppConstants.urlScheme)://toggle")!) {
                    Image(systemName: snapshot.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title)
                }
                Link(destination: URL(string: "\(AppConstants.urlScheme)://play")!) {
                    Image(systemName: "forward.end.fill")
                        .font(.title)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThickMaterial)
    }
}

struct PlaybackControlsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: AppConstants.widgetKindControls, provider: ControlsTimelineProvider()) { entry in
            ControlsWidgetView(snapshot: entry.snapshot)
        }
        .configurationDisplayName("Playback Controls")
        .description("Play, pause, and skip from your Home Screen.")
    }
}

@main
struct CarPlayVideoWidgetBundle: WidgetBundle {
    var body: some Widget {
        ContinueWatchingWidget()
        PlaybackControlsWidget()
    }
}
