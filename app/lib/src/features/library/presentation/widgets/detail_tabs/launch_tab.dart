// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../../../core/launch/args.dart';
import '../../../../../core/launch/detect.dart';
import '../../../../../core/launch/env.dart';
import '../../../../../core/model.dart';
import '../../../../../utils/prefs/app_prefs.dart';
import '../../../../../utils/theme/brand.dart';
import '../../../../../utils/toast.dart';
import '../../../../settings/presentation/sections/settings_widgets.dart';
import '../../../domain/game_editor.dart';
import '../../../domain/runner_detection.dart';
import '../library_toolbar.dart';
import 'info_tab.dart';

String launchModeName(LaunchMode mode) => switch (mode) {
  LaunchMode.proton => 'Proton',
  LaunchMode.wine => 'Wine',
  LaunchMode.native => 'Native',
  LaunchMode.steam => 'Steam',
};

/// Modes offered by the Mode control. Platform detection will narrow this.
final availableLaunchModesProvider = Provider<List<LaunchMode>>(
  (ref) => LaunchMode.values,
);

String localeDisplay(String locale) => locale.isEmpty ? 'System' : locale;

Widget launchFieldLabel(BuildContext context, String label, bool isDefault) {
  final scheme = Theme.of(context).colorScheme;
  final style = Theme.of(context).textTheme.labelSmall
      ?.copyWith(fontSize: 11.5, color: scheme.onSurfaceVariant);
  return Row(
    children: [
      Text(label, style: style),
      const Spacer(),
      if (isDefault)
        Text('Default', style: style?.copyWith(color: scheme.outline)),
    ],
  );
}

List<Widget> _spaced(List<Widget> fields) => [
  for (var i = 0; i < fields.length; i++) ...[
    if (i > 0) const SizedBox(height: 14),
    fields[i],
  ],
];

class LaunchTab extends ConsumerStatefulWidget {
  const LaunchTab({super.key, required this.game});

  final Game game;

  @override
  ConsumerState<LaunchTab> createState() => _LaunchTabState();
}

class _LaunchTabState extends ConsumerState<LaunchTab> {
  bool _advancedOpen = false;

  @override
  Widget build(BuildContext context) {
    final game = widget.game;
    final defaultPrefix = ref.watch(launchPrefixProvider);
    final defaultRunner = ref.watch(launchRunnerProvider);
    final defaultLocale = ref.watch(launchLocaleProvider);
    final defaultUmu = ref.watch(launchUmuGameIdProvider);
    final mode = game.launch.mode ?? LaunchMode.proton;
    final wines = ref.watch(wineRunnersProvider).value ?? const <WineRunner>[];
    final protons =
        ref.watch(protonRunnersProvider).value ?? const <ProtonRunner>[];
    final prefixes =
        ref.watch(steamPrefixesProvider).value ?? const <SteamPrefix>[];
    final steam = mode == LaunchMode.steam;
    final runnerMode = mode == LaunchMode.wine || mode == LaunchMode.proton;
    final modeFields = <Widget>[
      if (runnerMode)
        mode == LaunchMode.wine
            ? _WineRunnerField(
                game: game,
                runners: wines,
                defaultRunner: defaultRunner,
              )
            : _ProtonRunnerField(
                game: game,
                runners: protons,
                defaultRunner: defaultRunner,
              ),
      if (runnerMode)
        _PrefixField(
          game: game,
          prefixes: prefixes,
          defaultPrefix: defaultPrefix,
        ),
      if (runnerMode) _LocaleField(game: game, defaultLocale: defaultLocale),
    ];
    final advancedFields = <Widget>[
      if (runnerMode) _UmuField(game: game, defaultUmu: defaultUmu),
      if (!steam) _ArgumentsField(game: game),
      if (!steam) _EnvironmentField(game: game),
    ];
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ..._spaced([
            _ModeField(game: game, mode: mode),
            steam
                ? _SteamAppIdField(gameId: game.id, initial: game.launch)
                : _ExecutableField(game: game, defaultExecutable: null),
          ]),
          if (modeFields.isNotEmpty) ...[
            detailSectionDivider(context),
            DetailSection(
              label: launchModeName(mode),
              actions: [
                _HeadingAction(
                  key: const Key('launch-rescan'),
                  leading: Icons.refresh_rounded,
                  label: 'Rescan',
                  onTap: () {
                    ref.invalidate(wineRunnersProvider);
                    ref.invalidate(protonRunnersProvider);
                    ref.invalidate(steamPrefixesProvider);
                  },
                ),
              ],
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: _spaced(modeFields),
              ),
            ),
          ],
          if (advancedFields.isNotEmpty) ...[
            detailSectionDivider(context),
            DetailSection(
              label: 'Advanced',
              actions: [
                _HeadingAction(
                  key: const Key('launch-advanced-toggle'),
                  label: _advancedOpen ? 'Hide' : 'Show',
                  trailing: _advancedOpen
                      ? Icons.expand_less_rounded
                      : Icons.expand_more_rounded,
                  onTap: () => setState(() => _advancedOpen = !_advancedOpen),
                ),
              ],
              child: _advancedOpen
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: _spaced(advancedFields),
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ],
      ),
    );
  }
}

