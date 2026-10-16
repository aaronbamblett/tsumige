# vn-launcher

A visual novel library and launcher for Linux. Working name; the public name is not chosen yet.

Licensed under the Mozilla Public License 2.0. See `LICENSE`.

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
