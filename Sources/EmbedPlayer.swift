import WebKit
import UIKit

/// Plays a song through YouTube's OFFICIAL embedded player (IFrame Player API) inside a tiny web view.
/// This is the one route that does not depend on stream links / PO tokens / bot checks, because it is YouTube's own player.
/// Limits: no downloading, and videos whose owner disabled embedding (errors 101/150) cannot play this way.
@MainActor final class EmbedPlayer: NSObject, WKScriptMessageHandler {
    static let shared = EmbedPlayer()
    var onState: (@MainActor (Int) -> Void)?                  // 0 ended, 1 playing, 2 paused, 3 buffering
    var onTime: (@MainActor (Double, Double) -> Void)?        // position, duration
    var onError: (@MainActor (Int) -> Void)?                  // 2, 5, 100, 101, 150 ...

    private var web: WKWebView?
    private var ready = false
    private var pending: String?

    private static let html = """
    <!DOCTYPE html><html><head><meta name="viewport" content="width=device-width,initial-scale=1">
    <style>html,body{margin:0;padding:0;background:#000;overflow:hidden}</style></head><body><div id="p"></div>
    <script>
    var player;
    function post(o){ try { window.webkit.messageHandlers.yt.postMessage(o); } catch(e){} }
    var tag=document.createElement('script'); tag.src='https://www.youtube.com/iframe_api'; document.head.appendChild(tag);
    function onYouTubeIframeAPIReady(){
      player=new YT.Player('p',{height:'200',width:'200',
        playerVars:{playsinline:1,controls:0,rel:0,fs:0,disablekb:1,iv_load_policy:3,origin:'https://www.youtube.com'},
        events:{
          onReady:function(){ post({e:'ready'}); },
          onStateChange:function(ev){ post({e:'state',s:ev.data}); },
          onError:function(ev){ post({e:'error',c:ev.data}); }
        }});
      setInterval(function(){ if(player&&player.getCurrentTime){ post({e:'time',t:player.getCurrentTime(),d:player.getDuration()}); } },500);
    }
    </script></body></html>
    """

    private func makeWeb() -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.allowsInlineMediaPlayback = true
        cfg.mediaTypesRequiringUserActionForPlayback = []
        cfg.userContentController.add(self, name: "yt")
        let w = WKWebView(frame: CGRect(x: 0, y: 0, width: 200, height: 200), configuration: cfg)
        w.isOpaque = false; w.alpha = 0.02; w.isUserInteractionEnabled = false
        // must live inside a window or iOS may suspend its media
        let win = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap { $0.windows }.first { $0.isKeyWindow }
        win?.insertSubview(w, at: 0)
        w.loadHTMLString(Self.html, baseURL: URL(string: "https://www.youtube.com"))
        return w
    }

    func load(_ id: String) {
        guard id.range(of: "^[A-Za-z0-9_-]{6,20}$", options: .regularExpression) != nil else { onError?(-2); return }
        if web == nil { web = makeWeb(); ready = false }
        if ready { run("player.loadVideoById('\(id)')") } else { pending = id }
    }
    func play() { run("player.playVideo()") }
    func pause() { run("player.pauseVideo()") }
    func seek(_ s: Double) { run("player.seekTo(\(s), true)") }
    func stop() { pending = nil; if ready { run("player.stopVideo()") } }

    private func run(_ js: String) { guard ready else { return }; web?.evaluateJavaScript(js, completionHandler: nil) }

    func userContentController(_ c: WKUserContentController, didReceive m: WKScriptMessage) {
        guard let d = m.body as? [String: Any], let e = d["e"] as? String else { return }
        switch e {
        case "ready":
            ready = true
            if let id = pending { pending = nil; run("player.loadVideoById('\(id)')") }
        case "state": if let s = d["s"] as? Int { onState?(s) }
        case "time": onTime?((d["t"] as? Double) ?? 0, (d["d"] as? Double) ?? 0)
        case "error": if let c = d["c"] as? Int { onError?(c) }
        default: break
        }
    }
}
