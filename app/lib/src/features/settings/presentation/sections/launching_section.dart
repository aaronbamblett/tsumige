// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../core/launch/detect.dart';
import '../../../../core/model.dart' as core;
import '../../../../utils/prefs/app_prefs.dart';
import '../../../library/domain/runner_detection.dart';
import 'settings_widgets.dart';

const String _settingsCustomKey = 'custom';

class LaunchingSection extends StatelessWidget {
  const LaunchingSection({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          "Defaults for games that don't set their own.",
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 20),
        const SettingsGroup(title: 'Default mode', child: _ModeCards()),
        const SettingsGroup(
          title: 'Wine prefix',
          subtitle: 'Folder Proton and Wine games run in.',
          child: _PrefixField(),
        ),
        const SettingsGroup(
          title: 'Proton version',
          subtitle: 'Which Proton build umu uses.',
          child: _ProtonVersionField(),
        ),
        const SettingsGroup(
          title: 'Game language',
          subtitle:
              'Locale passed to Windows games. Japanese fixes most VN text.',
          divider: false,
          child: _LocaleField(),
        ),
      ],
    );
  }
}

class _ModeCards extends ConsumerWidget {
  const _ModeCards();

  static const Map<core.LaunchMode, (String, String, IconData)> _info = {
    core.LaunchMode.proton: (
      'Proton',
      'Windows games via umu and Proton',
      Icons.sports_esports_rounded,
    ),
    core.LaunchMode.wine: (
      'Wine',
      'Windows games via a Wine build',
      Icons.wine_bar_rounded,
    ),
    core.LaunchMode.native: ('Native', 'Linux games', Icons.terminal_rounded),
    core.LaunchMode.steam: (
      'Steam',
      'Launch through Steam',
      Icons.storefront_rounded,
    ),
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(launchModeProvider);
    return SizedBox(
      height: 136,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 12,
        children: [
          for (final mode in core.LaunchMode.values)
            Expanded(
              child: _ModeCard(
                key: Key('launch-mode-card-${mode.name}'),
                mode: mode,
                name: _info[mode]!.$1,
                description: _info[mode]!.$2,
                icon: _info[mode]!.$3,
                selected: selected == mode,
                onTap: () => ref.read(launchModeProvider.notifier).set(mode),
              ),
            ),
        ],
      ),
    );
  }
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({
    super.key,
    required this.mode,
    required this.name,
    required this.description,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final core.LaunchMode mode;
  final String name;
  final String description;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected
            ? scheme.primaryContainer.withValues(alpha: 0.6)
            : scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          hoverColor: scheme.onSurface.withValues(alpha: 0.06),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected ? scheme.primary : scheme.outlineVariant,
                width: selected ? 2 : 1,
              ),
            ),
            padding: const EdgeInsets.all(12),
            child: Stack(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      icon,
                      size: 22,
                      color: selected
                          ? scheme.primary
                          : scheme.onSurfaceVariant,
                    ),
                    const Spacer(),
                    Text(
                      name,
                      style: theme.textTheme.bodyLarge,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      description,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
                if (selected)
                  Positioned(
                    top: 0,
                    right: 0,
                    child: Container(
                      key: Key('launch-mode-selected-${mode.name}'),
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: scheme.primary,
                        border: Border.all(
                          color: scheme.primaryContainer,
                          width: 2,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PrefixField extends ConsumerWidget {
  const _PrefixField();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefix = ref.watch(launchPrefixProvider);
    final set = ref.read(launchPrefixProvider.notifier).set;
    return Align(
      alignment: Alignment.centerRight,
      child: SizedBox(
        width: 280,
        child: Row(
          children: [
            Expanded(
              child: PrefTextField(
                key: const Key('settings-prefix'),
                initial: prefix,
                isPath: true,
                onSave: set,
              ),
            ),
            const SizedBox(width: 12),
            FilledButton.tonal(
              key: const Key('settings-prefix-choose'),
              style: settingsSecondaryButtonStyle(context),
              onPressed: () async {
                final picked = await pickFolderOrNull(ref, context);
                if (picked != null) set(picked);
              },
              child: const Text('Choose…'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProtonVersionField extends ConsumerStatefulWidget {
  const _ProtonVersionField();

  @override
  ConsumerState<_ProtonVersionField> createState() =>
      _ProtonVersionFieldState();
}

class _ProtonVersionFieldState extends ConsumerState<_ProtonVersionField> {
  bool? _forceCustom;

  String _selected(String? stored, List<ProtonRunner> runners) {
    if (stored == null || stored.isEmpty) return '';
    if (runners.any((r) => r.path == stored)) return stored;
    return _settingsCustomKey;
  }

  @override
  Widget build(BuildContext context) {
    final stored = ref.watch(launchRunnerProvider);
    final runners =
        ref.watch(protonRunnersProvider).value ?? const <ProtonRunner>[];
    final showCustom =
        _forceCustom ?? _selected(stored, runners) == _settingsCustomKey;
    final set = ref.read(launchRunnerProvider.notifier).set;
    return Align(
      alignment: Alignment.centerRight,
      child: SizedBox(
        width: 280,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SettingsDropdown<String>(
              key: const Key('settings-proton-version'),
              value: showCustom
                  ? _settingsCustomKey
                  : _selected(stored, runners),
              items: [
                const DropdownMenuItem(
                  value: '',
                  child: Text('umu default (recommended)'),
                ),
                for (final runner in runners)
                  DropdownMenuItem(
                    value: runner.path,
                    child: Text(runner.name),
                  ),
                const DropdownMenuItem(
                  value: _settingsCustomKey,
                  child: Text('Custom…'),
                ),
              ],
              onChanged: (value) {
                if (value == null) return;
                if (value == _settingsCustomKey) {
                  setState(() => _forceCustom = true);
                } else {
                  setState(() => _forceCustom = false);
                  set(value.isEmpty ? null : value);
                }
              },
            ),
            if (showCustom) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: PrefTextField(
                      key: const Key('settings-proton-version-custom'),
                      initial: _selected(stored, runners) == _settingsCustomKey
                          ? (stored ?? '')
                          : '',
                      hint: 'umu default',
                      isPath: true,
                      onSave: (text) => set(text.isEmpty ? null : text),
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.tonal(
                    key: const Key('settings-proton-version-choose'),
                    style: settingsSecondaryButtonStyle(context),
                    onPressed: () async {
                      final picked = await pickFolderOrNull(ref, context);
                      if (picked != null) set(picked);
                    },
                    child: const Text('Choose…'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

const List<(String, String)> _localeChoices = [
  ('', 'System'),
  ('ja_JP.UTF-8', 'Japanese'),
  ('zh_CN.UTF-8', 'Chinese'),
  ('ko_KR.UTF-8', 'Korean'),
  ('en_US.UTF-8', 'English'),
];

class _LocaleField extends ConsumerStatefulWidget {
  const _LocaleField();

  @override
  ConsumerState<_LocaleField> createState() => _LocaleFieldState();
}

class _LocaleFieldState extends ConsumerState<_LocaleField> {
  bool? _forceCustom;

  String _selected(String stored) {
    if (stored.isEmpty || localePresets.contains(stored)) return stored;
    return _settingsCustomKey;
  }

  @override
  Widget build(BuildContext context) {
    final stored = ref.watch(launchLocaleProvider);
    final showCustom = _forceCustom ?? _selected(stored) == _settingsCustomKey;
    final set = ref.read(launchLocaleProvider.notifier).set;
    return Align(
      alignment: Alignment.centerRight,
      child: SizedBox(
        width: 280,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 4,
              children: [
                for (final (value, label) in _localeChoices)
                  SettingsRadioOption(
                    key: Key(
                      'settings-locale-${switch (value) {
                        '' => 'system',
                        'ja_JP.UTF-8' => 'japanese',
                        'zh_CN.UTF-8' => 'chinese',
                        'ko_KR.UTF-8' => 'korean',
                        _ => 'english',
                      }}',
                    ),
                    label: label,
                    selected: !showCustom && _selected(stored) == value,
                    onTap: () {
                      setState(() => _forceCustom = false);
                      set(value);
                    },
                  ),
                SettingsRadioOption(
                  key: const Key('settings-locale-custom'),
                  label: 'Custom',
                  selected: showCustom,
                  onTap: () => setState(() => _forceCustom = true),
                ),
              ],
            ),
            if (showCustom) ...[
              const SizedBox(height: 8),
              PrefTextField(
                key: const Key('settings-locale-custom-field'),
                initial: _selected(stored) == _settingsCustomKey ? stored : '',
                hint: 'e.g. fr_FR.UTF-8',
                onSave: set,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
