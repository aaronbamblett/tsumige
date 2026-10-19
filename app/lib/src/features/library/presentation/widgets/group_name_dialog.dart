// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../core/group_detection.dart';
import '../../../../core/groups.dart';
import '../../../../utils/theme/brand.dart';
import '../../../settings/presentation/sections/settings_widgets.dart';
import '../../data/library_repository.dart';
import 'dialog_shell.dart';

/// Small name prompt in the app's dialog shell, shared by Combine and Rename:
/// an eyebrow, a title, one `Name` field, and `Cancel` plus a confirm button.
/// Returns the trimmed name, or null on cancel.
Future<String?> showGroupNameDialog({
  required BuildContext context,
  required String eyebrow,
  required String title,
  required String initialName,
  required String confirmLabel,
  required bool Function(String name) canConfirm,
}) {
  return showDialog<String>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.5),
    builder: (context) => GroupNameDialog(
      eyebrow: eyebrow,
      title: title,
      initialName: initialName,
      confirmLabel: confirmLabel,
      canConfirm: canConfirm,
    ),
  );
}

/// The default Combine name for [titles]: when every title carries a part
/// marker and the series text before it matches, that text (`9-nine-
/// Episode 1..3` gives `9-nine-`); otherwise the shared title prefix with
/// trailing spaces, hyphens and colons trimmed, else the first title.
String combineDefaultName(List<String> titles) {
  if (titles.isEmpty) return '';
  final series = [for (final title in titles) seriesPrefixOf(title)];
  if (series.every((s) => s != null) &&
      series.every((s) => s!.key == series.first!.key)) {
    return series.first!.prefix;
  }
  final prefix =
      sharedTitlePrefix(titles).replaceAll(RegExp(r'[\s\-:]+$'), '');
  return prefix.isEmpty ? titles.first : prefix;
}

/// The Combine prompt: `Name` starts with the members' shared title prefix
/// (word-boundary trimmed, then trailing ` -:` trimmed), else the first
/// title. Selected groups count through their members. Confirm stays disabled
/// with fewer than 2 resulting games or an empty name.
Future<String?> showCombineDialog(
  BuildContext context,
  List<String> tileIds,
) {
  final library =
      ProviderScope.containerOf(context).read(libraryProvider).value?.library;
  final byId = {for (final g in library?.games ?? const []) g.id: g};
  final groupsById = {for (final g in library?.groups ?? const []) g.id: g};
  final titles = <String>[];
  final seen = <String>{};
  void addGame(String id) {
    final game = byId[id];
    if (game != null && seen.add(game.id)) titles.add(game.title);
  }

  for (final id in tileIds) {
    final group = groupsById[id];
    if (group != null) {
      for (final memberId in group.memberIds) {
        addGame(memberId);
      }
    } else {
      addGame(id);
    }
  }
  final gameCount = titles.length;
  return showGroupNameDialog(
    context: context,
    eyebrow: 'Group',
    title: 'Group games',
    initialName: combineDefaultName(titles),
    confirmLabel: 'Group',
    canConfirm: (name) => name.trim().isNotEmpty && gameCount >= 2,
  );
}

Size _dialogSize(BuildContext context) {
  final window = MediaQuery.sizeOf(context);
  return Size(
    math.min(480.0, window.width * 0.9),
    math.min(300.0, window.height * 0.9),
  );
}

class GroupNameDialog extends StatefulWidget {
  const GroupNameDialog({
    super.key,
    required this.eyebrow,
    required this.title,
    required this.initialName,
    required this.confirmLabel,
    required this.canConfirm,
  });

  final String eyebrow;
  final String title;
  final String initialName;
  final String confirmLabel;
  final bool Function(String name) canConfirm;

  @override
  State<GroupNameDialog> createState() => _GroupNameDialogState();
}

class _GroupNameDialogState extends State<GroupNameDialog> {
  late final TextEditingController _name = TextEditingController(
    text: widget.initialName,
  );
  late final FocusNode _focus = FocusNode();
  ModalRoute<dynamic>? _route;
  late bool _canConfirm = widget.canConfirm(widget.initialName);

  @override
  void initState() {
    super.initState();
    _name.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _name.text.length,
    );
    _name.addListener(() {
      final next = widget.canConfirm(_name.text);
      if (next != _canConfirm) setState(() => _canConfirm = next);
    });
    FocusManager.instance.addListener(_reclaimFieldFocus);
    WidgetsBinding.instance.addPostFrameCallback((_) => _reclaimFieldFocus());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _route ??= ModalRoute.of(context);
  }

  /// Keeps the field focused while the dialog opens: route transitions (the
  /// dialog's own, or a closing menu under it) park focus on the dialog
  /// frame, an ancestor of the field. Reclaim only from such scaffolding,
  /// never from a sibling control the user moved to.
  void _reclaimFieldFocus() {
    if (!mounted || _focus.hasFocus) return;
    if (_route != null && !_route!.isCurrent) return;
    final primary = FocusManager.instance.primaryFocus;
    if (primary == null || !_focus.ancestors.contains(primary)) return;
    _focus.requestFocus();
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_reclaimFieldFocus);
    _name.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _close() => Navigator.of(context).pop();

  void _submit() {
    if (_canConfirm) Navigator.of(context).pop(_name.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return DialogShell(
      frameKey: const Key('group-name-frame'),
      autofocus: false,
      size: _dialogSize(context),
      eyebrow: widget.eyebrow,
      title: widget.title,
      onClose: _close,
      closeKey: const Key('group-name-close'),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Name',
              style: theme.textTheme.labelSmall?.copyWith(
                fontSize: 11.5,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 6),
            SettingsTextField(
              key: const Key('group-name-field'),
              controller: _name,
              focusNode: _focus,
              autofocus: true,
              onSubmitted: (_) => _submit(),
            ),
          ],
        ),
      ),
      footer: Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
        child: Row(
          children: [
            const Spacer(),
            BrandGlassButton(
              key: const Key('group-name-cancel'),
              height: 40,
              expand: false,
              onPressed: _close,
              label: const Text('Cancel'),
            ),
            const SizedBox(width: 10),
            BrandButton(
              key: const Key('group-name-confirm'),
              height: 40,
              expand: false,
              onPressed: _canConfirm ? _submit : null,
              label: Text(widget.confirmLabel),
            ),
          ],
        ),
      ),
    );
  }
}
