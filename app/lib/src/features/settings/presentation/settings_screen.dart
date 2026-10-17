// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../constants/app_theme.dart';
import '../../../constants/pref_keys.dart' as keys;
import '../../../core/launch/detect.dart';
import '../../../core/model.dart' as model;
import '../../../core/store.dart' as core;
import '../../../utils/extensions/l10n.dart';
import '../../../utils/prefs/app_prefs.dart';
import '../../../utils/toast.dart';
import '../../library/data/library_repository.dart';
import '../../library/domain/game_editor.dart';
import '../../library/domain/runner_detection.dart';
import '../../library/presentation/widgets/detail_tabs/launch_tab.dart';
import '../widgets/slider_setting_tile/slider_setting_tile.dart';
import '../widgets/app_theme_mode_tile/app_theme_mode_tile.dart';
import 'appearance/widgets/app_theme_selector/app_theme_providers.dart';
import 'appearance/widgets/app_theme_selector/app_theme_selector.dart';
import 'appearance/widgets/is_true_black/is_true_black_tile.dart';

/// Opens a folder in the system file manager. Overridden in tests so no real
/// file manager ever opens.
final folderOpenerProvider =
    Provider<Future<bool> Function(Uri)>((ref) => launchUrl);

/// Picks a folder, rejecting Flatpak-portal paths with a toast.
Future<String?> pickFolderOrNull(WidgetRef ref, BuildContext context) async {
  final picked = await ref.read(pathPickerProvider)(
    mode: PathPickMode.folder,
  );
  if (picked == null || picked.isEmpty || !context.mounted) return null;
  if (isPortalPath(picked)) {
    Toast(context).show(portalPathMessage);
    return null;
  }
  return picked;
}

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
    final themeMode = ref.watch(appThemeModeProvider);
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
              const AppThemeModeTile(),
              const ThemeSelector(),
              Consumer(
                builder: (context, ref, _) {
                  final theme = ref.watch(appThemeKeyProvider);
                  return theme == AppTheme.custom
                      ? const CustomColorTile()
                      : const SizedBox.shrink();
                },
              ),
              if (themeMode != ThemeMode.light) const IsTrueBlackTile(),
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
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                child: Wrap(
                  spacing: 8,
                  children: [
                    OutlinedButton(
                      key: const Key('settings-open-data'),
                      onPressed: () =>
                          _openFolder(ref, context, dataDir.root),
                      child: const Text('Open data folder'),
                    ),
                    OutlinedButton(
                      key: const Key('settings-open-logs'),
                      onPressed: () =>
                          _openFolder(ref, context, dataDir.logs.path),
                      child: const Text('Open logs folder'),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                child: Text(
                  'Logs: one file per launch, plus latest.log',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                child: Text('Launching', style: headingStyle),
              ),
              const _DefaultModeTile(),
              _DefaultPrefixTile(),
              const _DefaultRunnerTile(),
              const _DefaultLocaleTile(),
              _DefaultUmuTile(),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openFolder(
      WidgetRef ref, BuildContext context, String path) async {
    try {
      // Synchronous so widget tests can use a real temp folder.
      Directory(path).createSync(recursive: true);
    } catch (_) {
      // Opening the folder still works when creating it failed.
    }
    try {
      final opened = await ref.read(folderOpenerProvider)(Uri.file(path));
      if (!opened && context.mounted) {
        Toast(context).showError('Could not open $path');
      }
    } catch (e) {
      if (context.mounted) {
        Toast(context).showError('Could not open folder: $e');
      }
    }
  }
}

class _DefaultModeTile extends ConsumerWidget {
  const _DefaultModeTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(launchModeProvider);
    return ListTile(
      title: const Text('Default mode'),
      trailing: DropdownButton<model.LaunchMode>(
        key: const Key('settings-default-mode'),
        value: mode,
        items: [
          for (final m in model.LaunchMode.values)
            DropdownMenuItem(value: m, child: Text(launchModeName(m))),
        ],
        onChanged: (value) {
          if (value != null) ref.read(launchModeProvider.notifier).set(value);
        },
      ),
    );
  }
}

class _DefaultPrefixTile extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefix = ref.watch(launchPrefixProvider);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Default prefix', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _PrefTextField(
                  key: const Key('settings-default-prefix'),
                  initial: prefix,
                  isPath: true,
                  onSave: (text) =>
                      ref.read(launchPrefixProvider.notifier).set(text),
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                key: const Key('settings-default-prefix-choose'),
                onPressed: () async {
                  final picked = await pickFolderOrNull(ref, context);
                  if (picked == null) return;
                  ref.read(launchPrefixProvider.notifier).set(picked);
                },
                child: const Text('Choose…'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

const String _settingsCustomKey = 'custom';

class _DefaultRunnerTile extends ConsumerStatefulWidget {
  const _DefaultRunnerTile();

  @override
  ConsumerState<_DefaultRunnerTile> createState() => _DefaultRunnerTileState();
}

class _DefaultRunnerTileState extends ConsumerState<_DefaultRunnerTile> {
  bool? _forceCustom;

  String _selected(String? stored, List<ProtonRunner> runners) {
    if (stored == null || stored.isEmpty) return '';
    if (runners.any((r) => r.path == stored)) return stored;
    return _settingsCustomKey;
  }

  @override
  Widget build(BuildContext context) {
    final stored = ref.watch(launchRunnerProvider);
    final runners = ref.watch(protonRunnersProvider).value ??
        const <ProtonRunner>[];
    final showCustom = _forceCustom ?? _selected(stored, runners) == 'custom';
    final set = ref.read(launchRunnerProvider.notifier).set;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Default Proton runner',
              style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 4),
          DropdownButton<String>(
            key: const Key('settings-default-runner'),
            value: showCustom ? _settingsCustomKey : _selected(stored, runners),
            isExpanded: true,
            items: [
              const DropdownMenuItem(value: '', child: Text('umu default')),
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
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _PrefTextField(
                    key: const Key('settings-default-runner-custom'),
                    initial: _selected(stored, runners) == _settingsCustomKey
                        ? (stored ?? '')
                        : '',
                    hint: 'umu default',
                    isPath: true,
                    onSave: (text) => set(text.isEmpty ? null : text),
                  ),
                ),
                const SizedBox(width: 8),
                TextButton(
                  key: const Key('settings-default-runner-choose'),
                  onPressed: () async {
                    final picked = await pickFolderOrNull(ref, context);
                    if (picked == null) return;
                    set(picked);
                  },
                  child: const Text('Choose…'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _DefaultLocaleTile extends ConsumerStatefulWidget {
  const _DefaultLocaleTile();

  @override
  ConsumerState<_DefaultLocaleTile> createState() => _DefaultLocaleTileState();
}

class _DefaultLocaleTileState extends ConsumerState<_DefaultLocaleTile> {
  bool? _forceCustom;

  String _selected(String stored) {
    if (stored.isEmpty || localePresets.contains(stored)) return stored;
    return _settingsCustomKey;
  }

  @override
  Widget build(BuildContext context) {
    final stored = ref.watch(launchLocaleProvider);
    final showCustom = _forceCustom ?? _selected(stored) == 'custom';
    final set = ref.read(launchLocaleProvider.notifier).set;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Default locale',
              style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 4),
          DropdownButton<String>(
            key: const Key('settings-default-locale'),
            value: showCustom ? _settingsCustomKey : _selected(stored),
            isExpanded: true,
            items: [
              const DropdownMenuItem(value: '', child: Text('System')),
              for (final preset in localePresets)
                DropdownMenuItem(value: preset, child: Text(preset)),
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
                set(value);
              }
            },
          ),
          if (showCustom) ...[
            const SizedBox(height: 8),
            _PrefTextField(
              key: const Key('settings-default-locale-custom'),
              initial:
                  _selected(stored) == _settingsCustomKey ? stored : '',
              hint: localeDisplay(stored),
              onSave: set,
            ),
          ],
        ],
      ),
    );
  }
}

class _DefaultUmuTile extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final umu = ref.watch(launchUmuGameIdProvider);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Default UMU id',
              style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 4),
          _PrefTextField(
            key: const Key('settings-default-umu'),
            initial: umu,
            onSave: (text) =>
                ref.read(launchUmuGameIdProvider.notifier).set(text),
          ),
        ],
      ),
    );
  }
}

