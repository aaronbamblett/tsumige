// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../features/library/presentation/library_screen.dart';

part 'router.g.dart';

/// Whether the scaffold shows its plain title bar: false on the library
/// route, which draws its own top bar (merged or stacked), true everywhere
/// else. Starts false because the app always opens on the library.
@Riverpod(keepAlive: true)
class ScaffoldTitleBar extends _$ScaffoldTitleBar {
  @override
  bool build() => false;

  bool get isOn => state;

  void set(bool value) => state = value;
}

/// Keeps [scaffoldTitleBarProvider] in step with the top route. Popup routes
/// (dialogs) are ignored so opening a dialog never toggles the chrome
/// underneath it.
class ScaffoldTitleBarObserver extends NavigatorObserver {
  ScaffoldTitleBarObserver(this._ref);

  final Ref _ref;

  void _sync(Route? top) {
    if (top is PopupRoute) return;
    // The initial push fires while the tree is still building, when the
    // provider already holds the right value, so only write on change.
    final value = top?.settings.name != 'library';
    final notifier = _ref.read(scaffoldTitleBarProvider.notifier);
    if (notifier.isOn != value) notifier.set(value);
  }

  @override
  void didPush(Route route, Route? previousRoute) => _sync(route);

  @override
  void didPop(Route route, Route? previousRoute) => _sync(previousRoute);

  @override
  void didRemove(Route route, Route? previousRoute) => _sync(previousRoute);

  @override
  void didReplace({Route? newRoute, Route? oldRoute}) => _sync(newRoute);
}

/// App routes: `/` is the library. Settings opens as a dialog over it.
final routerProvider = Provider<GoRouter>(
  (ref) => GoRouter(
    observers: [ScaffoldTitleBarObserver(ref)],
    routes: [
      GoRoute(
        path: '/',
        name: 'library',
        builder: (context, state) => const LibraryScreen(),
      ),
    ],
  ),
);
