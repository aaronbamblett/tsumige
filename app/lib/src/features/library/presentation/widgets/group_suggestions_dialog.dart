// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../core/group_detection.dart';
import '../../../../core/groups.dart';
import '../../../../core/model.dart';
import '../../../../utils/theme/brand.dart';
import '../../data/library_repository.dart';
import '../../domain/cover_source.dart';
import '../../domain/game_editor.dart';
import '../../domain/group_suggestions.dart';
import 'art_image.dart';
import 'dialog_shell.dart';

/// Opens the series Review list: one card per group suggestion.
Future<void> showGroupSuggestionsDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.5),
    builder: (context) => const GroupSuggestionsDialog(),
  );
}

/// The Review list in the app's dialog shell. Each card Groups through the
/// same path as Combine, or dismisses the suggestion as "Not a series". When
/// the last card is gone the dialog closes by itself.
class GroupSuggestionsDialog extends ConsumerWidget {
  const GroupSuggestionsDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final suggestions = ref.watch(groupSuggestionsProvider);
    if (suggestions.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted && Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
      });
      return const SizedBox.shrink();
    }
    final library = ref.watch(libraryProvider).value?.library;
    final byId = {for (final g in library?.games ?? const <Game>[]) g.id: g};
    return DialogShell(
      frameKey: const Key('group-suggestions-frame'),
      shrinkToContent: true,
      size: dialogShellSize(context),
      eyebrow: 'Series',
      title: 'Group these into one tile each?',
      onClose: () => Navigator.of(context).pop(),
      body: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
        children: [
          for (final suggestion in suggestions)
            _SuggestionCard(suggestion: suggestion, byId: byId),
        ],
      ),
      footer: Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
        child: Row(
          children: [
            const Spacer(),
            BrandGlassButton(
              height: 40,
              expand: false,
              onPressed: () => Navigator.of(context).pop(),
              label: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SuggestionCard extends ConsumerWidget {
  const _SuggestionCard({required this.suggestion, required this.byId});

  final GroupSuggestion suggestion;
  final Map<String, Game> byId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final members = [
      for (final id in suggestion.memberIds)
        if (byId[id] != null) byId[id]!,
    ];
    final shorts = [
      for (final member in members)
        shortNameForGroup(suggestion.name, member.title),
    ];
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (members.isNotEmpty) _SuggestionCover(game: members.first),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${suggestion.name} · ${suggestion.memberIds.length} entries',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    shorts.join(', '),
                    style: const TextStyle(fontSize: 13.5),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            IntrinsicWidth(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                BrandButton(
                  key: Key('suggest-group:${suggestion.key}'),
                  height: 40,
                  expand: false,
                  onPressed: () => ref.read(gameEditorProvider).combineTiles(
                        name: suggestion.name,
                        tileIds: suggestion.memberIds,
                        context: context,
                      ),
                  label: const Text('Group'),
                ),
                const SizedBox(height: 8),
                BrandGlassButton(
                  key: Key('suggest-dismiss:${suggestion.key}'),
                  height: 40,
                  expand: false,
                  onPressed: () => ref
                      .read(gameEditorProvider)
                      .dismissGroupSuggestion(
                        suggestion.key,
                        context: context,
                      ),
                  label: const Text('Not a series'),
                ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The first member's cover at 2:3, small; a placeholder icon when it has
/// none. The thumbnail is too small for `No cover` text (it wraps), so it
/// reuses the app's small no-cover placeholder icon in `scheme.outline`.
class _SuggestionCover extends ConsumerWidget {
  const _SuggestionCover({required this.game});

  final Game game;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dir = ref.watch(dataDirProvider);
    final exists = ref.watch(coverExistsProvider);
    final version = ref.watch(artVersionProvider);
    final scheme = Theme.of(context).colorScheme;
    final source = coverSourceFor(game, dir, 96, exists);
    final placeholder = Center(
      child: Icon(
        Icons.image_not_supported_outlined,
        color: scheme.outline,
      ),
    );
    return SizedBox(
      width: 48,
      child: AspectRatio(
        aspectRatio: 2 / 3,
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
          ),
          child: source == null
              ? placeholder
              : Image(
                  image: source.isThumbnail
                      ? artFileImage(
                          File(source.path),
                          version: version(source.path),
                        )
                      : artFileImage(
                          File(source.path),
                          version: version(source.path),
                          cacheWidth: 96,
                        ),
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                  errorBuilder: (_, _, _) => placeholder,
                ),
        ),
      ),
    );
  }
}
