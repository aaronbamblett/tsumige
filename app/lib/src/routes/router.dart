// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../features/library/data/library_repository.dart';
import '../utils/extensions/l10n.dart';

/// App routes: `/` is the library, `/settings` the settings page. Both are
/// placeholders showing the grid and settings tasks land on.
final routerProvider = Provider<GoRouter>((ref) => GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => const LibraryPlaceholderScreen(),
        ),
        GoRoute(
          path: '/settings',
          builder: (context, state) => const SettingsPlaceholderScreen(),
        ),
      ],
    ));

/// Placeholder for the library grid (Task 8): shows the game count.
class LibraryPlaceholderScreen extends ConsumerWidget {
  const LibraryPlaceholderScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = switch (ref.watch(libraryProvider)) {
      AsyncData(:final value) => value.library.games.length,
      _ => 0,
    };
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.library)),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(count == 1 ? '1 game' : '$count games'),
            FilledButton(
              onPressed: () => context.go('/settings'),
              child: Text(context.l10n.settings),
            ),
          ],
        ),
      ),
    );
  }
}

/// Placeholder for the settings page (Task 10): a title with a back button.
class SettingsPlaceholderScreen extends StatelessWidget {
  const SettingsPlaceholderScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: Text(context.l10n.settings),
      ),
      body: const SizedBox.shrink(),
    );
  }
}
