# Resona

A YouTube Music client for iOS and iPadOS with a Material 3 Expressive look:
dynamic colours from the album artwork, a floating navigation bar, an
expandable mini player and karaoke-style synced lyrics.

Resona is a UI fork of [Trop](https://github.com/SwiftyMedia/Trop) by 686udjie.
All networking, playback, library sync, downloads and lyrics providers come
from Trop unchanged; Resona replaces the SwiftUI views. The visual design is
inspired by the Android app ArchiveTune (GPLv3) and re-implemented in SwiftUI.

## Features

- Google sign-in through an in-app web view, library sync (playlists, albums, artists, podcasts)
- Streaming, downloads, queue, listening history, equalizer, SponsorBlock
- Synced lyrics (Musixmatch, LRCLIB, Netease, Kugou, Genius)
- Colour scheme generated from the current artwork (tonal palettes)
- Floating navigation bar on iPhone, navigation rail on iPad / wide screens
- Universal app, iPad landscape supported

## Install

Requires iOS 18 or later. Grab the unsigned `Resona.ipa`:

- latest build: **Actions** tab → newest *Build IPA* run → artifact `Resona-<n>`
- releases: push a tag `vX.Y.Z` and the workflow publishes a GitHub release

Sideload it with ESign, Feather, AltStore or SideStore (they re-sign it).

## Building

The IPA is built on GitHub Actions (`.github/workflows/build.yml`, `macos-latest`,
latest stable Xcode). Locally on a Mac: `./build_ipa.sh` → `build/Resona.ipa`.
The first build compiles ffmpeg-kit from source and takes a while; CI caches it.

Discord Rich Presence from upstream Trop is disabled because its SDK is
proprietary and not redistributable.

## License

GPLv3, see [LICENSE.txt](LICENSE.txt). Not affiliated with Google or YouTube.
