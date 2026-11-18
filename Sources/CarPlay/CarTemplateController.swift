import UIKit
import CarPlay
import Combine

/// Builds the CarPlay templates: on-screen playback buttons (CPMapTemplate) and the
/// Library / Queue lists (CPListTemplate).
final class CarTemplateController: NSObject {
    private let interfaceController: CPInterfaceController
    private let engine: PlaybackEngine
    private let library: LibraryStore
    private let settings: SettingsStore

    private var mapTemplate: CPMapTemplate?
    private var playButton: CPMapButton?
    private var fitButton: CPBarButton?
    private var cancellables = Set<AnyCancellable>()
    private var thumbnailCache: [String: UIImage] = [:]

    init(interfaceController: CPInterfaceController, engine: PlaybackEngine,
         library: LibraryStore, settings: SettingsStore) {
        self.interfaceController = interfaceController
        self.engine = engine
        self.library = library
        self.settings = settings
        super.init()
    }

    // MARK: Root

    func installRootTemplate() {
        let map = CPMapTemplate()
        map.automaticallyHidesNavigationBar = false
        map.hidesButtonsWithNavigationBar = false

        let libraryButton = CPBarButton(title: "Library") { [weak self] _ in self?.showLibrary() }
        let queueButton = CPBarButton(title: "Queue") { [weak self] _ in self?.showQueue() }
        let fit = CPBarButton(title: settings.settings.fillCarScreen ? "Fit" : "Fill") { [weak self] _ in
            self?.toggleFill()
        }
        fitButton = fit
        let widgets = CPBarButton(image: Self.symbol("square.grid.2x2")) { [weak self] _ in
            self?.settings.settings.showOverlays.toggle()
        }
        map.leadingNavigationBarButtons = [libraryButton, queueButton]
        map.trailingNavigationBarButtons = [fit, widgets]

        let back = CPMapButton { [weak self] _ in self?.engine.skipBackward() }
        back.image = Self.symbol("gobackward")
        let play = CPMapButton { [weak self] _ in self?.engine.togglePlayPause() }
        play.image = Self.symbol(engine.isPlaying ? "pause.fill" : "play.fill")
        let forward = CPMapButton { [weak self] _ in self?.engine.skipForward() }
        forward.image = Self.symbol("goforward")
        let next = CPMapButton { [weak self] _ in self?.engine.next() }
        next.image = Self.symbol("forward.end.fill")
        playButton = play
        map.mapButtons = [back, play, forward, next]

        mapTemplate = map
        interfaceController.setRootTemplate(map, animated: false, completion: nil)

        engine.$isPlaying
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] playing in
                self?.playButton?.image = Self.symbol(playing ? "pause.fill" : "play.fill")
            }
            .store(in: &cancellables)

        settings.$settings
            .map(\.fillCarScreen)
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] fill in self?.fitButton?.title = fill ? "Fit" : "Fill" }
            .store(in: &cancellables)
    }

    private func toggleFill() {
        settings.settings.fillCarScreen.toggle()
    }

    // MARK: Library

    private func showLibrary() {
        let limit = CPListTemplate.maximumItemCount
        var sections: [CPListSection] = []

        let recent = Array(library.recent.prefix(8))
        if !recent.isEmpty {
            sections.append(CPListSection(items: recent.map(listItem(for:)), header: "Continue Watching", sectionIndexTitle: nil))
        }
        for kind in [MediaKind.youtube, .localFile, .remoteURL] {
            let items = library.items(of: kind)
            if !items.isEmpty {
                sections.append(CPListSection(items: items.prefix(50).map(listItem(for:)), header: kind.label, sectionIndexTitle: nil))
            }
        }
        sections = trim(sections, to: limit)

        let template = CPListTemplate(title: "Library", sections: sections)
        template.emptyViewTitleVariants = ["No videos yet"]
        template.emptyViewSubtitleVariants = ["Add videos or YouTube links in the app on your iPhone."]
        interfaceController.pushTemplate(template, animated: true, completion: nil)
    }

    private func showQueue() {
        var items: [CPListItem] = []
        if let cur = engine.current {
            let item = listItem(for: cur)
            item.isPlaying = true
            items.append(item)
        }
        items.append(contentsOf: engine.queue.map(listItem(for:)))
        let section = CPListSection(items: Array(items.prefix(CPListTemplate.maximumItemCount)), header: "Up Next", sectionIndexTitle: nil)
        let template = CPListTemplate(title: "Queue", sections: items.isEmpty ? [] : [section])
        template.emptyViewTitleVariants = ["Queue is empty"]
        template.emptyViewSubtitleVariants = ["Use “Play Next” or “Add to Queue” on your iPhone."]
        interfaceController.pushTemplate(template, animated: true, completion: nil)
    }

    private func listItem(for media: MediaItem) -> CPListItem {
        var detail = media.kind.label
        if media.duration > 0 {
            let remaining = max(0, media.duration - media.resumePosition)
            detail += media.resumePosition > 5
                ? " · \(OverlayLayerView.time(remaining)) left"
                : " · \(OverlayLayerView.time(media.duration))"
        }
        let image = thumbnailCache[media.reference] ?? Self.symbol(media.kind.symbol)
        let item = CPListItem(text: media.title, detailText: detail, image: image)
        if media.progress > 0.01 {
            item.playbackProgress = CGFloat(media.progress)
        }
        item.handler = { [weak self] _, completion in
            self?.engine.play(media)
            self?.interfaceController.popToRootTemplate(animated: true, completion: nil)
            completion()
        }
        loadThumbnail(for: media, into: item)
        return item
    }

    private func loadThumbnail(for media: MediaItem, into item: CPListItem) {
        guard thumbnailCache[media.reference] == nil, let url = media.youtubeThumbnailURL else { return }
        let key = media.reference
        URLSession.shared.dataTask(with: url) { [weak self, weak item] data, _, _ in
            guard let data = data, let image = UIImage(data: data) else { return }
            DispatchQueue.main.async {
                self?.thumbnailCache[key] = image
                item?.setImage(image)
            }
        }.resume()
    }

    private func trim(_ sections: [CPListSection], to limit: Int) -> [CPListSection] {
        var remaining = limit
        var result: [CPListSection] = []
        for section in sections where remaining > 0 {
            let items = section.items.compactMap { $0 as? CPListItem }
            let kept = Array(items.prefix(remaining))
            remaining -= kept.count
            result.append(CPListSection(items: kept, header: section.header, sectionIndexTitle: nil))
        }
        return result
    }

    static func symbol(_ name: String) -> UIImage {
        let config = UIImage.SymbolConfiguration(pointSize: 22, weight: .semibold)
        return UIImage(systemName: name, withConfiguration: config) ?? UIImage()
    }
}
