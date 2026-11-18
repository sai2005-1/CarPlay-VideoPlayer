import UIKit
import AVFoundation
import SwiftUI

/// UIView backed by an AVPlayerLayer. Several of these can show the same AVPlayer at once
/// (phone preview + car screen).
final class PlayerLayerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }

    var player: AVPlayer? {
        get { playerLayer.player }
        set { playerLayer.player = newValue }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        playerLayer.videoGravity = .resizeAspect
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        backgroundColor = .black
    }
}

/// SwiftUI wrapper for the AVPlayer surface.
struct PlayerSurface: UIViewRepresentable {
    let player: AVPlayer
    var fill: Bool = false

    func makeUIView(context: Context) -> PlayerLayerView {
        let v = PlayerLayerView()
        v.player = player
        return v
    }

    func updateUIView(_ uiView: PlayerLayerView, context: Context) {
        if uiView.player !== player { uiView.player = player }
        uiView.playerLayer.videoGravity = fill ? .resizeAspectFill : .resizeAspect
    }
}

/// SwiftUI host for the shared YouTube web view. Only claims the web view while the
/// car screen is not using it.
struct YouTubeSurface: UIViewRepresentable {
    let backend: YouTubeBackend
    let carConnected: Bool

    func makeUIView(context: Context) -> UIView {
        let v = UIView()
        v.backgroundColor = .black
        v.clipsToBounds = true
        return v
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        if !carConnected {
            backend.attach(to: uiView)
        }
    }
}
