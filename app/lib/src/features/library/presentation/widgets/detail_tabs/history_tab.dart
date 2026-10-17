// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../../core/format.dart';
import '../../../../../core/model.dart';
import 'info_tab.dart';

class HistoryTab extends StatelessWidget {
  const HistoryTab({super.key, required this.game});

  final Game game;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sessions = game.playSessions.toList()
      ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DetailSection(
            label: 'TOTAL PLAYTIME',
            child: Text(
              formatPlaytime(game.totalPlaytimeSeconds),
              style: theme.textTheme.titleMedium,
            ),
          ),
          detailSectionDivider(context),
          DetailSection(
            label: 'SESSIONS',
            child: sessions.isEmpty
                ? Text(
                    'Not played yet',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    spacing: 4,
                    children: [
                      for (final session in sessions)
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                DateFormat('yyyy-MM-dd HH:mm').format(
                                  session.startedAt.toLocal(),
                                ),
                                style: theme.textTheme.bodyMedium,
                              ),
                            ),
                            Text(
                              formatPlaytime(session.durationSeconds),
                              textAlign: TextAlign.right,
                              style: theme.textTheme.bodyMedium,
                            ),
                          ],
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
