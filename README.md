# Tune

A native **SwiftUI macOS** client for YouTube Music — browse your liked songs and
play them from a clean, native interface.

> **Version 0.1.0** · macOS 26+ · Swift 5

## ⚠️ Disclaimer — read before using

- **Educational / personal use only.** This project is a learning exercise and a
  tool for personal use. It is **not** intended for distribution or commercial use.
- **Not affiliated with Google, YouTube, or YouTube Music** in any way. All
  trademarks belong to their respective owners.
- **Uses unofficial APIs.** Tune talks to YouTube's private *InnerTube* endpoints
  and authenticates with your own browser cookies. This is **not** a supported or
  sanctioned interface and very likely violates the
  [YouTube Terms of Service](https://www.youtube.com/t/terms). Use it at your own
  risk — your Google account is your responsibility.
- **No warranty.** The software is provided "as is", without warranty of any kind.
  The author is not liable for any consequences of using it, including account
  restrictions.
- **Do not ship as-is.** The app uses broad entitlements
  (`Resources/Tune.entitlements`) for network and cookie access and is meant for
  local builds only — not for the App Store or redistribution.

## Privacy & data

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
