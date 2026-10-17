// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../features/library/presentation/library_screen.dart';
import '../features/settings/presentation/settings_screen.dart';

/// App routes: `/` is the library, `/settings` the settings page.
final routerProvider = Provider<GoRouter>((ref) => GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => const LibraryScreen(),
        ),
        GoRoute(
          path: '/settings',
          builder: (context, state) => const SettingsScreen(),
        ),
      ],
    ));
