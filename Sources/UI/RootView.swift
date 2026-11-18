import SwiftUI
import AVKit
import UniformTypeIdentifiers
import UIKit

final class AppRouter: ObservableObject {
    static let shared = AppRouter()
    enum Tab: Hashable { case library, youtube, player, widgets, settings }
    @Published var tab: Tab = .library
}

struct RootView: View {
    @ObservedObject private var router = AppRouter.shared
    @ObservedObject private var engine = PlaybackEngine.shared

    var body: some View {
        TabView(selection: $router.tab) {
            LibraryView()
                .safeAreaInset(edge: .bottom) { miniPlayer }
                .tabItem { Label("Library", systemImage: "film.stack") }
                .tag(AppRouter.Tab.library)

            YouTubeBrowserView()
                .safeAreaInset(edge: .bottom) { miniPlayer }
                .tabItem { Label("YouTube", systemImage: "play.rectangle.fill") }
                .tag(AppRouter.Tab.youtube)

            NowPlayingView()
                .tabItem { Label("Now Playing", systemImage: "play.circle.fill") }
                .tag(AppRouter.Tab.player)

            WidgetEditorView()
                .tabItem { Label("Widgets", systemImage: "square.grid.2x2.fill") }
                .tag(AppRouter.Tab.widgets)

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
                .tag(AppRouter.Tab.settings)
        }
    }

    @ViewBuilder
    private var miniPlayer: some View {
        if engine.current != nil {
            MiniPlayerBar()
                .onTapGesture { router.tab = .player }
        }
    }
}

struct MiniPlayerBar: View {
    @ObservedObject private var engine = PlaybackEngine.shared

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: engine.current?.kind.symbol ?? "film")
                .font(.title3)
                .frame(width: 36, height: 36)
                .background(Color.accentColor.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                Text(engine.current?.title ?? "")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                HStack(spacing: 4) {
                    if engine.carConnected {
                        Image(systemName: "car.fill")
                        Text("On CarPlay")
                    } else {
                        Text(engine.current?.kind.label ?? "")
                    }
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
            Spacer()
            Button { engine.togglePlayPause() } label: {
                Image(systemName: engine.isPlaying ? "pause.fill" : "play.fill").font(.title2)
            }
            Button { engine.next() } label: {
                Image(systemName: "forward.end.fill").font(.title3)
            }
            .disabled(engine.queue.isEmpty)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.regularMaterial)
        .overlay(alignment: .top) {
            GeometryReader { geo in
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(width: engine.duration > 0 ? geo.size.width * min(1, engine.currentTime / engine.duration) : 0, height: 2)
            }
            .frame(height: 2)
        }
    }
}

/// AirPlay route picker.
struct RoutePicker: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let v = AVRoutePickerView()
        v.prioritizesVideoDevices = true
        return v
    }
    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}

struct LibraryView: View {
    @ObservedObject private var library = LibraryStore.shared
    @ObservedObject private var engine = PlaybackEngine.shared
    @State private var showingImporter = false

