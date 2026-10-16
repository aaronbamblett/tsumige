// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:vnl_core/vnl_core.dart' as core;

import '../constants/app_theme.dart';
import '../features/library/data/library_repository.dart';
import '../l10n/generated/app_localizations.dart';
import '../utils/extensions/l10n.dart';
import '../utils/theme/app_theme_builder.dart';

/// The message for a library load failure. Corrupt-file and newer-schema
/// errors name the library file and the backups folder so the data can be
/// recovered by hand; the file itself is never touched.
String libraryErrorMessage(Object error, core.DataDir dir) {
  final paths =
      '\n\nLibrary file: ${dir.libraryJson.path}\nBackups: ${dir.backups.path}';
  if (error is core.InvalidJson) {
    return 'Invalid JSON in ${error.path}: ${error.message}$paths';
  }
  if (error is core.NewerSchema) {
    return 'Unsupported schema version ${error.found} '
        '(this app supports ${error.supported}).$paths';
  }
  return error.toString();
}

/// A full standalone app shown when the library cannot be loaded.
class AppErrorApp extends ConsumerWidget {
  const AppErrorApp({super.key, required this.error});

  final Object error;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dir = ref.watch(dataDirProvider);
    return MaterialApp(
      theme: buildAppTheme(theme: AppTheme.vnl, brightness: Brightness.light),
      darkTheme:
          buildAppTheme(theme: AppTheme.vnl, brightness: Brightness.dark),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.l10n.errorTitle,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const Gap(12),
                    Text(libraryErrorMessage(error, dir)),
                    const Gap(16),
                    FilledButton(
                      onPressed: () => ref.invalidate(libraryProvider),
                      child: Text(context.l10n.retry),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
