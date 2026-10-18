// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/version.dart';
import '../../../../utils/theme/brand.dart';
import '../../../../widgets/tsumige_logo.dart';
import 'settings_widgets.dart';

/// Opens the project repository in the browser. Overridden in tests so no
/// browser opens.
final githubUrlOpenerProvider = Provider<Future<bool> Function(Uri)>(
  (ref) => launchUrl,
);

final _repoUri = Uri.parse('https://github.com/aaronbamblett/tsumige');

class AboutSection extends ConsumerWidget {
  const AboutSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const TsumigeLogo(size: 48),
            const SizedBox(width: 12),
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Tsumige', style: theme.textTheme.headlineSmall),
                const SizedBox(height: 4),
                Text('Version $appVersion', style: muted),
              ],
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Divider(height: 1, color: theme.colorScheme.outlineVariant),
        ),
        SettingsRow(
          label: 'License',
          control: Align(
            alignment: Alignment.centerRight,
            child: Text('MPL-2.0', style: theme.textTheme.bodyMedium),
          ),
        ),
        SettingsRow(
          label: 'Source code',
          control: Align(
            alignment: Alignment.centerRight,
            child: BrandGlassButton(
              height: 40,
              expand: false,
              onPressed: () => ref.read(githubUrlOpenerProvider)(_repoUri),
              icon: const Icon(Icons.code_rounded, size: 20),
              label: const Text('GitHub'),
            ),
          ),
        ),
      ],
    );
  }
}
