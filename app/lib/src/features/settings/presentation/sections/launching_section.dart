// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../core/launch/detect.dart';
import '../../../../utils/prefs/app_prefs.dart';
import '../../../../utils/theme/brand.dart';
import '../../../library/domain/runner_detection.dart';
import 'settings_widgets.dart';

const String _settingsCustomKey = 'custom';

class LaunchingSection extends StatelessWidget {
  const LaunchingSection({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SettingsGroup(
          rowKey: Key('settings-row-prefix'),
          title: 'Wine prefix',
          control: _PrefixField(),
        ),
        const SettingsGroup(
          rowKey: Key('settings-row-proton'),
          title: 'Proton version',
          control: _ProtonVersionField(),
        ),
        const _GameLanguageGroup(),
      ],
    );
  }
}

class _PrefixField extends ConsumerWidget {
  const _PrefixField();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefix = ref.watch(launchPrefixProvider);
    final set = ref.read(launchPrefixProvider.notifier).set;
    return SizedBox(
      width: 320,
      child: Row(
        children: [
          Expanded(
            child: PrefTextField(
              key: const Key('settings-prefix'),
              initial: prefix,
              isPath: true,
              middleEllipsis: true,
              onSave: set,
            ),
          ),
          const SizedBox(width: 8),
          BrandGlassButton(
            key: const Key('settings-prefix-choose'),
            height: 40,
            expand: false,
            onPressed: () async {
              final picked = await pickFolderOrNull(ref, context);
              if (picked != null) set(picked);
            },
            label: const Text('Choose…'),
          ),
        ],
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
    return SizedBox(
      width: 320,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SettingsDropdown<String>(
            key: const Key('settings-proton-version'),
            value: showCustom ? _settingsCustomKey : _selected(stored, runners),
            items: [
              const DropdownMenuItem(
                value: '',
                child: Text('umu default'),
              ),
              for (final runner in runners)
                DropdownMenuItem(value: runner.path, child: Text(runner.name)),
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
                    middleEllipsis: true,
                    onSave: (text) => set(text.isEmpty ? null : text),
                  ),
                ),
                const SizedBox(width: 8),
                BrandGlassButton(
                  key: const Key('settings-proton-version-choose'),
                  height: 40,
                  expand: false,
                  onPressed: () async {
                    final picked = await pickFolderOrNull(ref, context);
                    if (picked != null) set(picked);
                  },
                  label: const Text('Choose…'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _GameLanguageGroup extends ConsumerStatefulWidget {
  const _GameLanguageGroup();

  @override
  ConsumerState<_GameLanguageGroup> createState() => _GameLanguageGroupState();
}

class _GameLanguageGroupState extends ConsumerState<_GameLanguageGroup> {
  bool? _forceCustom;

  String _selected(String stored) {
    if (stored.isEmpty || localePresets.contains(stored)) return stored;
    return _settingsCustomKey;
  }

  @override
  Widget build(BuildContext context) {
    final stored = ref.watch(launchLocaleProvider);
    final selected = _selected(stored);
    final showCustom = _forceCustom ?? selected == _settingsCustomKey;
    final set = ref.read(launchLocaleProvider.notifier).set;
    return SettingsGroup(
      rowKey: const Key('settings-row-locale'),
      title: 'Game language',
      subtitle: 'Japanese fixes garbled text in most VNs.',
      divider: false,
      control: SizedBox(
        width: 320,
        child: SettingsDropdown<String>(
          key: const Key('settings-locale'),
          value: showCustom ? _settingsCustomKey : selected,
          items: [
            for (final (value, label, key) in localeChoices)
              DropdownMenuItem(
                value: value,
                child: Text(label, key: Key('settings-locale-$key')),
              ),
            const DropdownMenuItem(
              value: _settingsCustomKey,
              child: Text('Custom…', key: Key('settings-locale-custom')),
            ),
          ],
          onChanged: (value) {
            if (value == null) return;
            setState(() => _forceCustom = value == _settingsCustomKey);
            if (value != _settingsCustomKey) set(value);
          },
        ),
      ),
      footer: showCustom
          ? PrefTextField(
              key: const Key('settings-locale-custom-field'),
              initial: selected == _settingsCustomKey ? stored : '',
              hint: 'e.g. fr_FR.UTF-8',
              onSave: set,
            )
          : null,
    );
  }
}
