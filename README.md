# Tune

A native SwiftUI macOS client for browsing and playing YouTube Music in a desktop interface.

> **Version 0.1.0** · macOS 26+ · Swift 5

[Source](https://github.com/maxempolk/macos-native-yt-music-player) · [Build locally](#build)

## About

Tune is a personal learning project that explores a native macOS interface for YouTube Music. It loads a signed-in user's library and plays music through an embedded WebView.

## Highlights

- SwiftUI interface for the home feed, liked songs, playback controls and lyrics.
- Separate InnerTube client for library data and `WKWebView` playback using the signed-in session.
- Session storage in macOS Keychain and local caches for liked songs and artwork.

## Tech Stack

- **App:** Swift 5, SwiftUI, macOS 26+
- **Playback and login:** WebKit (`WKWebView`)
- **Project generation:** XcodeGen

## Live Demo

There is no hosted demo or distributed app build. [Build and run it locally](#build) in Xcode on macOS 26+.

## Important use and privacy notes

- **Personal, educational use only.** This project is not affiliated with Google, YouTube or YouTube Music and is not intended for commercial distribution.
- **Unofficial integration.** Tune uses private InnerTube endpoints and your browser session cookies. This interface is unsupported and may conflict with the [YouTube Terms of Service](https://www.youtube.com/t/terms); using it may put your account at risk.
- **Local builds only.** The app is not prepared for App Store submission or redistribution. Review `Resources/Tune.entitlements` and its network and cookie access before changing that scope.
- **No warranty.** The code is provided as-is; the author accepts no liability for use or account restrictions.

## Privacy and data

Tune does **not** collect or transmit your data to any third party other than
Google's own YouTube Music servers (which it must contact to function).

- **Credentials/session** are stored in the macOS **Keychain**, never in the
  repository or in plaintext files.
- **Caches** (liked-songs list, artwork) are written to `~/Library/Caches`, also
  outside the repository.
- No secrets, cookies, or tokens are committed to this repo.

## Build

This project uses [XcodeGen](https://github.com/yonyz/XcodeGen) — `project.yml`
is the source of truth for the Xcode project.

```sh
# Install XcodeGen if needed
brew install xcodegen

# Generate the Xcode project from project.yml
xcodegen generate

# Open and build
open Tune.xcodeproj
```

Then build & run the `Tune` target from Xcode (⌘R).

### Authentication

On first launch, Tune opens a login window where you sign in to your Google /
YouTube Music account. The session cookies are captured and stored in the
Keychain; subsequent launches reuse them.

## License

No license is granted. This code is published for educational reference only.
If you want to reuse it, please open an issue first.
