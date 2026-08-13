import AppKit
import IOKit.ps

// MARK: - System-wide Now Playing (private MediaRemote framework — same API Control Center uses)

struct Track: Equatable {
    var title: String
    var artist: String
    var album: String
    var isPlaying: Bool
    var artwork: NSImage?
    var sourceApp: String
    var sourceBundle: String = ""
    var duration: Double = 0      // seconds
    var elapsed: Double = 0       // seconds, sampled at `timestamp`
    var timestamp: Double = 0     // epoch seconds when `elapsed` was sampled
    var rate: Double = 0          // playback rate (0 when paused)

    static func == (a: Track, b: Track) -> Bool {
        a.title == b.title && a.artist == b.artist && a.isPlaying == b.isPlaying
    }

    /// Live playback position, projected forward from the last sample.
    var progress: Double {
        guard duration > 0 else { return 0 }
        let projected = elapsed + max(0, Date().timeIntervalSince1970 - timestamp) * (isPlaying ? rate : 0)
        return min(max(projected, 0), duration)
    }
}

enum MediaController {
    // Playback commands still work from any process on macOS 15.4+;
    // only *reading* now-playing info is restricted to Apple-signed callers.
    private typealias SendCommandFn = @convention(c) (UInt32, CFDictionary?) -> Bool

    private static let cmdToggle: UInt32 = 2
    private static let cmdNext: UInt32 = 4
    private static let cmdPrev: UInt32 = 5

