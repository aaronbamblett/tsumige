// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';

import '../../../../../core/model.dart';
import '../../../domain/vndb_markup.dart';

TextStyle? detailSectionLabelStyle(BuildContext context) {
  final theme = Theme.of(context);
  return theme.textTheme.labelSmall?.copyWith(
    color: theme.colorScheme.onSurfaceVariant,
    letterSpacing: 1.0,
  );
}

Widget detailSectionDivider(BuildContext context) => Divider(
      height: 24,
      thickness: 1,
      color: Theme.of(context).colorScheme.outlineVariant,
    );

class DetailSection extends StatelessWidget {
  const DetailSection({super.key, required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label, style: detailSectionLabelStyle(context)),
        const SizedBox(height: 8),
        child,
      ],
    );
  }
}

class InfoTab extends StatelessWidget {
  const InfoTab({super.key, required this.game});

  final Game game;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final labelStyle = detailSectionLabelStyle(context);
    final blocks = <Widget>[];
    if (game.vndbRating != null ||
        (game.released != null && game.released!.isNotEmpty)) {
      blocks.add(_facts(theme, labelStyle));
    }
    if (game.tags.isNotEmpty) {
      blocks.add(DetailSection(
        label: 'TAGS',
        child: Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final tag in game.tags)
              Chip(
                label: Text(tag, style: theme.textTheme.labelMedium),
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
          ],
        ),
      ));
    }
    if (game.description.isNotEmpty) {
      blocks.add(DetailSection(
        label: 'DESCRIPTION',
        child: DefaultTextStyle(
          style: theme.textTheme.bodyMedium!
              .copyWith(height: 1.5),
          child: VndbMarkupText(text: game.description),
        ),
      ));
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < blocks.length; i++) ...[
            if (i > 0) detailSectionDivider(context),
            blocks[i],
          ],
        ],
      ),
    );
  }

  Widget _facts(ThemeData theme, TextStyle? labelStyle) {
    return Wrap(
      spacing: 32,
      runSpacing: 12,
      children: [
        if (game.vndbRating != null)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('VNDB RATING', style: labelStyle),
              const SizedBox(height: 4),
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: (game.vndbRating! / 10).toStringAsFixed(1),
                      style: theme.textTheme.titleMedium,
                    ),
                    if (game.vndbVotecount != null)
                      TextSpan(
                        text: ' · ${game.vndbVotecount} votes',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        if (game.released != null && game.released!.isNotEmpty)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('RELEASED', style: labelStyle),
              const SizedBox(height: 4),
              Text(game.released!, style: theme.textTheme.bodyLarge),
            ],
          ),
      ],
    );
  }
}
