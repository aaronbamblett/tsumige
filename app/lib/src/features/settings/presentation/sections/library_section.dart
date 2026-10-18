// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../core/steamgriddb.dart';
import '../../../../core/store.dart' as core;
import '../../../../utils/prefs/app_prefs.dart';
import '../../../../utils/theme/brand.dart';
import '../../../../utils/toast.dart';
import '../../../library/data/library_repository.dart';
import '../../../library/presentation/widgets/detail_tabs/related_tab.dart';
import 'settings_widgets.dart';

class LibrarySection extends ConsumerStatefulWidget {
  const LibrarySection({super.key});

  @override
  ConsumerState<LibrarySection> createState() => _LibrarySectionState();
}

class _LibrarySectionState extends ConsumerState<LibrarySection> {
  bool _refreshing = false;

  Future<void> _refreshRatings() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    // Read before the first await so the job survives leaving the page.
    final repository = ref.read(libraryRepositoryProvider);
    final loaded = ref.read(libraryProvider).value;
    final notifier = ref.read(libraryProvider.notifier);
    try {
      if (loaded == null) return;
      if (loaded.skipped.isNotEmpty) {
        if (mounted) {
          Toast(context).showError(
            'Some library entries could not be read, so ratings cannot be saved. Fix library.json first.',
          );
        }
        return;
      }
      final report = await repository.refreshVndbData(loaded);
      if (report.updated > 0) {
        try {
          await repository.save(loaded);
        } on core.ChangedOnDisk {
          await notifier.reload();
          if (mounted) {
            Toast(context).showError(
              'The library changed outside the app. Reloaded it, try again.',
            );
          }
          return;
        } catch (_) {
          await notifier.reload();
          rethrow;
        }
      }
      await notifier.reload();
      if (!mounted) return;
      if (report.error != null) {
        Toast(context).showError('VNDB refresh failed: ${report.error}');
        return;
      }
      var message = 'Updated ${report.updated} VNDB ratings';
      if (report.notFound.isNotEmpty) {
        message += ', ${report.notFound.length} not found on VNDB';
      }
      Toast(context).show(message);
    } catch (e) {
      if (mounted) {
        Toast(context).showError('VNDB refresh failed: $e');
      }
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  Future<void> _openFolder(String path) async {
    try {
      // Synchronous so widget tests can use a real temp folder.
      Directory(path).createSync(recursive: true);
    } catch (_) {
      // Opening the folder still works when creating it failed.
    }
    try {
      final opened = await ref.read(folderOpenerProvider)(Uri.file(path));
      if (!opened && mounted) {
        Toast(context).showError('Could not open $path');
      }
    } catch (e) {
      if (mounted) {
        Toast(context).showError('Could not open folder: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Watched so the library is loaded before the first refresh tap.
    ref.watch(libraryProvider);
    final dataDir = ref.watch(dataDirProvider);
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsGroup(
          rowKey: const Key('settings-row-vndb'),
          title: 'VNDB data',
          subtitle:
              'Ratings, tags, developers and related VNs are fetched for every game with a VNDB id.',
          control: IntrinsicWidth(
            child: BrandButton(
              key: const Key('settings-refresh-ratings'),
              height: 40,
              expand: false,
              loading: _refreshing,
              onPressed: _refreshing ? null : _refreshRatings,
              label: const Text('Refresh now'),
            ),
          ),
        ),
        SettingsGroup(
          rowKey: const Key('settings-row-steamgriddb'),
          title: 'SteamGridDB',
          subtitle:
              'Optional. Adds covers and backgrounds from steamgriddb.com to Change art. Uses your own API key, stored on this computer.',
          control: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              SizedBox(
                width: 220,
                child: PrefTextField(
                  key: const Key('settings-steamgriddb-key'),
                  initial: ref.watch(steamGridDbKeyProvider),
                  obscureText: true,
                  onSave: (text) =>
                      ref.read(steamGridDbKeyProvider.notifier).set(text),
                ),
              ),
              TextButton(
                style: TextButton.styleFrom(
                  minimumSize: const Size(0, 40),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: () => ref.read(vndbUrlOpenerProvider)(
                  Uri.parse(steamGridDbPreferencesUrl),
                ),
                child: const Text('Get a key'),
              ),
            ],
          ),
        ),
        SettingsGroup(
          rowKey: const Key('settings-row-data-folder'),
          title: 'Data folder',
          subtitleWidget: MiddleEllipsisText(
            text: dataDir.root,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontFamily: 'monospace',
            ),
          ),
          control: IntrinsicWidth(
            child: BrandGlassButton(
              key: const Key('settings-open-data'),
              height: 40,
              expand: false,
              onPressed: () => _openFolder(dataDir.root),
              label: const Text('Open folder'),
            ),
          ),
        ),
        SettingsGroup(
          rowKey: const Key('settings-row-launch-logs'),
          title: 'Launch logs',
          subtitle: 'One log per launch.',
          divider: false,
          control: IntrinsicWidth(
            child: BrandGlassButton(
              key: const Key('settings-open-logs'),
              height: 40,
              expand: false,
              onPressed: () => _openFolder(dataDir.logs.path),
              label: const Text('Open folder'),
            ),
          ),
        ),
      ],
    );
  }
}
