import SwiftUI
import AVKit
import UniformTypeIdentifiers
import UIKit

final class AppRouter: ObservableObject {
    static let shared = AppRouter()
    enum Tab: Hashable { case home, library, youtube, player, settings }
    @Published var tab: Tab = .home
}

struct RootView: View {
    @ObservedObject private var router = AppRouter.shared
    @ObservedObject private var engine = PlaybackEngine.shared

    var body: some View {
        TabView(selection: $router.tab) {
            HomeView()
                .tabItem { Label("Home", systemImage: "house.fill") }
                .tag(AppRouter.Tab.home)

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

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
                .tag(AppRouter.Tab.settings)
        }
        .tint(AppPalette.blue)
        .toolbarBackground(.visible, for: .tabBar)
    }

    @ViewBuilder
    private var miniPlayer: some View {
        if engine.current != nil {
            MiniPlayerBar()
                .onTapGesture { router.tab = .player }
        }
    }
}

struct HomeView: View {
    @ObservedObject private var router = AppRouter.shared
    @ObservedObject private var library = LibraryStore.shared
    @ObservedObject private var engine = PlaybackEngine.shared

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HStack(spacing: 14) {
                        BrandMark(size: 58)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("CarPlay Video")
                                .font(.title2.weight(.bold))
                            Text("Your video library, ready when parked")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }

                    if let current = engine.current {
                        currentCard(current)
                    } else {
                        welcomeCard
                    }

                    HStack(spacing: 12) {
                        quickAction(
                            title: "Add video",
                            subtitle: "Files or a link",
                            symbol: "plus",
                            tint: AppPalette.blue
                        ) {
                            router.tab = .youtube
                        }
                        quickAction(
                            title: "My library",
                            subtitle: "\(library.items.count) videos",
                            symbol: "film.stack",
                            tint: AppPalette.ocean
                        ) {
                            router.tab = .library
                        }
                    }