class _ModeField extends ConsumerWidget {
  const _ModeField({required this.game, required this.mode});

  final Game game;
  final LaunchMode mode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        launchFieldLabel(context, 'Mode', game.launch.mode == null),
        const SizedBox(height: 6),
        LaunchModeSegment(
          key: const Key('launch-mode'),
          mode: mode,
          onChanged: (picked) => ref
              .read(gameEditorProvider)
              .update(game.id, (g) => g.launch.mode = picked),
        ),
      ],
    );
  }
}

/// The launch modes as a segmented control. A mode outside the available
/// list still shows, selected, so a stored value is never hidden.
class LaunchModeSegment extends ConsumerWidget {
  const LaunchModeSegment({
    super.key,
    required this.mode,
    required this.onChanged,
  });

  final LaunchMode mode;
  final ValueChanged<LaunchMode> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final modes = [...ref.watch(availableLaunchModesProvider)];
    if (!modes.contains(mode)) modes.add(mode);
    return ToolbarBox(
      key: key,
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: Row(
          children: [
            for (final option in modes)
              Expanded(
                child: ToolbarSegment(
                  key: Key('mode-${option.name}'),
                  label: launchModeName(option),
                  selected: option == mode,
                  onTap: () => onChanged(option),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Muted icon-and-text action in a section heading.
class _HeadingAction extends StatelessWidget {
  const _HeadingAction({
    super.key,
    required this.label,
    required this.onTap,
    this.leading,
    this.trailing,
  });

  final String label;
  final VoidCallback onTap;
  final IconData? leading;
  final IconData? trailing;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = scheme.onSurfaceVariant;
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (leading != null) ...[
              Icon(leading, size: 16, color: color),
              const SizedBox(width: 4),
            ],
            Text(label, style: TextStyle(fontSize: 12.5, color: color)),
            if (trailing != null) Icon(trailing, size: 18, color: color),
          ],
        ),
      ),
    );
  }
}

/// A nullable text field that saves on blur or Enter, reverts on Esc, and
/// saves a pending edit to the captured game even when unmounted by a game
/// switch. Clearing the field saves through [onSave] with empty text so the
/// caller can fall back to null.
class _LaunchTextField extends ConsumerStatefulWidget {
  const _LaunchTextField({
    super.key,
    required this.gameId,
    this.label,
    required this.initial,
    this.hint,
    this.isDefault = false,
    this.minLines = 1,
    this.maxLines = 1,
    this.keyboardType,
    this.isPath = false,
    this.validate,
    this.footerBuilder,
    required this.onSave,
  });

  final String gameId;
  final String? label;
  final String initial;
  final String? hint;
  final bool isDefault;
  final int minLines;
  final int? maxLines;
  final TextInputType? keyboardType;
  final bool isPath;
  final String? Function(String text)? validate;
  final Widget Function(BuildContext context, String text)? footerBuilder;
  final void Function(GameEditor editor, String gameId, String text) onSave;

