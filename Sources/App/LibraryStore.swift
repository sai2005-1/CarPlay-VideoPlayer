import Foundation
import Combine
import WidgetKit

/// Persists the user's video library and keeps the widget snapshot up to date.
final class LibraryStore: ObservableObject {
    static let shared = LibraryStore()

    @Published private(set) var items: [MediaItem] = []

    private let fileURL: URL
    private var saveWorkItem: DispatchWorkItem?

    init(fileURL: URL = AppConstants.sharedContainer.appendingPathComponent("library.json")) {
        self.fileURL = fileURL
        load()
        importLooseFilesFromDocuments()
    }

    // MARK: Folders

    static var videosDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("Videos", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    static func localURL(for item: MediaItem) -> URL? {
        guard item.kind == .localFile else { return nil }
        return videosDirectory.appendingPathComponent(item.reference)
    }

    static let videoExtensions: Set<String> = ["mp4", "m4v", "mov", "3gp", "mkv", "avi", "webm", "ts", "m3u8"]

    // MARK: Queries

    var recent: [MediaItem] {
        items.filter { $0.lastPlayedAt != nil }
            .sorted { ($0.lastPlayedAt ?? .distantPast) > ($1.lastPlayedAt ?? .distantPast) }
    }

    var lastPlayed: MediaItem? { recent.first }

    func item(withID id: UUID) -> MediaItem? { items.first { $0.id == id } }

    func items(of kind: MediaKind) -> [MediaItem] {
        items.filter { $0.kind == kind }.sorted { $0.addedAt > $1.addedAt }
    }

    // MARK: Mutations

    @discardableResult
    func add(_ item: MediaItem) -> MediaItem {
        // De-duplicate by kind + reference.
        if let existing = items.first(where: { $0.kind == item.kind && $0.reference == item.reference }) {
            return existing
        }
        items.insert(item, at: 0)
        scheduleSave()
        return item
    }

    func update(_ item: MediaItem) {
        guard let i = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[i] = item
        scheduleSave()
    }

    func updateProgress(id: UUID, position: Double, duration: Double) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        // Near the end -> reset so the next play starts from the beginning.
        let finished = duration > 0 && position > duration - 5
        items[i].resumePosition = finished ? 0 : max(0, position)
        if duration > 0 { items[i].duration = duration }
        scheduleSave()
    }

    func markPlayed(id: UUID) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        items[i].lastPlayedAt = Date()
        scheduleSave()
    }

    func rename(id: UUID, to title: String) {
        guard let i = items.firstIndex(where: { $0.id == id }), !title.isEmpty else { return }
        items[i].title = title
        scheduleSave()
    }

    func delete(_ item: MediaItem) {
        if let url = Self.localURL(for: item) {
            try? FileManager.default.removeItem(at: url)
        }
        items.removeAll { $0.id == item.id }
        scheduleSave()
    }

    /// Copies a picked file into the app's Videos folder and adds it to the library.
    @discardableResult
    func importFile(at source: URL, title: String? = nil) throws -> MediaItem {
        let accessing = source.startAccessingSecurityScopedResource()
        defer { if accessing { source.stopAccessingSecurityScopedResource() } }

        let ext = source.pathExtension.isEmpty ? "mp4" : source.pathExtension
        let base = source.deletingPathExtension().lastPathComponent
        var name = "\(base).\(ext)"
        var dest = Self.videosDirectory.appendingPathComponent(name)
        var n = 1
        while FileManager.default.fileExists(atPath: dest.path) {
            name = "\(base)-\(n).\(ext)"
            dest = Self.videosDirectory.appendingPathComponent(name)
            n += 1
        }
        try FileManager.default.copyItem(at: source, to: dest)
        let item = MediaItem(title: title ?? base, kind: .localFile, reference: name)
        return add(item)
    }

    /// Picks up videos dropped into Documents (via Files app / Finder file sharing).
    func importLooseFilesFromDocuments() {
        let fm = FileManager.default
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        if let loose = try? fm.contentsOfDirectory(at: docs, includingPropertiesForKeys: nil) {
            for url in loose where Self.videoExtensions.contains(url.pathExtension.lowercased()) {
                let dest = Self.videosDirectory.appendingPathComponent(url.lastPathComponent)
                if !fm.fileExists(atPath: dest.path) {
                    try? fm.moveItem(at: url, to: dest)
                }
            }
        }
        // Register any file in Videos that isn't in the library yet.
        if let files = try? fm.contentsOfDirectory(at: Self.videosDirectory, includingPropertiesForKeys: nil) {
            for url in files where Self.videoExtensions.contains(url.pathExtension.lowercased()) {
                let name = url.lastPathComponent
                if !items.contains(where: { $0.kind == .localFile && $0.reference == name }) {
                    items.append(MediaItem(title: url.deletingPathExtension().lastPathComponent,
                                           kind: .localFile, reference: name))
                }
            }
        }
        // Drop library entries whose file disappeared.
        items.removeAll { item in
            guard let url = Self.localURL(for: item) else { return false }
            return !fm.fileExists(atPath: url.path)
        }
        scheduleSave()
    }

    // MARK: Persistence

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([MediaItem].self, from: data) else { return }
        items = decoded
    }

    private func scheduleSave() {
        saveWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.saveNow() }
        saveWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    func saveNow() {
        if let data = try? JSONEncoder().encode(items) {
            try? data.write(to: fileURL, options: .atomic)
        }
        publishWidgetSnapshot()
    }

    func publishWidgetSnapshot(nowPlaying: MediaItem? = nil, isPlaying: Bool? = nil, progress: Double? = nil) {
        var snap = WidgetSnapshot.load()
        if let np = nowPlaying {
            snap.nowPlayingTitle = np.title
            snap.nowPlayingKind = np.kind
        }
        if let isPlaying = isPlaying { snap.isPlaying = isPlaying }
        if let progress = progress { snap.progress = progress }
        snap.recent = recent.prefix(4).map {
            WidgetSnapshot.Entry(id: $0.id, title: $0.title, kind: $0.kind, progress: $0.progress)
        }
        snap.updatedAt = Date()
        snap.save()
        WidgetCenter.shared.reloadAllTimelines()
    }
}
