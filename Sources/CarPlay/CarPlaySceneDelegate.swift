import UIKit
import CarPlay

/// Entry point for the CarPlay video experience. CarPlay renders its templates for each display.
@MainActor
final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    private var interfaceController: CPInterfaceController?
    private var templateController: CarTemplateController?

    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene,
                                  didConnect interfaceController: CPInterfaceController) {
        self.interfaceController = interfaceController

        let engine = PlaybackEngine.shared
        let templates = CarTemplateController(interfaceController: interfaceController,
                                              engine: engine,
                                              library: .shared)
        templateController = templates
        templates.installRootTemplate()

        engine.carConnected = true
        engine.prepareForCarConnection()
    }

    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene,
                                  didDisconnectInterfaceController interfaceController: CPInterfaceController) {
        PlaybackEngine.shared.carConnected = false
        templateController = nil
        self.interfaceController = nil
        LibraryStore.shared.saveNow()
    }

    func sceneDidBecomeActive(_ scene: UIScene) {}
}
