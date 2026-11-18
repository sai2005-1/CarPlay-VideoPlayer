import UIKit
import CarPlay
import Combine

/// Builds native CarPlay templates, which adapt to supported vehicle and HomeView displays.
@MainActor
final class CarTemplateController: NSObject {
    private let interfaceController: CPInterfaceController
    private let engine: PlaybackEngine
    private let library: LibraryStore

    private var libraryTemplate: CPListTemplate?
    private var queueTemplate: CPListTemplate?
    private var cancellables = Set<AnyCancellable>()

    init(interfaceController: CPInterfaceController, engine: PlaybackEngine, library: LibraryStore) {
        self.interfaceController = interfaceController
        self.engine = engine
        self.library = library
        super.init()
    }

    func installRootTemplate() {
        let library = CPListTemplate(title: "Library", sections: librarySections())
        library.emptyViewTitleVariants = ["No CarPlay videos"]
        library.emptyViewSubtitleVariants = ["Add a video file or supported stream in the iPhone app."]
        library.leadingNavigationBarButtons = [
            CPBarButton(title: "Now Playing") { [weak self] _ in self?.showNowPlaying() }
        ]

        let queue = CPListTemplate(title: "Up Next", sections: queueSections())
        queue.emptyViewTitleVariants = ["Queue is empty"]
        queue.emptyViewSubtitleVariants = ["Add videos to the queue from your iPhone."]
        queue.leadingNavigationBarButtons = [
            CPBarButton(title: "Now Playing") { [weak self] _ in self?.showNowPlaying() }
        ]

        libraryTemplate = library
        queueTemplate = queue
        let tabs = CPTabBarTemplate(templates: [library, queue])
        interfaceController.setRootTemplate(tabs, animated: false, completion: nil)

        self.library.$items
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshLibrary() }
            .store(in: &cancellables)
        engine.$current
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshLibrary() }
            .store(in: &cancellables)
        engine.$queue
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshQueue() }
            .store(in: &cancellables)
    }

    private func refreshLibrary() {
        libraryTemplate?.updateSections(librarySections())
    }

    private func refreshQueue() {
        queueTemplate?.updateSections(queueSections())
    }

    private func librarySections() -> [CPListSection] {
        var sections: [CPListSection] = []
        let recent = Array(library.recent.filter { $0.kind != .youtube }.prefix(8))
        if !recent.isEmpty {
            sections.append(CPListSection(
                items: recent.map(listItem(for:)),
                header: "Continue Watching",
                sectionIndexTitle: nil
            ))
        }
        for kind in [MediaKind.localFile, .remoteURL] {
            let items = library.items(of: kind)
            if !items.isEmpty {
                sections.append(CPListSection(
                    items: Array(items.prefix(50)).map(listItem(for:)),
                    header: kind.label,
                    sectionIndexTitle: nil
                ))
            }
        }
        return trim(sections, to: CPListTemplate.maximumItemCount)
    }

    private func queueSections() -> [CPListSection] {
        let items = engine.queue
            .filter { $0.kind != .youtube }
            .map(listItem(for:))
        guard !items.isEmpty else { return [] }
        return [CPListSection(
            items: Array(items.prefix(CPListTemplate.maximumItemCount)),
            header: "Up Next",
            sectionIndexTitle: nil
        )]
    }

    private func listItem(for media: MediaItem) -> CPListItem {
        var detail = media.kind.label
        if media.duration > 0 {
            let remaining = max(0, media.duration - media.resumePosition)
            detail += media.resumePosition > 5
                ? " · \(OverlayLayerView.time(remaining)) left"
                : " · \(OverlayLayerView.time(media.duration))"
        }
        let item = CPListItem(text: media.title, detailText: detail, image: Self.symbol(media.kind.symbol))
        if media.progress > 0.01 {
            item.playbackProgress = CGFloat(media.progress)
        }
        item.handler = { [weak self] _, completion in
            guard let self else {
                completion()
                return
            }
            self.engine.play(media)
            completion()
            self.showNowPlaying()
        }
        return item
    }

    private func showNowPlaying() {
        interfaceController.pushTemplate(CPNowPlayingTemplate.shared, animated: true, completion: nil)
    }

    private func trim(_ sections: [CPListSection], to limit: Int) -> [CPListSection] {
        var remaining = limit
        var result: [CPListSection] = []
        for section in sections where remaining > 0 {
            let items = section.items.compactMap { $0 as? CPListItem }
            let kept = Array(items.prefix(remaining))
            remaining -= kept.count
            if !kept.isEmpty {
                result.append(CPListSection(items: kept, header: section.header, sectionIndexTitle: nil))
            }
        }
        return result
    }

    private static func symbol(_ name: String) -> UIImage {
        let config = UIImage.SymbolConfiguration(pointSize: 22, weight: .semibold)
        return UIImage(systemName: name, withConfiguration: config) ?? UIImage()
    }
}