  @override
  ConsumerState<_LaunchTextField> createState() => _LaunchTextFieldState();
}

class _LaunchTextFieldState extends ConsumerState<_LaunchTextField> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  late GameEditor _editor;
  String? _error;
  String? _editGameId;
  String _focusValue = '';
  bool _cancelled = false;
  bool _focused = false;

  bool get _singleLine => (widget.maxLines ?? 1) == 1;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initial);
    _editor = ref.read(gameEditorProvider);
    _focusNode = FocusNode();
    _focusNode.addListener(_onFocus);
    _controller.addListener(_onTextChanged);
  }

  @override
  void didUpdateWidget(_LaunchTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_focusNode.hasFocus &&
        oldWidget.initial != widget.initial &&
        _controller.text == oldWidget.initial) {
      _controller.text = widget.initial;
      _error = null;
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocus);
    _controller.removeListener(_onTextChanged);
    // A game switch keeps this state alive (same keys), so the focus-loss
    // path saves to the captured game. This backstop only covers unmounts
    // such as closing the pane. Invalid and portal paths never save.
    if (_editGameId != null && !_cancelled && _controller.text != _focusValue) {
      final text = _controller.text;
      if (widget.validate?.call(text) == null &&
          !(widget.isPath && text.isNotEmpty && isPortalPath(text))) {
        widget.onSave(_editor, _editGameId!, text);
      }
    }
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    if (mounted) setState(() {});
  }

  void _onFocus() {
    setState(() => _focused = _focusNode.hasFocus);
    if (_focusNode.hasFocus) {
      _editGameId = widget.gameId;
      _focusValue = _controller.text;
      _cancelled = false;
    } else {
      _submit();
    }
  }

  void _submit() {
    final text = _controller.text;
    final problem = widget.validate?.call(text);
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    setState(() => _error = null);
    if (text == _focusValue) return;
    _focusValue = text;
    _saveTo(_editGameId ?? widget.gameId, text);
  }

  void _saveTo(String gameId, String text) {
    if (widget.isPath && text.isNotEmpty && isPortalPath(text)) {
      if (mounted) {
        Toast(context).show(portalPathMessage);
        _controller.text = _focusValue;
      }
      return;
    }
    widget.onSave(_editor, gameId, text);
  }

  void _cancel() {
    setState(() {
      _cancelled = true;
      _error = null;
      _controller.text = _focusValue;
    });
    _focusNode.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final field = TextField(
      controller: _controller,
      focusNode: _focusNode,
      minLines: widget.minLines,
      maxLines: widget.maxLines,
      keyboardType: widget.keyboardType,
      style: theme.textTheme.bodyMedium,
      decoration:
          settingsInputDecoration(
            context,
            hint: widget.hint,
            contentPadding: _singleLine ? null : const EdgeInsets.all(10),
          ).copyWith(
            constraints: _singleLine
                ? null
                : const BoxConstraints(minHeight: 72),
          ),
      onSubmitted: _singleLine ? (_) => _submit() : null,
    );
    final control = widget.isPath && _singleLine
        ? SizedBox(
            height: 40,
            child: Stack(
              fit: StackFit.expand,
              children: [
                field,
                if (!_focused && _controller.text.isNotEmpty)
                  MiddleEllipsisValue(text: _controller.text),
              ],
            ),
          )
        : field;
    final footer = widget.footerBuilder?.call(context, _controller.text);
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        control,
        if (_error != null) ...[
          const SizedBox(height: 4),
          Text(
            _error!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
        ],
        if (footer != null) ...[const SizedBox(height: 4), footer],
      ],
    );
    final wrapped = Focus(
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          _cancel();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: body,
    );
    if (widget.label == null) return wrapped;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        launchFieldLabel(context, widget.label!, widget.isDefault),
        const SizedBox(height: 6),
        wrapped,
      ],
    );
  }
}

class _ExecutableField extends ConsumerWidget {
  const _ExecutableField({required this.game, required this.defaultExecutable});

