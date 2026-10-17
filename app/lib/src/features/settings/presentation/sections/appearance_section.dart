// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../constants/app_theme.dart';
import '../../../../constants/pref_keys.dart' as keys;
import '../../../../utils/extensions/bool.dart';
import '../../../../utils/prefs/app_prefs.dart';
import '../../widgets/app_theme_mode_tile/app_theme_mode_tile.dart';
import '../appearance/widgets/app_theme_selector/app_theme_providers.dart';
import '../appearance/widgets/app_theme_selector/app_theme_selector.dart';
import '../appearance/widgets/is_true_black/is_true_black_tile.dart';
import 'settings_widgets.dart';

class AppearanceSection extends ConsumerWidget {
  const AppearanceSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(appThemeModeProvider) ?? ThemeMode.system;
    final coverWidth = ref.watch(coverWidthProvider);
    final trueBlack = ref.watch(isTrueBlackProvider).ifNull();
    final appTheme = ref.watch(appThemeKeyProvider) ?? kDefaultAppTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsGroup(
          title: 'Theme mode',
          subtitle: 'Follow the system or pick light or dark.',
          child: Wrap(
            spacing: 4,
            children: [
              for (final mode in ThemeMode.values)
                SettingsRadioOption(
                  key: Key('settings-theme-mode-${mode.name}'),
                  label: switch (mode) {
                    ThemeMode.system => 'System',
                    ThemeMode.light => 'Light',
                    ThemeMode.dark => 'Dark',
                  },
                  selected: themeMode == mode,
                  onTap: () =>
                      ref.read(appThemeModeProvider.notifier).update(mode),
                ),
            ],
          ),
        ),
        SettingsGroup(
          title: 'Theme',
          subtitle: 'Pick a colour theme.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const ThemeSelector(title: SizedBox.shrink()),
              if (appTheme == AppTheme.custom) const CustomColorTile(),
            ],
          ),
        ),
        if (themeMode != ThemeMode.light)
          SettingsGroup(
            title: 'Pure black',
            child: SettingsRow(
              hint: 'Use true black backgrounds in dark mode.',
              control: Switch(
                key: const Key('settings-true-black'),
                value: trueBlack,
                onChanged: (value) =>
                    ref.read(isTrueBlackProvider.notifier).update(value),
              ),
            ),
          ),
        SettingsGroup(
          title: 'Cover size',
          subtitle: 'Width of covers in the library grid.',
          divider: false,
          child: SettingsRow(
            control: Row(
              children: [
                Expanded(
                  child: Slider(
                    key: const Key('cover-size-slider'),
                    value: coverWidth.toDouble(),
                    min: keys.coverWidthMin.toDouble(),
                    max: keys.coverWidthMax.toDouble(),
                    label: '$coverWidth px',
                    onChanged: (value) => ref
                        .read(coverWidthProvider.notifier)
                        .set(value.round()),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '$coverWidth px',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                IconButton(
                  key: const Key('cover-size-reset'),
                  tooltip: 'Reset cover size',
                  icon: const Icon(Icons.restart_alt_rounded, size: 20),
                  onPressed: () => ref
                      .read(coverWidthProvider.notifier)
                      .set(keys.coverWidthDefault),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
