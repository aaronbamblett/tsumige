# vn-launcher

A visual novel library and launcher for Linux. Working name; the public name is not chosen yet.

Licensed under the Mozilla Public License 2.0. See `LICENSE`.

## Install

Download the file for your system from the
[releases page](https://github.com/aaronbamblett/tsumige/releases).

- **Linux (Flatpak, recommended):** `flatpak remote-add --if-not-exists tsumige https://flatpak.tsumige.app/index.flatpakrepo`, then `flatpak install tsumige app.tsumige.Tsumige`.
- **Linux (AppImage):** download `Tsumige-…-x86_64.AppImage`, run `chmod +x` on it, then run it.
- **macOS:** unzip `Tsumige-…-macos.zip`. The app is unsigned, so right-click it and choose Open the first time.
- **Windows:** unzip `Tsumige-…-windows-x64.zip` and run `tsumige.exe`.

## Building

Flutter 3.47.7 via fvm (`.fvmrc` at the repo root applies in subfolders).
Run every dart/flutter command through `fvm`, from `app/`:

```sh
cd app
fvm flutter pub get
fvm flutter test
fvm flutter build linux --release
```

`flutter build linux` needs the GTK dev files visible to pkg-config. With a
Linuxbrew setup, if cmake reports `gtk+-3.0` not found, relink the package
whose `.pc` link went missing (`brew unlink shared-mime-info &&
brew link shared-mime-info`) and rebuild from a clean `app/build/linux`.
