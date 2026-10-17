// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../core/store.dart' as core;
import '../../../../utils/toast.dart';
import '../../../library/data/library_repository.dart';
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
      final report = await repository.refreshRatings(loaded);
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
          title: 'VNDB ratings',
          subtitle: 'Ratings are fetched for every game with a VNDB id.',
          child: Align(
            alignment: Alignment.centerRight,
            child: FilledButton.tonal(
              key: const Key('settings-refresh-ratings'),
              style: settingsSecondaryButtonStyle(context),
              onPressed: _refreshing ? null : _refreshRatings,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_refreshing) ...[
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 8),
                  ],
                  const Text('Refresh now'),
                ],
              ),
            ),
          ),
        ),
        SettingsGroup(
          title: 'Data folder',
          child: Row(
            children: [
              Expanded(
                child: MiddleEllipsisText(
                  text: dataDir.root,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontFamily: 'monospace',
                  ),
                ),
              ),
              const SizedBox(width: 16),
              FilledButton.tonal(
                key: const Key('settings-open-data'),
                style: settingsSecondaryButtonStyle(context),
                onPressed: () => _openFolder(dataDir.root),
                child: const Text('Open folder'),
              ),
            ],
          ),
        ),
        SettingsGroup(
          title: 'Launch logs',
          subtitle: 'One log per launch.',
          divider: false,
          child: Align(
            alignment: Alignment.centerRight,
            child: FilledButton.tonal(
              key: const Key('settings-open-logs'),
              style: settingsSecondaryButtonStyle(context),
              onPressed: () => _openFolder(dataDir.logs.path),
              child: const Text('Open folder'),
            ),
          ),
        ),
      ],
    );
  }
}
