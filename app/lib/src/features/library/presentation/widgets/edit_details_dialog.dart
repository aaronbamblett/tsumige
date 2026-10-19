// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../core/model.dart';
import '../../../../utils/theme/brand.dart';
import '../../../settings/presentation/sections/settings_widgets.dart';
import '../../domain/game_editor.dart';
import 'dialog_shell.dart';

const String _refreshNote =
    'Your values are kept when Tsumige refreshes data from VNDB.';

const String _releaseErrorText = 'Enter a valid release date.';

Future<void> showEditDetailsDialog(BuildContext context, Game game) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.5),
    builder: (context) => EditDetailsDialog(game: game),
  );
}

Size _dialogSize(BuildContext context) {
  final window = MediaQuery.sizeOf(context);
  return Size(
    math.min(560.0, window.width * 0.9),
    math.min(560.0, window.height * 0.9),
  );
}

class EditDetailsDialog extends ConsumerStatefulWidget {
  const EditDetailsDialog({super.key, required this.game});

  final Game game;

  @override
  ConsumerState<EditDetailsDialog> createState() => _EditDetailsDialogState();
}

class _EditDetailsDialogState extends ConsumerState<EditDetailsDialog> {
  late final TextEditingController _name;
  late final TextEditingController _originalTitle;
  late final TextEditingController _developers;
  late final TextEditingController _released;

  late final bool _hasVndb;
  late final String _heading;
  late final String _initialTitle;
  late final String? _initialOriginalTitle;
  late final String _initialOriginalTitleText;
  late final String? _initialReleased;
  late final String _initialReleasedText;
  late final List<Developer> _initialDevelopers;
  late final String _initialDevelopersText;
  late final List<Map<String, Object?>> _initialDevelopersJson;
  late final List<Developer> _originalDevelopers;
  late final Map<String, Object?> _originals;

