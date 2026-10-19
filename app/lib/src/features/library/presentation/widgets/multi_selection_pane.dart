// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../utils/theme/brand.dart';
import '../../data/library_repository.dart';
import '../../domain/game_editor.dart';
import '../../domain/selection.dart';
import 'group_name_dialog.dart';

/// The pane slot's content while 2 or more tiles are selected: a heading,
/// their titles (a group shows as its name plus its member count), and
/// `Combine into one tile…` plus `Clear selection`.
class MultiSelectionPane extends ConsumerWidget {
  const MultiSelectionPane({super.key, required this.tileIds});

  final List<String> tileIds;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final library = ref.watch(libraryProvider).value?.library;
    final byId = {for (final g in library?.games ?? const []) g.id: g};
    final groupsById = {for (final g in library?.groups ?? const []) g.id: g};
    final rows = <String>[];
    for (final id in tileIds) {
      final group = groupsById[id];
      if (group != null) {
        rows.add('${group.name} (${group.memberIds.length})');
      } else {
        final game = byId[id];
        if (game != null) rows.add(game.title);
      }
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${tileIds.length} games selected',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final row in rows)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Text(
                        row,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          BrandButton(
            onPressed: () async {
              final name = await showCombineDialog(context, tileIds);
              if (name == null || !context.mounted) return;
              await ref.read(gameEditorProvider).combineTiles(
                    name: name,
                    tileIds: tileIds,
                    context: context,
                  );
            },
            label: const Text('Combine into one tile…'),
          ),
          const SizedBox(height: 10),
          BrandGlassButton(
            onPressed: () =>
                ref.read(multiSelectionProvider.notifier).clear(),
            label: const Text('Clear selection'),
          ),
        ],
      ),
    );
  }
}
