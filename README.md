# vn-launcher

A visual novel library and launcher for Linux. Working name; the public name is not chosen yet.

Licensed under the Mozilla Public License 2.0. See `LICENSE`.

## Building

Flutter 3.47.7 via fvm (`.fvmrc` at the repo root applies in subfolders).
Run every dart/flutter command through `fvm`:

```sh
fvm dart pub get                                             # repo root
(cd packages/vnl_core && fvm dart test)
(cd app && fvm flutter pub get && fvm flutter test)
mkdir -p build && fvm dart compile exe packages/vnl_cli/bin/vnl.dart -o build/vnl && build/vnl --version
(cd app && fvm flutter build linux --release)
```

The `app` package is not a pub workspace member: Flutter 3.47.7's
`flutter_test` pins `test_api 0.7.12`, which conflicts with `vnl_core`'s
`test ^1.33.0` when resolved in one workspace, so the root `pubspec.yaml`
lists only `packages/vnl_core` and `packages/vnl_cli` in `workspace:` and
`app` depends on `vnl_core` through a path dependency instead.

`flutter build linux` needs the GTK dev files visible to pkg-config. With a
Linuxbrew setup, if cmake reports `gtk+-3.0` not found, relink the package
whose `.pc` link went missing (`brew unlink shared-mime-info &&
brew link shared-mime-info`) and rebuild from a clean `app/build/linux`.