                    if !library.recent.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Pick up where you left off")
                                    .font(.headline)
                                Spacer()
                                Button("See all") { router.tab = .library }
                                    .font(.subheadline.weight(.semibold))
                            }
                            ForEach(library.recent.prefix(3)) { item in
                                Button {
                                    engine.play(item)
                                    router.tab = .player
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: item.kind.symbol)
                                            .font(.headline)
                                            .foregroundStyle(AppPalette.blue)
                                            .frame(width: 42, height: 42)
                                            .background(AppPalette.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 13))
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(item.title)
                                                .font(.subheadline.weight(.semibold))
                                                .lineLimit(1)
                                            Text(item.kind.label)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        Image(systemName: "play.circle.fill")
                                            .font(.title2)
                                            .foregroundStyle(AppPalette.blue)
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(18)
                        .appGlassCard()
                    }

                    if engine.carConnected {
                        Label("Connected to CarPlay", systemImage: "car.fill")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(AppPalette.ocean)
                            .padding(.horizontal, 4)
                    }
                }
                .padding(20)
            }
            .background(AppPalette.canvas.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private var welcomeCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Ready when you are", systemImage: "sparkles")
                .font(.headline)
                .foregroundStyle(.white.opacity(0.8))
            Text("Bring your favorite videos together.")
                .font(.system(.title2, design: .rounded, weight: .bold))
                .foregroundStyle(.white)
            Text("Choose a video from Files or paste a YouTube link to start your library.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.78))
            Button {
                router.tab = .youtube
            } label: {
                Label("Add your first video", systemImage: "plus")
                    .font(.subheadline.weight(.bold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 11)
                    .foregroundStyle(AppPalette.ink)
                    .background(.white, in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(22)
        .background(AppPalette.gradient, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: AppPalette.ocean.opacity(0.2), radius: 20, y: 10)
    }

    private func currentCard(_ item: MediaItem) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                let onCarPlay = engine.carConnected && engine.backend != .youtube
                Label(onCarPlay ? "Playing on CarPlay" : "Now playing", systemImage: onCarPlay ? "car.fill" : "play.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white.opacity(0.78))
                Spacer()
                Button {
                    engine.togglePlayPause()
                } label: {
                    Image(systemName: engine.isPlaying ? "pause.fill" : "play.fill")
                        .font(.headline)
                        .foregroundStyle(AppPalette.ink)
                        .frame(width: 44, height: 44)
                        .background(.white, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(engine.isPlaying ? "Pause" : "Play")
            }
            Text(item.title)
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)
                .lineLimit(2)
            ProgressView(value: engine.duration > 0 ? min(engine.currentTime / engine.duration, 1) : 0)
                .tint(AppPalette.cyan)
            HStack {
                Text(OverlayLayerView.time(engine.currentTime))
                Spacer()
                Text(OverlayLayerView.time(engine.duration))
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.white.opacity(0.75))
            Button {
                router.tab = .player
            } label: {
                Text("Open player")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
        }
        .padding(20)
        .background(AppPalette.gradient, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: AppPalette.ocean.opacity(0.2), radius: 20, y: 10)
    }

    private func quickAction(
        title: String,
        subtitle: String,
        symbol: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: symbol)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(tint)
                    .frame(width: 42, height: 42)
                    .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
                Text(title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .appGlassCard(cornerRadius: 22)
        }
        .buttonStyle(.plain)
    }
}

struct MiniPlayerBar: View {
    @ObservedObject private var engine = PlaybackEngine.shared
    @ObservedObject private var router = AppRouter.shared

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: engine.current?.kind.symbol ?? "film")
                .font(.title3)
                .frame(width: 36, height: 36)
                .background(Color.accentColor.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
            Button {
                router.tab = .player
            } label: {
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
                    .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
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
        .appGlassCard(cornerRadius: 20)
        .overlay(alignment: .top) {
            GeometryReader { geo in
                Rectangle()
                    .fill(AppPalette.cyan)
                    .frame(width: engine.duration > 0 ? geo.size.width * min(1, engine.currentTime / engine.duration) : 0, height: 2)
            }
            .frame(height: 2)
        }
        .padding(.horizontal, 10)
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
    @State private var searchText = ""
    @State private var importError: String?

    var body: some View {
        NavigationStack {
            List {
                if !recentItems.isEmpty {
                    Section("Continue Watching") {
                        ForEach(recentItems) { item in
                            mediaRow(item)
                        }
                    }
                }
                ForEach([MediaKind.youtube, .localFile, .remoteURL], id: \.self) { kind in
                    let items = filteredItems(of: kind)
                    if !items.isEmpty {
                        Section(kind.label) {
                            ForEach(items) { item in
                                mediaRow(item)
                            }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppPalette.canvas)
            .searchable(text: $searchText, prompt: "Search your videos")
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
                    do {
                        _ = try library.importFile(at: url)
                    } catch {
                        importError = error.localizedDescription
                    }
                }
            }
            .alert("Couldn't import video", isPresented: Binding(
                get: { importError != nil },
                set: { if !$0 { importError = nil } }
            )) {
                Button("OK", role: .cancel) { importError = nil }
            } message: {
                Text(importError ?? "Try choosing the video again.")
            }
        }
    }

    private var recentItems: [MediaItem] {
        let items = library.recent
        let filtered = searchText.isEmpty
            ? items
            : items.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
        return Array(filtered.prefix(8))
    }

    private func filteredItems(of kind: MediaKind) -> [MediaItem] {
        let items = library.items(of: kind)
        guard !searchText.isEmpty else { return items }
        return items.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
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
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    BrandMark(size: 66)
                    Text("Add a video")
                        .font(.largeTitle.weight(.bold))
                    Text("Paste a YouTube link or enter a video ID. You can also add a video file from your Library.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 10) {
                        TextField("youtube.com/watch?v=…", text: $input)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                            .submitLabel(.go)
                            .onSubmit(play)
                        Button {
                            if let text = UIPasteboard.general.string {
                                input = text.trimmingCharacters(in: .whitespacesAndNewlines)
                                errorMessage = nil
                            }
                        } label: {
                            Image(systemName: "doc.on.clipboard")
                                .font(.title3)
                        }
                        .accessibilityLabel("Paste link")
                    }
                    .padding(14)
                    .appGlassCard(cornerRadius: 18)

                    Button(action: play) {
                        Label("Play YouTube video", systemImage: "play.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppPalette.blue)
                    .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.circle.fill")
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }

                    if engine.backend == .youtube {
                        if engine.carConnected {
                            Label("CarPlay is connected. YouTube video stays in the iPhone app.", systemImage: "car.fill")
                                .font(.subheadline.weight(.medium))
                                .padding(16)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .appGlassCard(cornerRadius: 20)
                        } else {
                            YouTubeSurface(backend: engine.youtube, carConnected: false)
                                .frame(height: 220)
                                .clipShape(RoundedRectangle(cornerRadius: 20))
                                .appGlassCard(cornerRadius: 20)
                        }
                    }

                    Label(
                        "Videos playing in the YouTube app can't be detected automatically. Copy a link there, then paste it here to play it in this app.",
                        systemImage: "info.circle"
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
                .padding(20)
            }
            .background(AppPalette.canvas.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
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
                        if engine.carConnected {
                            Label("CarPlay is connected. YouTube video stays in the iPhone app.", systemImage: "car.fill")
                                .font(.subheadline)
                                .padding()
                        } else {
                            YouTubeSurface(backend: engine.youtube, carConnected: false)
                                .frame(maxHeight: 300)
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                                .padding()
                        }
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
        Form {
            Section("iPhone preview") {
                OverlayLayerView(settingsStore: settings, engine: engine, sensors: sensors, baseScale: 0.75)
                    .frame(height: 220)
                    .background(AppPalette.ink)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                Text("CarPlay uses native system templates; these overlays appear only in this iPhone preview.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
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
        .scrollContentBackground(.hidden)
        .background(AppPalette.canvas)
        .navigationTitle("Overlay Preview")
        .onAppear(perform: updateSensorMonitoring)
        .onChange(of: settings.settings.overlays) { _ in
            updateSensorMonitoring()
        }
        .onDisappear {
            sensors.stop()
        }
    }

    private func updateSensorMonitoring() {
        let needsLocation = settings.settings.overlays.contains {
            $0.enabled && ($0.kind == .speed || $0.kind == .weather)
        }
        if needsLocation {
            sensors.start()
        } else {
            sensors.stop()
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
                    Label(
                        "CarPlay adapts the library and playback controls to each supported display. Video availability and driving restrictions are managed by iOS and the vehicle.",
                        systemImage: "car.fill"
                    )
                    .font(.footnote)
                    Toggle("Metric units", isOn: $settings.settings.useMetricUnits)
                }
                Section("Display") {
                    Toggle("24-hour clock", isOn: $settings.settings.use24HourClock)
                    Toggle("Show overlays", isOn: $settings.settings.showOverlays)
                }
                Section("Widgets") {
                    NavigationLink("Preview overlay widgets") {
                        WidgetEditorView()
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppPalette.canvas)
            .navigationTitle("Settings")
        }
    }
}