    private static let handle: UnsafeMutableRawPointer? = {
        dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW)
    }()

    private static let sendCommand: SendCommandFn? = {
        guard let handle, let sym = dlsym(handle, "MRMediaRemoteSendCommand") else { return nil }
        return unsafeBitCast(sym, to: SendCommandFn.self)
    }()

    /// JXA run inside /usr/bin/osascript — an Apple platform binary, which is the
    /// only kind of process MediaRemote still answers on macOS 15.4+.
    private static let jxa = #"""
    ObjC.import("Foundation");
    function run() {
      try {
        const MR = $.NSBundle.bundleWithPath("/System/Library/PrivateFrameworks/MediaRemote.framework/");
        MR.load;
        const Req = $.NSClassFromString("MRNowPlayingRequest");
        if (!Req) return JSON.stringify({ error: "no MRNowPlayingRequest" });
        const out = { isPlaying: Req.localIsPlaying ? true : false };
        const item = Req.localNowPlayingItem;
        if (item && item.nowPlayingInfo) {
          const d = item.nowPlayingInfo, e = d.keyEnumerator;
          let k;
          while ((k = e.nextObject) && !k.isNil()) {
            const ks = ObjC.unwrap(k), v = d.objectForKey(k);
            const key2 = ks.replace("kMRMediaRemoteNowPlayingInfo", "");
            if (v && !v.isNil()) {
              if (v.isKindOfClass($.NSDate)) out[key2] = v.timeIntervalSince1970;
              else if (v.isKindOfClass($.NSNumber) || v.isKindOfClass($.NSString)) out[key2] = ObjC.unwrap(v);
              else if (v.isKindOfClass($.NSData) && key2 === "ArtworkData")
                out.ArtworkB64 = ObjC.unwrap(v.base64EncodedStringWithOptions(0));
            }
          }
        }
        const pp = Req.localNowPlayingPlayerPath;
        if (pp && pp.client) {
          const c = pp.client;
          if (c.parentApplicationBundleIdentifier && !c.parentApplicationBundleIdentifier.isNil())
            out.ParentBundle = ObjC.unwrap(c.parentApplicationBundleIdentifier);
          if (c.bundleIdentifier && !c.bundleIdentifier.isNil())
            out.Bundle = ObjC.unwrap(c.bundleIdentifier);
        }
        return JSON.stringify(out);
      } catch (e) {
        return JSON.stringify({ error: e.toString() });
      }
    }
    """#

    static func fetchTrack(completion: @escaping (Track?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let track = queryNowPlaying()
            DispatchQueue.main.async { completion(track) }
        }
    }

    private static func queryNowPlaying() -> Track? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        proc.arguments = ["-l", "JavaScript", "-e", jxa]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice

        do { try proc.run() } catch { return nil }

        let watchdog = DispatchWorkItem { proc.terminate() }
        DispatchQueue.global().asyncAfter(deadline: .now() + 5, execute: watchdog)
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        watchdog.cancel()

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              json["error"] == nil,
              let title = json["Title"] as? String, !title.isEmpty else { return nil }

        let artist = json["Artist"] as? String ?? ""
        let album = json["Album"] as? String ?? ""
        let isPlaying = json["isPlaying"] as? Bool ?? false

        var image: NSImage?
        if let b64 = json["ArtworkB64"] as? String, let artData = Data(base64Encoded: b64) {
            image = NSImage(data: artData)
        }

        let bundle = (json["ParentBundle"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            ?? (json["Bundle"] as? String)
            ?? ""
        let sourceApp = NSRunningApplication.runningApplications(withBundleIdentifier: bundle)
            .first?.localizedName ?? bundle

        // Browsers (Chromium/Safari web playback) expose no artwork bytes — only
        // dimensions. For YouTube tabs, grab the tab URL from the browser and use
        // the public thumbnail instead.
        if image == nil, browserAppNames[bundle] != nil {
            image = fetchYouTubeThumbnail(bundle: bundle, title: title)
        }

        func num(_ k: String) -> Double { (json[k] as? NSNumber)?.doubleValue ?? 0 }

        return Track(title: title, artist: artist, album: album,
                     isPlaying: isPlaying, artwork: image, sourceApp: sourceApp,
                     sourceBundle: bundle,
                     duration: num("Duration"), elapsed: num("ElapsedTime"),
                     timestamp: num("Timestamp"), rate: num("PlaybackRate"))
    }

    // MARK: YouTube thumbnails for browser playback

    private static let browserAppNames: [String: String] = [
        "com.brave.Browser": "Brave Browser",
        "com.google.Chrome": "Google Chrome",
        "com.apple.Safari": "Safari",
        "company.thebrowser.Browser": "Arc",
        "com.microsoft.edgemac": "Microsoft Edge",
        "org.mozilla.firefox": "Firefox",
    ]

    private static var thumbCache: [String: NSImage?] = [:]

    private static func fetchYouTubeThumbnail(bundle: String, title: String) -> NSImage? {
        guard let appName = browserAppNames[bundle] else { return nil }
        let cacheKey = bundle + "|" + title
        if let hit = thumbCache[cacheKey] { return hit }

        var result: NSImage?
        defer { thumbCache[cacheKey] = result }

        guard let url = activeTabURL(appName: appName),
              let videoID = youtubeVideoID(from: url) else { return nil }

        let thumbURL = URL(string: "https://i.ytimg.com/vi/\(videoID)/hqdefault.jpg")!
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
        proc.arguments = ["-sL", "--max-time", "5", thumbURL.absoluteString]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice
        guard let _ = try? proc.run() else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        guard data.count > 1000, let img = NSImage(data: data) else { return nil }
        result = img
        return result
    }

    private static func activeTabURL(appName: String) -> String? {
        let script: String
        if appName == "Safari" {
            script = "tell application \"Safari\" to get URL of current tab of front window"
        } else {
            script = "tell application \"\(appName)\" to get URL of active tab of front window"
        }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        proc.arguments = ["-e", script]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice
        guard let _ = try? proc.run() else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        let url = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return url?.isEmpty == false ? url : nil
    }

    private static func youtubeVideoID(from url: String) -> String? {
        let pattern = #"(?:youtube\.com/(?:watch\?[^ ]*v=|shorts/|embed/)|youtu\.be/)([A-Za-z0-9_-]{11})"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: url, range: NSRange(url.startIndex..., in: url)),
              let range = Range(match.range(at: 1), in: url) else { return nil }
        return String(url[range])
    }

    static func seek(to seconds: Double) {
        let opts = ["kMRMediaRemoteOptionPlaybackPosition": seconds] as CFDictionary
        _ = sendCommand?(24, opts) // MRMediaRemoteCommandSeekToPlaybackPosition
    }

    static func command(_ action: String) {
        let code: UInt32
        switch action {
        case "toggle": code = cmdToggle
        case "next": code = cmdNext
        case "prev": code = cmdPrev
        default: return
        }
        _ = sendCommand?(code, nil)
    }
}
