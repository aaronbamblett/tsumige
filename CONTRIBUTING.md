# Contributing to Tsumige

Thanks for your interest in Tsumige. It is a Flutter app in `app/`, licensed under MPL-2.0.

## Reporting bugs

Search existing issues first, then open a bug report with your Tsumige version, platform, OS version, and steps to reproduce. The bug form asks for the launch logs from **Settings → Library → Launch logs → Open folder**.

## Requesting features

Open a feature request that describes the problem you are trying to solve, not only the solution.

## Development

Flutter is pinned in `.fvmrc` (3.47.7). Install it with fvm and run every command from `app/`:

```sh
cd app
fvm install
fvm flutter pub get
fvm dart run build_runner build --delete-conflicting-outputs
fvm flutter analyze
fvm flutter test
```

- Run `build_runner` after changing `@riverpod` annotations or any other generated source.
- Tests must never call the VNDB API. Use fakes or fixtures for VNDB responses.
- Match the surrounding code style and keep pull requests focused on one change.

## Pull requests

- One logical change per PR. Describe the *why*.
- Make sure `analyze` and `test` pass, and test the flow you changed.
- By contributing, you agree your work is licensed under the project's MPL-2.0 license (see `LICENSE`).

Please also follow our [Code of Conduct](./CODE_OF_CONDUCT.md).