  final Game game;
  final String? defaultExecutable;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        launchFieldLabel(context, 'Executable', false),
        const SizedBox(height: 6),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _LaunchTextField(
                key: const Key('launch-executable'),
                gameId: game.id,
                initial: game.launch.executable ?? '',
                hint: defaultExecutable,
                isPath: true,
                onSave: (editor, id, text) => editor.update(
                  id,
                  (g) => g.launch.executable = text.isEmpty ? null : text,
                ),
              ),
            ),
            const SizedBox(width: 8),
            BrandGlassButton(
              key: const Key('launch-executable-choose'),
              height: 40,
              expand: false,
              onPressed: () => _choose(context, ref),
              label: const Text('Choose…'),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _choose(BuildContext context, WidgetRef ref) async {
    final current = game.launch.executable;
    final picked = await ref.read(pathPickerProvider)(
      initialDirectory: current != null && current.isNotEmpty
          ? p.dirname(current)
          : null,
      mode: PathPickMode.file,
    );
    if (picked == null || picked.isEmpty || !context.mounted) return;
    if (isPortalPath(picked)) {
      Toast(context).show(portalPathMessage);
      return;
    }
    await ref
        .read(gameEditorProvider)
        .update(game.id, (g) => g.launch.executable = picked);
  }
}

const String _defaultKey = 'default';
const String _customKey = 'custom';

class _WineRunnerField extends ConsumerStatefulWidget {
  const _WineRunnerField({
    required this.game,
    required this.runners,
    required this.defaultRunner,
  });

  final Game game;
  final List<WineRunner> runners;
  final String? defaultRunner;

  @override
  ConsumerState<_WineRunnerField> createState() => _WineRunnerFieldState();
}

class _WineRunnerFieldState extends ConsumerState<_WineRunnerField> {
  bool? _forceCustom;

  String _selected() {
    final stored = widget.game.launch.runner;
    if (stored == null || stored.isEmpty) return _defaultKey;
    if (widget.runners.any((r) => r.binary == stored)) return stored;
    return _customKey;
  }

  bool get _showCustom => _forceCustom ?? _selected() == _customKey;

