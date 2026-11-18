import Foundation
import UIKit
import WebKit

protocol YouTubeBackendDelegate: AnyObject {
    func youtubeDidBecomeReady()
    func youtubeStateChanged(_ state: YouTubeBackend.PlayerState)
    func youtubeTimeUpdated(current: Double, duration: Double)
    func youtubeTitleUpdated(_ title: String)
    func youtubeFailed(code: Int, message: String)
}

/// Plays YouTube videos with the official IFrame Player API inside a single WKWebView.
/// The same web view is moved between the phone UI and the CarPlay window, so playback
/// never restarts when the screen changes.
final class YouTubeBackend: NSObject {
    enum PlayerState: Int {
        case unstarted = -1, ended = 0, playing = 1, paused = 2, buffering = 3, cued = 5
    }

    weak var delegate: YouTubeBackendDelegate?
    private(set) var isReady = false
    private(set) var state: PlayerState = .unstarted

    /// Origin used for the embed (YouTube requires a valid referrer/origin, otherwise error 152/153).
    static let origin = "https://com.saibh.carplayvideo"

    lazy var webView: WKWebView = makeWebView()

    // MARK: Setup

    private func makeWebView() -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.allowsAirPlayForMediaPlayback = true
        config.allowsPictureInPictureMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        let controller = WKUserContentController()
        controller.add(WeakScriptHandler(target: self), name: "yt")
        config.userContentController = controller

        let wv = WKWebView(frame: CGRect(x: 0, y: 0, width: 640, height: 360), configuration: config)
        wv.isOpaque = false
        wv.backgroundColor = .black
        wv.scrollView.backgroundColor = .black
        wv.scrollView.isScrollEnabled = false
        wv.scrollView.bounces = false
        wv.scrollView.contentInsetAdjustmentBehavior = .never
        wv.navigationDelegate = self
        wv.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        wv.loadHTMLString(Self.playerHTML, baseURL: URL(string: Self.origin))
        return wv
    }

    /// Moves the shared web view into `container`, filling it.
    func attach(to container: UIView) {
        let wv = webView
        guard wv.superview !== container else { return }
        wv.removeFromSuperview()
        wv.frame = container.bounds
        wv.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        container.addSubview(wv)
    }

    func isAttached(to container: UIView) -> Bool { webView.superview === container }

    // MARK: Commands

    func load(videoID: String, start: Double, autoplay: Bool) {
        guard YouTubeID.isValidID(videoID) else { return }
        _ = webView // make sure it exists
        run("load('\(videoID)', \(max(0, start)), \(autoplay ? "true" : "false"));")
    }

    func play() { run("player && player.playVideo();") }
    func pause() { run("player && player.pauseVideo();") }
    func stop() { run("player && player.stopVideo();") }
    func seek(to seconds: Double) { run("player && player.seekTo(\(max(0, seconds)), true);") }
    func setRate(_ rate: Double) { run("player && player.setPlaybackRate(\(rate));") }

    private func run(_ js: String) {
        webView.evaluateJavaScript(js, completionHandler: nil)
    }

    fileprivate func handle(message body: Any) {
        guard let dict = body as? [String: Any], let event = dict["e"] as? String else { return }
        switch event {
        case "ready":
            isReady = true
            delegate?.youtubeDidBecomeReady()
        case "state":
            let raw = (dict["v"] as? Int) ?? (dict["v"] as? NSNumber)?.intValue ?? -1
            state = PlayerState(rawValue: raw) ?? .unstarted
            delegate?.youtubeStateChanged(state)
        case "time":
            let c = (dict["c"] as? NSNumber)?.doubleValue ?? 0
            let d = (dict["d"] as? NSNumber)?.doubleValue ?? 0
            delegate?.youtubeTimeUpdated(current: c, duration: d)
        case "title":
            if let t = dict["v"] as? String, !t.isEmpty { delegate?.youtubeTitleUpdated(t) }
        case "error":
            let code = (dict["v"] as? NSNumber)?.intValue ?? -1
            delegate?.youtubeFailed(code: code, message: Self.describeError(code))
        default:
            break
        }
    }

    static func describeError(_ code: Int) -> String {
        switch code {
        case 2: return "Invalid YouTube video ID."
        case 5: return "This video can't be played in the HTML5 player."
        case 100: return "Video not found, removed or private."
        case 101, 150: return "The owner of this video doesn't allow it to be played in other apps."
        case 152, 153: return "YouTube player configuration error. Try again or check your connection."
        default: return "YouTube playback error (\(code))."
        }
    }

    // MARK: HTML

    static let playerHTML: String = """
    <!DOCTYPE html>
    <html><head>
    <meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no">
    <meta name="referrer" content="strict-origin-when-cross-origin">
    <style>
      html,body{margin:0;padding:0;background:#000;width:100%;height:100%;overflow:hidden}
      #player{position:absolute;top:0;left:0;width:100%;height:100%}
    </style>
    </head><body>
    <div id="player"></div>
    <script>
      var player = null, ready = false, pending = null;
      function post(m){ try { window.webkit.messageHandlers.yt.postMessage(m); } catch(e){} }
      var tag = document.createElement('script');
      tag.src = "https://www.youtube.com/iframe_api";
      tag.onerror = function(){ post({e:'error', v:-2}); };
      document.head.appendChild(tag);
      function onYouTubeIframeAPIReady(){
        player = new YT.Player('player', {
          width: '100%', height: '100%',
          playerVars: { playsinline: 1, autoplay: 0, controls: 1, rel: 0, fs: 0, iv_load_policy: 3,
                        origin: '\(YouTubeBackend.origin)', widget_referrer: '\(YouTubeBackend.origin)' },
          events: {
            onReady: function(){
              ready = true; post({e:'ready'});
              if (pending) { var p = pending; pending = null; load(p.id, p.start, p.auto); }
            },
            onStateChange: function(ev){ post({e:'state', v: ev.data}); if (ev.data === 1 || ev.data === 5) sendTitle(); },
            onError: function(ev){ post({e:'error', v: ev.data}); }
          }
        });
        setInterval(function(){
          if (ready && player && player.getCurrentTime) {
            post({e:'time', c: player.getCurrentTime() || 0, d: player.getDuration() || 0});
          }
        }, 500);
      }
      function sendTitle(){
        try { var d = player.getVideoData(); if (d && d.title) post({e:'title', v: d.title}); } catch(e){}
      }
      function load(id, start, auto){
        if (!ready) { pending = {id:id, start:start, auto:auto}; return; }
        var opts = {videoId: id, startSeconds: start};
        if (auto) player.loadVideoById(opts); else player.cueVideoById(opts);
      }
    </script>
    </body></html>
    """
}

extension YouTubeBackend: WKNavigationDelegate {
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        // Recover from WebKit crashes (memory pressure etc.).
        isReady = false
        webView.loadHTMLString(Self.playerHTML, baseURL: URL(string: Self.origin))
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        // Keep the player page in place; open taps on "Watch on YouTube" etc. externally.
        if navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url {
            UIApplication.shared.open(url)
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }
}

/// Avoids the WKUserContentController -> handler retain cycle.
private final class WeakScriptHandler: NSObject, WKScriptMessageHandler {
    weak var target: YouTubeBackend?
    init(target: YouTubeBackend) { self.target = target }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.handle(message: message.body)
    }
}
