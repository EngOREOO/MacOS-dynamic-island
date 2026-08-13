# MacOS Dynamic Island

A Dynamic Island for your MacBook notch — just like the iPhone. A slim black pill
that lives at the top-center of your screen, shows what's playing, pops up
notifications when the track changes, and expands on hover with full media
controls and a seekable progress bar.

![Platform](https://img.shields.io/badge/platform-macOS%2013%2B-black)
![Swift](https://img.shields.io/badge/Swift-5.9-orange)
![Chip](https://img.shields.io/badge/Apple%20Silicon-M1%2FM2%2FM3%2FM4-green)

## Features

- **Idle pill** — clock + battery, sits quietly at the top of the screen
- **Now Playing pill** — artwork, track title, and a live animated waveform
  while anything plays (freezes on pause)
- **Track-change pop** — the island expands by itself for ~4 seconds when a new
  track starts, then shrinks back (iPhone-style)
- **Hover to expand** — full card with artwork, title, artist, source-app badge,
  previous / play-pause / next, and a **seek bar you can drag** to scrub
  through the song or video
- **Works with everything** — YouTube in Brave/Chrome/Safari/Arc/Edge/Firefox,
  Apple Music, Spotify, QuickTime… anything macOS Now Playing sees
- **YouTube thumbnails** — browser playback doesn't ship artwork to macOS, so the
  app pulls the real video thumbnail from the browser tab URL
- **Click-through** — the invisible window area never steals your clicks or
  hover; only the visible island reacts
- **No Dock icon**, floats above everything, follows you across Spaces

## Requirements

- macOS 13 or later (developed and tested on macOS 26, Apple Silicon)
- Xcode command line tools (`xcode-select --install`) — only needed to build

## Build & Run

```sh
cd DynamicIsland
swift build -c release
cp .build/release/DynamicIsland "Dynamic Island.app/Contents/MacOS/DynamicIsland"
open "Dynamic Island.app"
```

Or just double-click **Dynamic Island.app** if it's already built.

To run it at every login:
**System Settings → General → Login Items → + → choose Dynamic Island.app**

To quit: hover the island and click the small power button (bottom corner of
the expanded card).

## Permissions (one-time prompts)

macOS will ask once for each of these — approve them:

- **Automation → your browser**: lets the island read the active tab URL to
  fetch YouTube thumbnails. Without it, everything still works; browser tracks
  just show a music-note placeholder instead of the video thumbnail.

## Usage

| Action | Result |
|---|---|
| Do nothing | Slim pill: time + battery (or track + waveform while playing) |
| Play media anywhere | Pill grows with artwork + title + live waveform |
| Track changes | Island pops open ~4s with "Now Playing", then collapses |
| Hover the island | Full controls: prev / play / next, seek slider, source badge |
| Drag the seek bar | Scrubs the playing song/video |
| Click the power icon | Quits the app |

## How it works

- SwiftUI + a borderless, always-on-top `NSPanel` positioned at the top-center
  of the screen, 13px below the edge.
- Since macOS 15.4, Apple restricts Now Playing *reads* to Apple-signed
  processes. The app runs its query through a small embedded JXA script executed
  by `/usr/bin/osascript` (a platform binary), which returns title, artist,
  duration, elapsed time, playback rate, artwork, and the source app as JSON.
- Playback commands (play/pause/next/prev/seek) are **not** restricted, so they
  go straight to the system via `MRMediaRemoteSendCommand`.
- Hover hit-testing is done manually: the window ignores the mouse everywhere
  except the island's actual visible frame, so it never interferes with apps
  underneath.

## Project layout

```
DynamicIsland/
├── Package.swift                  SwiftPM manifest (macOS 13+)
├── Dynamic Island.app/            Prebuilt app bundle (double-click to run)
└── Sources/
    ├── DynamicIslandApp.swift     App entry point + AppDelegate
    ├── IslandWindow.swift         Borderless panel, positioning, hover hit-testing
    ├── MediaController.swift      Now Playing bridge (osascript/JXA), commands, thumbnails
    ├── IslandState.swift          State machine: idle / compact / notification / expanded
    ├── IslandView.swift           Island UI + animated waveform
    └── SeekBarView.swift          Live seek/progress slider
```

## Notes

- Uses the private `MediaRemote` framework (same one Control Center uses). Not
  App Store eligible, and could change in a future macOS update.
- Artwork for non-YouTube browser players may fall back to the placeholder —
  browsers expose artwork dimensions but not image bytes.

## Author

**Ahmed Hany (EngOREOO)**

- GitHub: [@EngOREOO](https://github.com/EngOREOO)
- LinkedIn: [codebyoreoo](https://www.linkedin.com/in/codebyoreoo/)
- Facebook: [hanyohnana](https://web.facebook.com/hanyohnana)
- Email: [ahmed.hany.off@gmail.com](mailto:ahmed.hany.off@gmail.com)