  @override
  void didUpdateWidget(_WineRunnerField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.game.id != widget.game.id) _forceCustom = null;
  }

  @override
  Widget build(BuildContext context) {
    final stored = widget.game.launch.runner;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        launchFieldLabel(context, 'Runner', stored == null),
        const SizedBox(height: 6),
        SettingsDropdown<String>(
          key: const Key('launch-runner'),
          value: _showCustom ? _customKey : _selected(),
          items: [
            const DropdownMenuItem(
              value: _defaultKey,
              child: Text('Default (wine on PATH)'),
            ),
            for (final runner in widget.runners)
              DropdownMenuItem(
                value: runner.binary,
                child: Text('${runner.name} (${runner.source})'),
              ),
            const DropdownMenuItem(value: _customKey, child: Text('Custom…')),
          ],
          onChanged: (value) {
            if (value == null) return;
            if (value == _defaultKey) {
              setState(() => _forceCustom = false);
              ref
                  .read(gameEditorProvider)
                  .update(widget.game.id, (g) => g.launch.runner = null);
            } else if (value == _customKey) {
              setState(() => _forceCustom = true);
            } else {
              setState(() => _forceCustom = false);
              ref
                  .read(gameEditorProvider)
                  .update(widget.game.id, (g) => g.launch.runner = value);
            }
          },
        ),
        if (_showCustom) ...[
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _LaunchTextField(
                  key: const Key('launch-runner-custom'),
                  gameId: widget.game.id,
                  initial: _selected() == _customKey ? (stored ?? '') : '',
                  hint: widget.defaultRunner ?? 'umu default',
                  isPath: true,
                  onSave: (editor, id, text) =>
                      editor.update(id, (g) => g.launch.runner = text),
                ),
              ),
              const SizedBox(width: 8),
              BrandGlassButton(
                key: const Key('launch-runner-choose'),
                height: 40,
                expand: false,
                onPressed: () => _choose(context, ref),
                label: const Text('Choose…'),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Future<void> _choose(BuildContext context, WidgetRef ref) async {
    final stored = widget.game.launch.runner;
    final picked = await ref.read(pathPickerProvider)(
      initialDirectory: stored != null && stored.isNotEmpty
          ? p.dirname(stored)
          : null,
      mode: PathPickMode.file,
    );
    if (picked == null || picked.isEmpty || !context.mounted) return;
    if (isPortalPath(picked)) {
      Toast(context).show(portalPathMessage);
      return;
    }
    await ref
        .read(gameEditorProvider)
        .update(widget.game.id, (g) => g.launch.runner = picked);
  }
}

class _ProtonRunnerField extends ConsumerStatefulWidget {
  const _ProtonRunnerField({
    required this.game,
    required this.runners,
    required this.defaultRunner,
  });

  final Game game;
  final List<ProtonRunner> runners;
  final String? defaultRunner;

  @override
  ConsumerState<_ProtonRunnerField> createState() => _ProtonRunnerFieldState();
}

class _ProtonRunnerFieldState extends ConsumerState<_ProtonRunnerField> {
  bool? _forceCustom;

  String _selected() {
    final stored = widget.game.launch.runner;
    if (stored == null || stored.isEmpty) return _defaultKey;
    if (widget.runners.any((r) => r.path == stored)) return stored;
    return _customKey;
  }

  bool get _showCustom => _forceCustom ?? _selected() == _customKey;

  @override
  void didUpdateWidget(_ProtonRunnerField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.game.id != widget.game.id) _forceCustom = null;
  }

  @override
  Widget build(BuildContext context) {
    final stored = widget.game.launch.runner;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        launchFieldLabel(context, 'Runner', stored == null),
        const SizedBox(height: 6),
        SettingsDropdown<String>(
          key: const Key('launch-runner'),
          value: _showCustom ? _customKey : _selected(),
          items: [
            const DropdownMenuItem(
              value: _defaultKey,
              child: Text('umu default'),
            ),
            for (final runner in widget.runners)
              DropdownMenuItem(value: runner.path, child: Text(runner.name)),
            const DropdownMenuItem(value: _customKey, child: Text('Custom…')),
          ],
          onChanged: (value) {
            if (value == null) return;
            if (value == _defaultKey) {
              setState(() => _forceCustom = false);
              ref
                  .read(gameEditorProvider)
                  .update(widget.game.id, (g) => g.launch.runner = null);
            } else if (value == _customKey) {
              setState(() => _forceCustom = true);
            } else {
              setState(() => _forceCustom = false);
              ref
                  .read(gameEditorProvider)
                  .update(widget.game.id, (g) => g.launch.runner = value);
            }
          },
        ),
        if (_showCustom) ...[
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _LaunchTextField(
                  key: const Key('launch-runner-custom'),
                  gameId: widget.game.id,
                  initial: _selected() == _customKey ? (stored ?? '') : '',
                  hint: widget.defaultRunner ?? 'umu default',
                  isPath: true,
                  onSave: (editor, id, text) =>
                      editor.update(id, (g) => g.launch.runner = text),
                ),
              ),
              const SizedBox(width: 8),
              BrandGlassButton(
                key: const Key('launch-runner-choose'),
                height: 40,
                expand: false,
                onPressed: () => _choose(context, ref),
                label: const Text('Choose…'),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Future<void> _choose(BuildContext context, WidgetRef ref) async {
    final picked = await ref.read(pathPickerProvider)(
      mode: PathPickMode.folder,
    );
    if (picked == null || picked.isEmpty || !context.mounted) return;
    if (isPortalPath(picked)) {
      Toast(context).show(portalPathMessage);
      return;
    }
    await ref
        .read(gameEditorProvider)
        .update(widget.game.id, (g) => g.launch.runner = picked);
  }
}

class _PrefixField extends ConsumerStatefulWidget {
  const _PrefixField({
    required this.game,
    required this.prefixes,
    required this.defaultPrefix,
  });

  final Game game;
  final List<SteamPrefix> prefixes;
  final String defaultPrefix;

  @override
  ConsumerState<_PrefixField> createState() => _PrefixFieldState();
}

class _PrefixFieldState extends ConsumerState<_PrefixField> {
  bool? _forceCustom;

  String _selected() {
    final stored = widget.game.launch.prefix;
    if (stored == null || stored.isEmpty) return _defaultKey;
    if (widget.prefixes.any((prefix) => prefix.path == stored)) {
      return stored;
    }
    return _customKey;
  }

  bool get _showCustom => _forceCustom ?? _selected() == _customKey;

  @override
  void didUpdateWidget(_PrefixField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.game.id != widget.game.id) _forceCustom = null;
  }

  @override
  Widget build(BuildContext context) {
    final stored = widget.game.launch.prefix;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        launchFieldLabel(context, 'Prefix', stored == null),
        const SizedBox(height: 6),
        SettingsDropdown<String>(
          key: const Key('launch-prefix'),
          value: _showCustom ? _customKey : _selected(),
          items: [
            DropdownMenuItem(
              value: _defaultKey,
              child: Text('Default (${widget.defaultPrefix})'),
            ),
            for (final prefix in widget.prefixes)
              DropdownMenuItem(
                value: prefix.path,
                child: Text(
                  '${prefix.gameName ?? 'App ${prefix.appId}'} (${prefix.appId})',
                ),
              ),
            const DropdownMenuItem(value: _customKey, child: Text('Custom…')),
          ],
          onChanged: (value) {
            if (value == null) return;
            if (value == _defaultKey) {
              setState(() => _forceCustom = false);
              ref
                  .read(gameEditorProvider)
                  .update(widget.game.id, (g) => g.launch.prefix = null);
            } else if (value == _customKey) {
              setState(() => _forceCustom = true);
            } else {
              setState(() => _forceCustom = false);
              ref
                  .read(gameEditorProvider)
                  .update(widget.game.id, (g) => g.launch.prefix = value);
            }
          },
        ),
        if (_showCustom) ...[
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _LaunchTextField(
                  key: const Key('launch-prefix-custom'),
                  gameId: widget.game.id,
                  initial: _selected() == _customKey ? (stored ?? '') : '',
                  hint: widget.defaultPrefix,
                  isPath: true,
                  onSave: (editor, id, text) =>
                      editor.update(id, (g) => g.launch.prefix = text),
                ),
              ),
              const SizedBox(width: 8),
              BrandGlassButton(
                key: const Key('launch-prefix-choose'),
                height: 40,
                expand: false,
                onPressed: () => _choose(context, ref),
                label: const Text('Choose…'),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Future<void> _choose(BuildContext context, WidgetRef ref) async {
    final picked = await ref.read(pathPickerProvider)(
      mode: PathPickMode.folder,
    );
    if (picked == null || picked.isEmpty || !context.mounted) return;
    if (isPortalPath(picked)) {
      Toast(context).show(portalPathMessage);
      return;
    }
    await ref
        .read(gameEditorProvider)
        .update(widget.game.id, (g) => g.launch.prefix = picked);
  }
}

class _LocaleField extends ConsumerStatefulWidget {
  const _LocaleField({required this.game, required this.defaultLocale});

  final Game game;
  final String defaultLocale;

  @override
  ConsumerState<_LocaleField> createState() => _LocaleFieldState();
}

class _LocaleFieldState extends ConsumerState<_LocaleField> {
  bool? _forceCustom;

  String? _selected() {
    final stored = widget.game.launch.locale;
    if (stored == null) return null;
    if (stored.isEmpty || localePresets.contains(stored)) return stored;
    return _customKey;
  }

  bool get _showCustom => _forceCustom ?? _selected() == _customKey;

  @override
  void didUpdateWidget(_LocaleField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.game.id != widget.game.id) _forceCustom = null;
  }

  @override
  Widget build(BuildContext context) {
    final stored = widget.game.launch.locale;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        launchFieldLabel(context, 'Locale', stored == null),
        const SizedBox(height: 6),
        SettingsDropdown<String>(
          key: const Key('launch-locale'),
          value: _showCustom ? _customKey : _selected(),
          hint: Text(localeDisplay(widget.defaultLocale)),
          items: [
            const DropdownMenuItem(value: '', child: Text('System')),
            for (final preset in localePresets)
              DropdownMenuItem(value: preset, child: Text(preset)),
            const DropdownMenuItem(value: _customKey, child: Text('Custom…')),
          ],
          onChanged: (value) {
            if (value == null) return;
            if (value == _customKey) {
              setState(() => _forceCustom = true);
            } else {
              setState(() => _forceCustom = false);
              ref
                  .read(gameEditorProvider)
                  .update(widget.game.id, (g) => g.launch.locale = value);
            }
          },
        ),
        if (_showCustom) ...[
          const SizedBox(height: 8),
          _LaunchTextField(
            key: const Key('launch-locale-custom'),
            gameId: widget.game.id,
            initial: _selected() == _customKey ? (stored ?? '') : '',
            hint: localeDisplay(widget.defaultLocale),
            onSave: (editor, id, text) => editor.update(
              id,
              // A blank custom locale means the system locale.
              (g) => g.launch.locale = text.isEmpty ? '' : text,
            ),
          ),
        ],
      ],
    );
  }
}