    var body: some View {
        NavigationStack {
            List {
                if !library.recent.isEmpty {
                    Section("Continue Watching") {
                        ForEach(library.recent) { item in
                            mediaRow(item)
                        }
                    }
                }
                ForEach([MediaKind.youtube, .localFile, .remoteURL], id: \.self) { kind in
                    let items = library.items(of: kind)
                    if !items.isEmpty {
                        Section(kind.label) {
                            ForEach(items) { item in
                                mediaRow(item)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Library")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showingImporter = true } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingImporter) {
                VideoDocumentPicker { url in
                    _ = try? library.importFile(at: url)
                }
            }
        }
    }

    @ViewBuilder
    private func mediaRow(_ item: MediaItem) -> some View {
        Button {
            engine.play(item)
        } label: {
            HStack {
                Image(systemName: item.kind.symbol)
                    .frame(width: 28)
                VStack(alignment: .leading) {
                    Text(item.title).lineLimit(1)
                    Text(item.kind.label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if item.progress > 0 {
                    Text("\(Int(item.progress * 100))%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .swipeActions {
            Button(role: .destructive) {
                library.delete(item)
            } label: {
                Label("Delete", systemImage: "trash")
            }
            Button {
                engine.playNext(item)
            } label: {
                Label("Play Next", systemImage: "text.insert")
            }
        }
    }
}

struct VideoDocumentPicker: UIViewControllerRepresentable {
    let completion: (URL) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let types: [UTType] = [.movie, .mpeg4Movie, .quickTimeMovie]
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: true)
        picker.allowsMultipleSelection = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(completion: completion) }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let completion: (URL) -> Void
        init(completion: @escaping (URL) -> Void) { self.completion = completion }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            completion(url)
        }
    }
}

struct YouTubeBrowserView: View {
    @ObservedObject private var engine = PlaybackEngine.shared
    @State private var input = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                TextField("YouTube URL or video ID", text: $input)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding()
                    .background(.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))

                Button("Play") { play() }
                    .buttonStyle(.borderedProminent)
                    .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .font(.caption)
                }

                if engine.backend == .youtube {
                    YouTubeSurface(backend: engine.youtube, carConnected: engine.carConnected)
                        .frame(height: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                Spacer()
            }
            .padding()
            .navigationTitle("YouTube")
        }
    }

    private func play() {
        guard let item = MediaFactory.item(from: input) else {
            errorMessage = "Enter a valid YouTube URL or video ID."
            return
        }
        errorMessage = nil
        engine.play(item)
    }
}

struct NowPlayingView: View {
    @ObservedObject private var engine = PlaybackEngine.shared

    var body: some View {
        NavigationStack {
            VStack {
                if engine.current == nil {
                    Spacer()
                    Image(systemName: "play.rectangle")
                        .font(.system(size: 64))
                        .foregroundStyle(.secondary)
                    Text("Nothing playing")
                        .font(.title3)
                    Spacer()
                } else {
                    if engine.backend == .youtube {
                        YouTubeSurface(backend: engine.youtube, carConnected: engine.carConnected)
                            .frame(maxHeight: 300)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .padding()
                    } else {
                        PlayerSurface(player: engine.player, fill: false)
                            .frame(maxHeight: 300)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .padding()
                    }

                    Text(engine.current?.title ?? "")
                        .font(.headline)
                        .lineLimit(2)
                        .padding(.horizontal)

                    Slider(
                        value: Binding(
                            get: { engine.currentTime },
                            set: { engine.seek(to: $0) }
                        ),
                        in: 0...max(engine.duration, 1)
                    )
                    .padding(.horizontal)

                    HStack {
                        Text(OverlayLayerView.time(engine.currentTime))
                        Spacer()
                        Text(OverlayLayerView.time(engine.duration))
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)

                    HStack(spacing: 36) {
                        Button { engine.previous() } label: {
                            Image(systemName: "backward.end.fill")
                        }
                        Button { engine.togglePlayPause() } label: {
                            Image(systemName: engine.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                .font(.system(size: 52))
                        }
                        Button { engine.next() } label: {
                            Image(systemName: "forward.end.fill")
                        }
                    }
                    .padding()

                    HStack {
                        Text("Speed")
                        Picker("Speed", selection: Binding(
                            get: { engine.playbackRate },
                            set: { engine.setRate($0) }
                        )) {
                            ForEach([Float(0.75), 1.0, 1.25, 1.5, 2.0], id: \.self) { rate in
                                Text("\(rate, specifier: "%.2g")x").tag(rate)
                            }
                        }
                        .pickerStyle(.menu)
                        RoutePicker().frame(width: 44, height: 44)
                    }
                    .padding(.horizontal)

                    Spacer()
                }
            }
            .navigationTitle("Now Playing")
        }
    }
}

struct WidgetEditorView: View {
    @ObservedObject private var settings = SettingsStore.shared
    @ObservedObject private var engine = PlaybackEngine.shared
    @ObservedObject private var sensors = SensorHub.shared

    var body: some View {
        NavigationStack {
            Form {
                Section("Preview") {
                    OverlayLayerView(settingsStore: settings, engine: engine, sensors: sensors, baseScale: 0.75)
                        .frame(height: 220)
                        .background(.black)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                Section("Widgets") {
                    ForEach(OverlayWidgetKind.allCases) { kind in
                        Toggle(kind.title, isOn: settings.binding(for: kind).enabled)
                    }
                }
                Section("Style") {
                    Picker("Accent", selection: $settings.settings.overlayAccent) {
                        ForEach(OverlayAccent.allCases) { accent in
                            Text(accent.rawValue.capitalized).tag(accent)
                        }
                    }
                    Toggle("Show overlays", isOn: $settings.settings.showOverlays)
                    Button("Reset overlays") {
                        settings.resetOverlays()
                    }
                }
            }
            .navigationTitle("Widgets")
        }
    }
}

struct SettingsView: View {
    @ObservedObject private var settings = SettingsStore.shared

    var body: some View {
        NavigationStack {
            Form {
                Section("Playback") {
                    Toggle("Resume when CarPlay connects", isOn: $settings.settings.resumeOnConnect)
                    Toggle("Auto-play on CarPlay connection", isOn: $settings.settings.autoPlayOnConnect)
                    Toggle("Auto-advance queue", isOn: $settings.settings.autoAdvance)
                    Picker("Skip interval", selection: $settings.settings.skipInterval) {
                        Text("10 seconds").tag(10.0)
                        Text("15 seconds").tag(15.0)
                        Text("30 seconds").tag(30.0)
                        Text("60 seconds").tag(60.0)
                    }
                }
                Section("CarPlay") {
                    Toggle("Pause video while moving", isOn: $settings.settings.speedLockEnabled)
                    Stepper("Speed threshold: \(Int(settings.settings.speedThresholdKmh)) km/h",
                            value: $settings.settings.speedThresholdKmh, in: 3...30)
                    Toggle("Fill screen", isOn: $settings.settings.fillCarScreen)
                    Toggle("Metric units", isOn: $settings.settings.useMetricUnits)
                }
                Section("Display") {
                    Toggle("24-hour clock", isOn: $settings.settings.use24HourClock)
                    Toggle("Show overlays", isOn: $settings.settings.showOverlays)
                }
            }
            .navigationTitle("Settings")
        }
    }
}
