// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../features/library/presentation/library_screen.dart';

/// App routes: `/` is the library. Settings opens as a dialog over it.
/// The library screen draws its own top bar, so no scaffold chrome is needed.
final routerProvider = Provider<GoRouter>(
  (ref) => GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const LibraryScreen(),
      ),
    ],
  ),
);