class _UmuField extends ConsumerWidget {
  const _UmuField({required this.game, required this.defaultUmu});

  final Game game;
  final String defaultUmu;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _LaunchTextField(
      key: const Key('launch-umu'),
      gameId: game.id,
      label: 'UMU game id',
      initial: game.launch.umuGameId ?? '',
      hint: defaultUmu,
      isDefault: game.launch.umuGameId == null,
      onSave: (editor, id, text) => editor.update(
        id,
        (g) => g.launch.umuGameId = text.isEmpty ? null : text,
      ),
    );
  }
}

class _SteamAppIdField extends ConsumerWidget {
  const _SteamAppIdField({required this.gameId, required this.initial});

  final String gameId;
  final LaunchOverrides initial;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _LaunchTextField(
      key: const Key('launch-steam-app-id'),
      gameId: gameId,
      label: 'Steam app id',
      initial: initial.steamAppId?.toString() ?? '',
      keyboardType: TextInputType.number,
      validate: (text) {
        if (text.isEmpty) return null;
        if (RegExp(r'^\d+$').hasMatch(text)) return null;
        return 'Steam App ID must be digits.';
      },
      onSave: (editor, id, text) => editor.update(
        id,
        (g) => g.launch.steamAppId = text.isEmpty ? null : int.parse(text),
      ),
    );
  }
}

