import AppIntents
import Foundation

/// Toggles playback in the main app. Runs in whichever process hosts it and signals the app
/// through a Darwin notification, so it works from Home Screen, Lock Screen and CarPlay widgets.
@available(iOS 17.0, *)
struct TogglePlaybackIntent: AppIntent {
    static var title: LocalizedStringResource = "Play / Pause"
    static var description = IntentDescription("Plays or pauses the current video in CarPlay Video.")

    func perform() async throws -> some IntentResult {
        DarwinNotifier.post(AppConstants.darwinTogglePlayback)
        return .result()
    }
}

@available(iOS 17.0, *)
struct NextVideoIntent: AppIntent {
    static var title: LocalizedStringResource = "Next Video"
    static var description = IntentDescription("Skips to the next video in the queue.")

    func perform() async throws -> some IntentResult {
        DarwinNotifier.post(AppConstants.darwinNext)
        return .result()
    }
}
