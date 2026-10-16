// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'src/constants/app_theme.dart';
import 'src/features/library/data/library_repository.dart';
import 'src/l10n/generated/app_localizations.dart';
import 'src/routes/router.dart';
import 'src/utils/desktop/desktop_window.dart';
import 'src/utils/prefs/prefs_mixin.dart';
import 'src/utils/startup_time.dart';
import 'src/utils/theme/app_theme_builder.dart';
import 'src/widgets/app_error_app.dart';

/// App entry. Never loads the library: the root widget does that through
/// [libraryProvider] so startup always lands on a loading, error, or library
/// screen instead of failing before the first frame.
Future<void> main() async {
  appMainEntry = DateTime.now();
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  await initDesktopWindow(prefs);
  runApp(
    ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: const VnlApp(),
    ),
  );
}

class VnlApp extends ConsumerWidget {
  const VnlApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final library = ref.watch(libraryProvider);
    // Show the error screen while a retry is pending too: Riverpod re-runs a
    // failed load on a timer, during which the state is loading-with-error,
    // and a corrupt library would otherwise sit on an empty window.
    if (library.hasError) {
      return AppErrorApp(error: library.error!);
    }
    return library.when(
      loading: () => MaterialApp(
        theme: buildAppTheme(theme: AppTheme.vnl, brightness: Brightness.light),
        darkTheme:
            buildAppTheme(theme: AppTheme.vnl, brightness: Brightness.dark),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: SizedBox.shrink()),
      ),
      error: (error, _) => AppErrorApp(error: error),
      data: (_) => MaterialApp.router(
        theme:
            buildAppTheme(theme: AppTheme.vnl, brightness: Brightness.light),
        darkTheme:
            buildAppTheme(theme: AppTheme.vnl, brightness: Brightness.dark),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: ref.watch(routerProvider),
      ),
    );
  }
}
