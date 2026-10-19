// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../utils/prefs/app_prefs.dart';
import '../../domain/group_suggestions.dart';
import 'group_suggestions_dialog.dart';

/// Dismissible notice above the cover grid, shown while series in the library
/// can be grouped into one tile each. `Review` opens the suggestion list;
/// `Dismiss` hides the notice until the suggestion set changes (it never
/// marks anything "Not a series").
class GroupSuggestionNotice extends ConsumerWidget {
  const GroupSuggestionNotice({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final suggestions = ref.watch(visibleGroupSuggestionsProvider);
    if (suggestions.isEmpty) return const SizedBox.shrink();
    final text = suggestions.length == 1
        ? '1 series in your library can be grouped into one tile.'
        : '${suggestions.length} series in your library can be grouped '
            'into one tile each.';
    return Card(
      margin: const EdgeInsets.all(8),
      child: ListTile(
        dense: true,
        title: Text(text),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextButton(
              onPressed: () => showGroupSuggestionsDialog(context),
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.primary,
              ),
              child: const Text('Review'),
            ),
            IconButton(
              tooltip: 'Dismiss',
              icon: const Icon(Icons.close_rounded),
              onPressed: () => ref
                  .read(dismissedSuggestionNoticeProvider.notifier)
                  .dismiss({for (final s in suggestions) s.key}),
            ),
          ],
        ),
      ),
    );
  }
}
