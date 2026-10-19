// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'src/constants/app_theme.dart';
import 'src/core/legacy_migration.dart';
import 'src/features/library/data/library_repository.dart';
import 'src/features/settings/presentation/appearance/widgets/app_theme_selector/app_theme_providers.dart';
import 'src/features/settings/widgets/app_theme_mode_tile/app_theme_mode_tile.dart';
import 'src/l10n/generated/app_localizations.dart';
import 'src/routes/router.dart';
import 'src/utils/app_scroll_behavior.dart';
import 'src/utils/desktop/desktop_window.dart';
import 'src/utils/font_licenses.dart';
import 'src/utils/prefs/prefs_mixin.dart';
import 'src/utils/startup_time.dart';
import 'src/utils/theme/app_theme_builder.dart';
import 'src/widgets/app_error_app.dart';
import 'src/widgets/tsumige_logo.dart';

Widget tsumigeRouterBuilder(BuildContext context, Widget? child) =>
    FToastBuilder()(context, child);

/// App entry. Never loads the library: the root widget does that through
/// [libraryProvider] so startup always lands on a loading, error, or library
/// screen instead of failing before the first frame.
Future<void> main() async {
  appMainEntry = DateTime.now();
  WidgetsFlutterBinding.ensureInitialized();
  final env = Platform.environment;
  if (Platform.isLinux) await migrateLegacyDataDir(env);
  if (Platform.isLinux) await migrateLegacyPrefsFile(env);
  final prefs = await SharedPreferences.getInstance();
  await migrateLaunchPrefix(prefs, env);
  await initDesktopWindow(prefs);
  registerFontLicenses();
  runApp(
    ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: const TsumigeApp(),
    ),
  );
}

class TsumigeApp extends ConsumerWidget {
  const TsumigeApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final library = ref.watch(libraryProvider);
    final appTheme = ref.watch(appThemeKeyProvider) ?? kDefaultAppTheme;
    final customSeed = ref.watch(customThemeColorProvider) ?? 0xFF7C7BFF;
    final theme = buildAppTheme(
      theme: appTheme,
      brightness: Brightness.light,
      customSeed: Color(customSeed),
    );
    final darkTheme = buildAppTheme(
      theme: appTheme,
      brightness: Brightness.dark,
      customSeed: Color(customSeed),
    );
    final themeMode = ref.watch(appThemeModeProvider) ?? ThemeMode.system;
    // Show the error screen while a retry is pending too: Riverpod re-runs a
    // failed load on a timer, during which the state is loading-with-error,
    // and a corrupt library would otherwise sit on an empty window.
    if (library.hasError) {
      return AppErrorApp(error: library.error!);
    }
    return library.when(
      loading: () => MaterialApp(
        theme: theme,
        darkTheme: darkTheme,
        themeMode: themeMode,
        scrollBehavior: const AppScrollBehavior(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Center(
            child: Builder(
              builder: (context) => TsumigeLogoShimmer(
                size: MediaQuery.sizeOf(context).shortestSide * 0.35,
              ),
            ),
          ),
        ),
      ),
      error: (error, _) => AppErrorApp(error: error),
      data: (_) => MaterialApp.router(
        builder: tsumigeRouterBuilder,
        theme: theme,
        darkTheme: darkTheme,
        themeMode: themeMode,
        scrollBehavior: const AppScrollBehavior(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: ref.watch(routerProvider),
      ),
    );
  }
}
