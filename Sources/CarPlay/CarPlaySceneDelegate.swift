import UIKit
import CarPlay

/// Entry point for the CarPlay screen. Uses the navigation-app scene, which gives us a full
/// `CPWindow` we can render video into, plus a `CPMapTemplate` for on-screen buttons.
final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    private var interfaceController: CPInterfaceController?
    private var carWindow: CPWindow?
    private var videoController: CarVideoViewController?
    private var templateController: CarTemplateController?

    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene,
                                  didConnect interfaceController: CPInterfaceController,
                                  to window: CPWindow) {
        self.interfaceController = interfaceController
        self.carWindow = window

        let engine = PlaybackEngine.shared
        let vc = CarVideoViewController(engine: engine, settings: .shared, sensors: .shared)
        window.rootViewController = vc
        videoController = vc

        let templates = CarTemplateController(interfaceController: interfaceController,
                                              engine: engine,
                                              library: .shared,
                                              settings: .shared)
        templateController = templates
        templates.installRootTemplate()

        engine.carConnected = true
        SensorHub.shared.start()
        engine.prepareForCarConnection()
    }

    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene,
                                  didDisconnect interfaceController: CPInterfaceController,
                                  from window: CPWindow) {
        PlaybackEngine.shared.carConnected = false
        templateController = nil
        videoController = nil
        window.rootViewController = nil
        self.interfaceController = nil
        self.carWindow = nil
        LibraryStore.shared.saveNow()
    }

    // Called on iOS 15+ for the instrument-cluster / dashboard; nothing extra needed.
    func sceneDidBecomeActive(_ scene: UIScene) {}
}
