// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../constants/pref_keys.dart' as keys;
import '../../../core/store.dart' as core;
import '../../../utils/extensions/l10n.dart';
import '../../../utils/prefs/app_prefs.dart';
import '../../../utils/toast.dart';
import '../../library/data/library_repository.dart';
import '../widgets/slider_setting_tile/slider_setting_tile.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
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

  @override
  Widget build(BuildContext context) {
    // Watched so the library is loaded before the first refresh tap.
    ref.watch(libraryProvider);
    final coverWidth = ref.watch(coverWidthProvider);
    final dataDir = ref.watch(dataDirProvider);
    final theme = Theme.of(context);
    final headingStyle = theme.textTheme.titleSmall
        ?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: Text(context.l10n.settings),
      ),
      body: Align(
        alignment: Alignment.topLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                child: Text('Appearance', style: headingStyle),
              ),
              SliderSettingTile(
                title: 'Cover size',
                icon: Icons.photo_size_select_large_rounded,
                value: coverWidth.toDouble(),
                defaultValue: keys.coverWidthDefault.toDouble(),
                min: keys.coverWidthMin.toDouble(),
                max: keys.coverWidthMax.toDouble(),
                getSliderLabel: (value) => '${value.round()} px',
                onChanged: (value) =>
                    ref.read(coverWidthProvider.notifier).set(value.round()),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                child: Text('Library', style: headingStyle),
              ),
              ListTile(
                title: const Text('Refresh VNDB ratings'),
                subtitle: const Text(
                  'Fetch the latest VNDB Rating for every game with a VNDB id',
                ),
                enabled: !_refreshing,
                onTap: _refreshing ? null : _refreshRatings,
                trailing: _refreshing
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh_rounded),
              ),
              ListTile(
                title: const Text('Data folder'),
                subtitle: SelectionArea(child: Text(dataDir.root)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
