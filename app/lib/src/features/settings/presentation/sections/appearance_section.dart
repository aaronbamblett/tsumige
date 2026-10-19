// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../constants/app_theme.dart';
import '../../../../constants/pref_keys.dart' as keys;
import '../../../../utils/prefs/app_prefs.dart';
import '../../widgets/app_theme_mode_tile/app_theme_mode_tile.dart';
import '../appearance/widgets/app_theme_selector/app_theme_providers.dart';
import '../appearance/widgets/app_theme_selector/app_theme_selector.dart';
import 'settings_widgets.dart';

class AppearanceSection extends ConsumerWidget {
  const AppearanceSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(appThemeModeProvider) ?? ThemeMode.system;
    final coverWidth = ref.watch(coverWidthProvider);
    final appTheme = ref.watch(appThemeKeyProvider) ?? kDefaultAppTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsGroup(
          title: 'Theme mode',
          control: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: 2,
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
        ThemeSelector(
          title: Text('Theme', style: Theme.of(context).textTheme.titleMedium),
        ),
        if (appTheme == AppTheme.custom) const CustomColorTile(),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Divider(
            height: 1,
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
        SettingsGroup(
          title: 'Cover size',
          control: Row(
            children: [
              Expanded(
                child: Slider(
                  key: const Key('cover-size-slider'),
                  value: coverWidth.toDouble(),
                  min: keys.coverWidthMin.toDouble(),
                  max: keys.coverWidthMax.toDouble(),
                  label: '$coverWidth px',
                  onChanged: (value) =>
                      ref.read(coverWidthProvider.notifier).set(value.round()),
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
        SettingsGroup(
          title: 'Show in details pane',
          divider: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 4,
            children: [
              for (final field in _detailFields)
                _DetailFieldRow(field: field),
            ],
          ),
        ),
      ],
    );
  }
}

/// An Info tab section with its settings checkbox label, in display order.
class _DetailField {
  const _DetailField(this.id, this.label);

  final String id;
  final String label;
}

const List<_DetailField> _detailFields = [
  _DetailField(keys.detailFieldDescription, 'Description'),
  _DetailField(keys.detailFieldTags, 'Tags'),
  _DetailField(keys.detailFieldVndbTags, 'VNDB tags'),
  _DetailField(keys.detailFieldNotes, 'Notes'),
];

class _DetailFieldRow extends ConsumerWidget {
  const _DetailFieldRow({required this.field});

  final _DetailField field;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final selected =
        ref.watch(detailFieldsProvider).contains(field.id);
    final toggle = ref.read(detailFieldsProvider.notifier).toggle;
    return InkWell(
      key: Key('settings-detail-field-${field.id}'),
      borderRadius: BorderRadius.circular(8),
      onTap: () => toggle(field.id),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: ExcludeFocus(
                child: Checkbox(
                  value: selected,
                  onChanged: (_) => toggle(field.id),
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              field.label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurface,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