class _ArgumentsField extends ConsumerWidget {
  const _ArgumentsField({required this.game});

  final Game game;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return _LaunchTextField(
      key: const Key('launch-arguments'),
      gameId: game.id,
      label: 'Arguments',
      initial: game.launch.arguments ?? '',
      validate: (text) {
        try {
          splitArgs(text);
        } on FormatException catch (e) {
          return e.message;
        }
        return null;
      },
      footerBuilder: (context, text) {
        try {
          final count = splitArgs(text).length;
          return Text(
            'Splits into $count argument${count == 1 ? '' : 's'}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          );
        } on FormatException catch (e) {
          return Text(
            e.message,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
            ),
          );
        }
      },
      onSave: (editor, id, text) => editor.update(
        id,
        (g) => g.launch.arguments = text.isEmpty ? null : text,
      ),
    );
  }
}

class _EnvironmentField extends ConsumerWidget {
  const _EnvironmentField({required this.game});

  final Game game;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _LaunchTextField(
      key: const Key('launch-environment'),
      gameId: game.id,
      label: 'Environment',
      initial: game.launch.environment ?? '',
      minLines: 3,
      maxLines: null,
      validate: (text) {
        try {
          parseEnv(text);
        } on FormatException catch (e) {
          return e.message;
        }
        return null;
      },
      onSave: (editor, id, text) => editor.update(
        id,
        (g) => g.launch.environment = text.isEmpty ? null : text,
      ),
    );
  }
}
