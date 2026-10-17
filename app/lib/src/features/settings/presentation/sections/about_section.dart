// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';

import '../../../../core/version.dart';
import 'settings_widgets.dart';

class AboutSection extends StatelessWidget {
  const AboutSection({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('vnl', style: theme.textTheme.headlineSmall),
        const SizedBox(height: 4),
        Text('Version $vnlVersion', style: muted),
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
      ],
    );
  }
}