  String? _releaseError;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final game = widget.game;
    _hasVndb = game.vndbId != null;
    _heading = game.title;
    _initialTitle = game.title;
    _initialOriginalTitle = game.vndbOriginalTitle;
    _initialOriginalTitleText = game.vndbOriginalTitle ?? '';
    _initialReleased = game.released;
    _initialReleasedText = game.released ?? '';
    _initialDevelopers = [...game.developers];
    _initialDevelopersText = _developerNames(_initialDevelopers);
    _initialDevelopersJson = _developersJson(_initialDevelopers);
    _originals = {...game.vndbOriginals};
    _originalDevelopers = _developersFromJson(_originals[vndbDevelopersKey]);
    _name = TextEditingController(text: game.title);
    _originalTitle = TextEditingController(text: _initialOriginalTitleText);
    _developers = TextEditingController(text: _initialDevelopersText);
    _released = TextEditingController(text: _initialReleasedText);
    _releaseError = _releaseErrorFor(_released.text);
    _name.addListener(_sync);
    _released.addListener(_sync);
  }

  @override
  void dispose() {
    _name.dispose();
    _originalTitle.dispose();
    _developers.dispose();
    _released.dispose();
    super.dispose();
  }

  void _sync() {
    if (!mounted) return;
    setState(() => _releaseError = _releaseErrorFor(_released.text));
  }

  String? _releaseErrorFor(String text) =>
      text == _initialReleasedText ? null : _validateRelease(text);

  void _close() {
    if (_saving) return;
    Navigator.of(context).pop();
  }

  bool get _canSave =>
      !_saving && _name.text.trim().isNotEmpty && _releaseError == null;

  Future<void> _save() async {
    setState(() => _saving = true);
    final title = _name.text.trim();
    final originalTitle = _nullIfEmpty(_originalTitle.text);
    final released = _nullIfEmpty(_released.text);
    await ref.read(gameEditorProvider).update(
      widget.game.id,
      (game) {
        if (_name.text != _initialTitle) {
          _write(game, vndbTitleKey, _initialTitle, title, () {
            game.title = title;
          });
        }
        if (_originalTitle.text != _initialOriginalTitleText) {
          _write(
            game,
            vndbOriginalTitleKey,
            _initialOriginalTitle,
            originalTitle,
            () => game.vndbOriginalTitle = originalTitle,
          );
        }
        if (_released.text != _initialReleasedText) {
          _write(game, vndbReleasedKey, _initialReleased, released, () {
            game.released = released;
          });
        }
        if (_developers.text != _initialDevelopersText) {
          final developers =
              _parseDevelopers(_developers.text, _initialDevelopers,
                  _originalDevelopers);
          _write(
            game,
            vndbDevelopersKey,
            _initialDevelopersJson,
            _developersJson(developers),
            () => game.developers = developers,
          );
        }
      },
      context: context,
    );
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  /// Stores VNDB's value before an edit replaces the field, then writes the
  /// field. A field equal to the stored VNDB value is no longer an edit.
  void _write(
    Game game,
    String key,
    Object? initial,
    Object? value,
    void Function() write,
  ) {
    if (game.vndbId != null) {
      if (!game.vndbOriginals.containsKey(key) && !_same(initial, value)) {
        game.vndbOriginals[key] = initial;
      }
      if (game.vndbOriginals.containsKey(key) &&
          _same(_normalized(key, game.vndbOriginals[key]),
              _normalized(key, value))) {
        game.vndbOriginals.remove(key);
      }
    }
    write();
  }

  void _useVndbValue(String key) {
    final original = _originals[key];
    switch (key) {
      case vndbTitleKey:
        _setText(_name, original is String ? original : '');
        break;
      case vndbOriginalTitleKey:
        _setText(_originalTitle, original is String ? original : '');
        break;
      case vndbReleasedKey:
        _setText(_released, original is String ? original : '');
        break;
      case vndbDevelopersKey:
        _setText(_developers, _developerNamesFromJson(original));
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DialogShell(
      frameKey: const Key('edit-details-frame'),
      size: _dialogSize(context),
      eyebrow: 'Edit…',
      title: _heading,
      onClose: _close,
      closeKey: const Key('edit-details-close'),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _field(
              context,
              label: 'Name',
              vndbKey: vndbTitleKey,
              fieldKey: const Key('edit-details-name'),
              controller: _name,
            ),
            const SizedBox(height: 14),
            _field(
              context,
              label: 'Original title',
              vndbKey: vndbOriginalTitleKey,
              fieldKey: const Key('edit-details-original-title'),
              controller: _originalTitle,
            ),
            const SizedBox(height: 14),
            _field(
              context,
              label: 'Developers',
              vndbKey: vndbDevelopersKey,
              fieldKey: const Key('edit-details-developers'),
              controller: _developers,
              hint: 'Comma-separated',
            ),
            const SizedBox(height: 14),
            _field(
              context,
              label: 'Release date',
              vndbKey: vndbReleasedKey,
              fieldKey: const Key('edit-details-released'),
              controller: _released,
              hint: 'year-month-day; month and day are optional',
            ),
            if (_releaseError != null) ...[
              const SizedBox(height: 6),
              Text(
                _releaseError!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.error,
                ),
              ),
            ],
            if (_hasVndb) ...[
              const SizedBox(height: 18),
              Text(
                _refreshNote,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
      footer: Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
        child: Row(
          children: [
            const Spacer(),
            BrandGlassButton(
              key: const Key('edit-details-cancel'),
              height: 40,
              expand: false,
              onPressed: _saving ? null : _close,
              label: const Text('Cancel'),
            ),
            const SizedBox(width: 10),
            BrandButton(
              key: const Key('edit-details-save'),
              height: 40,
              expand: false,
              onPressed: _canSave ? _save : null,
              label: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(
    BuildContext context, {
    required String label,
    required String vndbKey,
    required Key fieldKey,
    required TextEditingController controller,
    String? hint,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                fontSize: 11.5,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const Spacer(),
            if (_hasVndb && _originals.containsKey(vndbKey))
              TextButton(
                key: Key('use-vndb-$vndbKey'),
                style: TextButton.styleFrom(
                  foregroundColor: scheme.onSurfaceVariant,
                  minimumSize: const Size(0, 28),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  textStyle: const TextStyle(fontSize: 12.5),
                ),
                onPressed: _saving ? null : () => _useVndbValue(vndbKey),
                child: const Text('Use VNDB value'),
              ),
          ],
        ),
        const SizedBox(height: 6),
        SettingsTextField(key: fieldKey, controller: controller, hint: hint),
      ],
    );
  }
}

void _setText(TextEditingController controller, String text) {
  controller.value = TextEditingValue(
    text: text,
    selection: TextSelection.collapsed(offset: text.length),
  );
}

String? _nullIfEmpty(String text) {
  final trimmed = text.trim();
  return trimmed.isEmpty ? null : trimmed;
}

bool _same(Object? a, Object? b) => jsonEncode(a) == jsonEncode(b);

/// Developer lists compare by their fields, not by which optional keys the
/// stored JSON happened to include.
Object? _normalized(String key, Object? value) {
  if (key != vndbDevelopersKey) return value;
  return _developersJson(_developersFromJson(value));
}

List<Developer> _developersFromJson(Object? raw) => [
      if (raw is List)
        for (final entry in raw)
          if (entry is Map && entry['id'] is String) Developer.fromJson(entry),
    ];

String _developerNames(List<Developer> developers) => [
  for (final developer in developers)
    if (developer.name.trim().isNotEmpty) developer.name.trim(),
].join(', ');

String _developerNamesFromJson(Object? raw) => [
  if (raw is List)
    for (final entry in raw)
      if (entry is Map && entry['name'] is String)
        if ((entry['name'] as String).trim().isNotEmpty)
          (entry['name'] as String).trim(),
].join(', ');

List<Map<String, Object?>> _developersJson(List<Developer> developers) => [
  for (final developer in developers) developer.toJson(),
];

/// Comma-separated names. A name that matches VNDB's developers or one of the
/// game's own keeps that developer's VNDB id; a new name gets no VNDB id.
List<Developer> _parseDevelopers(
    String raw, List<Developer> existing, List<Developer> vndb) {
  final byName = <String, Developer>{};
  for (final developer in [...vndb, ...existing]) {
    final name = developer.name.trim();
    if (name.isNotEmpty) {
      byName.putIfAbsent(name.toLowerCase(), () => developer);
    }
  }
  final seen = <String>{};
  final out = <Developer>[];
  for (final part in raw.split(',')) {
    final name = part.trim();
    if (name.isEmpty || !seen.add(name.toLowerCase())) continue;
    out.add(byName[name.toLowerCase()] ?? Developer(id: '', name: name));
  }
  return out;
}

/// Accepts `YYYY`, `YYYY-MM` and `YYYY-MM-DD`, with a real month and day,
/// plus `TBA`, which VNDB uses for an unspecified future date.
String? _validateRelease(String raw) {
  final text = raw.trim();
  if (text.isEmpty || text == 'TBA') return null;
  final match = RegExp(r'^(\d{4})(?:-(\d{2})(?:-(\d{2}))?)?$').firstMatch(text);
  if (match == null) return _releaseErrorText;
  final month = match.group(2);
  if (month == null) return null;
  final monthNumber = int.parse(month);
  if (monthNumber < 1 || monthNumber > 12) return _releaseErrorText;
  final day = match.group(3);
  if (day == null) return null;
  final year = int.parse(match.group(1)!);
  final lastDay = DateTime.utc(year, monthNumber + 1, 0).day;
  final dayNumber = int.parse(day);
  if (dayNumber < 1 || dayNumber > lastDay) return _releaseErrorText;
  return null;
}