/// A prefs text field that saves on blur or Enter and reverts on Esc.
class _PrefTextField extends ConsumerStatefulWidget {
  const _PrefTextField(
      {super.key,
      required this.initial,
      this.hint,
      this.isPath = false,
      required this.onSave});

  final String initial;
  final String? hint;
  final bool isPath;
  final void Function(String text) onSave;

  @override
  ConsumerState<_PrefTextField> createState() => _PrefTextFieldState();
}

class _PrefTextFieldState extends ConsumerState<_PrefTextField> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  String _focusValue = '';

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initial);
    _focusNode = FocusNode();
    _focusNode.addListener(_onFocus);
  }

  @override
  void didUpdateWidget(_PrefTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_focusNode.hasFocus &&
        oldWidget.initial != widget.initial &&
        _controller.text == oldWidget.initial) {
      _controller.text = widget.initial;
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocus);
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onFocus() {
    if (_focusNode.hasFocus) {
      _focusValue = _controller.text;
    } else {
      _submit();
    }
  }

  void _submit() {
    final text = _controller.text;
    if (text == _focusValue) return;
    _focusValue = text;
    if (widget.isPath && text.isNotEmpty && isPortalPath(text)) {
      if (mounted) {
        Toast(context).show(portalPathMessage);
        _controller.text = widget.initial;
        _focusValue = _controller.text;
      }
      return;
    }
    widget.onSave(text);
  }

  void _cancel() {
    _controller.text = _focusValue;
    _focusNode.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          _cancel();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: TextField(
        controller: _controller,
        focusNode: _focusNode,
        decoration: InputDecoration(
          hintText: widget.hint,
          isDense: true,
          border: const OutlineInputBorder(),
        ),
        onSubmitted: (_) => _submit(),
      ),
    );
  }
}
