// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../utils/prefs/app_prefs.dart';
import 'settings_widgets.dart';

class AdvancedSection extends ConsumerWidget {
  const AdvancedSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final umu = ref.watch(launchUmuGameIdProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsGroup(
          title: 'UMU game ID',
          subtitle: 'Leave as umu-default unless a game fix needs its own ID.',
          divider: false,
          control: SizedBox(
            width: 320,
            child: PrefTextField(
              key: const Key('settings-umu-id'),
              initial: umu,
              onSave: ref.read(launchUmuGameIdProvider.notifier).set,
            ),
          ),
        ),
      ],
    );
  }
}
