// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../../core/model.dart';
import '../../../../../utils/prefs/app_prefs.dart' hide LaunchMode;

class LaunchTab extends ConsumerWidget {
  const LaunchTab({super.key, required this.game});

  final Game game;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final LaunchMode fallback = ref.watch(launchModeProvider);
    final LaunchMode mode = game.launch.mode ?? fallback;
    final rows = <Widget>[];
    void add(Widget row) {
      rows.add(row);
    }

    if (mode == LaunchMode.steam) {
      final appId = game.launch.steamAppId;
      if (appId != null) {
        add(_row(context, theme, 'Steam app id', '$appId', false));
      }
    } else if (mode == LaunchMode.native) {
      final executable = game.launch.executable;
      if (executable != null && executable.isNotEmpty) {
        add(_executableRow(context, theme, executable));
      }
      final args = game.launch.arguments;
      if (args != null && args.isNotEmpty) {
        add(_row(context, theme, 'Arguments', args, false));
      }
    } else {
      add(_row(context, theme, 'Mode', _modeName(mode),
          game.launch.mode == null));
      final executable = game.launch.executable;
      if (executable != null && executable.isNotEmpty) {
        add(_executableRow(context, theme, executable));
      }
      add(_row(context, theme, 'Prefix',
          game.launch.prefix ?? ref.watch(launchPrefixProvider),
          game.launch.prefix == null));
      final runner =
          game.launch.runner ?? ref.watch(launchRunnerProvider);
      add(_row(context, theme, 'Runner', runner ?? 'umu default',
          game.launch.runner == null));
      add(_row(context, theme, 'Locale',
          game.launch.locale ?? ref.watch(launchLocaleProvider),
          game.launch.locale == null));
      add(_row(context, theme, 'UMU game id',
          game.launch.umuGameId ?? ref.watch(launchUmuGameIdProvider),
          game.launch.umuGameId == null));
      final args = game.launch.arguments;
      if (args != null && args.isNotEmpty) {
        add(_row(context, theme, 'Arguments', args, false));
      }
      final env = game.launch.environment;
      if (env != null && env.isNotEmpty) {
        add(_row(context, theme, 'Environment', env, false));
      }
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 12,
        children: rows,
      ),
    );
  }

  String _modeName(LaunchMode mode) => switch (mode) {
        LaunchMode.proton => 'Proton',
        LaunchMode.wine => 'Wine',
        LaunchMode.native => 'Native',
        LaunchMode.steam => 'Steam',
      };

  Widget _row(BuildContext context, ThemeData theme, String label,
      String value, bool isDefault) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        Text.rich(
          TextSpan(
            children: [
              TextSpan(text: value, style: theme.textTheme.bodyLarge),
              if (isDefault)
                TextSpan(
                  text: ' · default',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _executableRow(
      BuildContext context, ThemeData theme, String executable) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Executable',
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        Tooltip(
          message: executable,
          child: Text(
            _middleEllipsize(executable),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyLarge,
          ),
        ),
      ],
    );
  }

  String _middleEllipsize(String text) {
    if (text.length <= 64) return text;
    return '${text.substring(0, 40)}…${text.substring(text.length - 24)}';
  }
}
