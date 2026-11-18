import UIKit
import SwiftUI
import CarPlay

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        _ = SettingsStore.shared
        _ = LibraryStore.shared
        _ = PlaybackEngine.shared
        NowPlayingController.shared.registerCommands()
        application.beginReceivingRemoteControlEvents()
        return true
    }

    func application(_ application: UIApplication,
                     configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        if connectingSceneSession.role == UISceneSession.Role.carTemplateApplication {
            let config = UISceneConfiguration(name: "CarPlay", sessionRole: connectingSceneSession.role)
            config.delegateClass = CarPlaySceneDelegate.self
            return config
        }
        let config = UISceneConfiguration(name: "Phone", sessionRole: connectingSceneSession.role)
        config.delegateClass = PhoneSceneDelegate.self
        return config
    }

    func applicationWillTerminate(_ application: UIApplication) {
        LibraryStore.shared.saveNow()
    }
}

final class PhoneSceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = UIHostingController(rootView: RootView())
        window.makeKeyAndVisible()
        self.window = window

        if let ctx = connectionOptions.urlContexts.first {
            DeepLinkRouter.handle(ctx.url)
        }
    }

    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        for ctx in URLContexts { DeepLinkRouter.handle(ctx.url) }
    }

    func sceneWillEnterForeground(_ scene: UIScene) {
        LibraryStore.shared.importLooseFilesFromDocuments()
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        LibraryStore.shared.saveNow()
    }
}

/// Handles `carplayvideo://` links (from widgets) and opened video files / shared YouTube links.
enum DeepLinkRouter {
    static func handle(_ url: URL) {
        let engine = PlaybackEngine.shared
        let library = LibraryStore.shared

        if url.isFileURL {
            if let item = try? library.importFile(at: url) { engine.play(item) }
            return
        }
        guard url.scheme == AppConstants.urlScheme else {
            if let item = MediaFactory.item(from: url.absoluteString) { engine.play(item) }
            return
        }
        let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let query = comps?.queryItems ?? []
        switch url.host {
        case "play":
            if let idString = query.first(where: { $0.name == "id" })?.value,
               let id = UUID(uuidString: idString),
               let item = library.item(withID: id) {
                engine.play(item)
            } else if let link = query.first(where: { $0.name == "url" })?.value,
                      let item = MediaFactory.item(from: link) {
                engine.play(item)
            } else {
                engine.resume()
            }
        case "toggle":
            engine.togglePlayPause()
        default:
            break
        }
    }
}

/// Turns user input (YouTube link, video ID, or any URL) into a MediaItem.
enum MediaFactory {
    static func item(from input: String) -> MediaItem? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if let id = YouTubeID.extract(from: text) {
            if let existing = LibraryStore.shared.items.first(where: { $0.kind == .youtube && $0.reference == id }) {
                return existing
            }
            var item = MediaItem(title: "YouTube \(id)", kind: .youtube, reference: id)
            if let t = YouTubeID.startTime(from: text) { item.resumePosition = t }
            return item
        }
        guard let url = URL(string: text), let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else { return nil }
        let name = url.deletingPathExtension().lastPathComponent
        let title = name.isEmpty || name == "/" ? (url.host ?? "Stream") : name.removingPercentEncoding ?? name
        return MediaItem(title: title, kind: .remoteURL, reference: url.absoluteString)
    }
}
