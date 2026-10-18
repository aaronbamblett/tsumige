<p align="center">
 <picture>
  <source media="(prefers-color-scheme: dark)" srcset="app/assets/icon/tsumige_mark.png">
  <source media="(prefers-color-scheme: light)" srcset="app/assets/icon/tsumige_mark_on_light.png">
  <img width=120px height=120px src="app/assets/icon/tsumige_mark.png" alt="Tsumige logo"/>
 </picture>
</p>

<h1 align="center">Tsumige</h1>

<div align="center">

[![Platform](https://img.shields.io/badge/platform-Linux%20%7C%20macOS%20%7C%20Windows-lightgrey)](https://github.com/aaronbamblett/tsumige/releases)
[![License: MPL-2.0](https://img.shields.io/badge/license-MPL--2.0-blue)](LICENSE)
[![Latest release](https://img.shields.io/github/v/release/aaronbamblett/tsumige?label=download)](https://github.com/aaronbamblett/tsumige/releases/latest)

</div>

<p align="center">A good-looking library and launcher for your visual novels</p>

> *Tsumige* (積みゲー) is the pile of games you've bought and haven't played yet. It's a sibling of [Tsumiru](https://tsumiru.app), the manga and webtoon reader, and shares its look and themes.

## What it is

Tsumige keeps your visual novels in one library with their cover art, descriptions and tags from [VNDB](https://vndb.org), and starts each one with the settings it needs. Everything stays on your computer: no account, no server, and your library is a JSON file in your data folder. Guides and the FAQ are at [tsumige.app](https://tsumige.app).

## Features

- **Cover art.** Covers and backgrounds come from VNDB. You can swap in another from the release packages or screenshots, or use your own image.
- **VNDB metadata.** Search VNDB when you add a game and the description, developer, release date, length, rating and tags fill in.
- **Folder import.** Point Tsumige at a folder of games. Each subfolder is matched to VNDB and its .exe is picked for you, and you check every match before anything is added.
- **Launching.** Proton (through umu-run), Wine, native executables and Steam. Prefix, Proton or Wine version and game locale are set per game, and installers or patches run inside the same prefix.
- **Playtime.** Every session is recorded from launch to exit, with a total and a history for each game.
- **Library tools.** Search, sort, favourites, your own tags and VNDB tags (spoilers hidden until you ask), related titles, and an adult filter.
- **Themes.** Built-in themes, light and dark, and a custom accent colour.

## Download

Get the latest build from [Releases](https://github.com/aaronbamblett/tsumige/releases/latest). The [download page](https://tsumige.app/download/) has install steps for each platform.

- **Linux:** the Flatpak from our own repo updates itself. An AppImage is also on Releases.
- **macOS and Windows:** builds are on Releases. Linux is the platform in daily use; macOS and Windows support is newer.

## Building

The Flutter version is pinned in `.fvmrc`. The app lives in `app/`.

```bash
cd app
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter build linux --release   # or: macos / windows
```

## Credits and license

Game data comes from [VNDB](https://vndb.org).

Licensed under the [Mozilla Public License 2.0](LICENSE). Source files keep their MPL-2.0 headers.
