// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:math' as math;

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
    final scheme = theme.colorScheme;
    final sessions = game.playSessions.toList()
      ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
    final total = game.totalPlaytimeSeconds;
    final lastPlayed = game.lastPlayedAt;
    final longest = sessions.fold(
      0,
      (best, s) => math.max(best, s.durationSeconds),
    );
    final now = DateTime.now();
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 28,
            runSpacing: 12,
            children: [
              _Fact(
                label: 'Total',
                child: Text(total > 0 ? formatPlaytime(total) : 'Never'),
              ),
              _Fact(label: 'Sessions', child: Text('${sessions.length}')),
              _Fact(
                label: 'Last played',
                child: Text(
                  lastPlayed == null ? 'Never' : formatPlayDay(lastPlayed, now),
                ),
              ),
            ],
          ),
          detailSectionDivider(context),
          DetailSection(
            label: 'Sessions',
            child: sessions.isEmpty
                ? Text(
                    'Not played yet',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < sessions.length; i++)
                        _SessionRow(
                          session: sessions[i],
                          now: now,
                          fraction: longest == 0
                              ? 0
                              : sessions[i].durationSeconds / longest,
                          barKey: Key('session-bar-$i'),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _SessionRow extends StatefulWidget {
  const _SessionRow({
    required this.session,
    required this.now,
    required this.fraction,
    required this.barKey,
  });

  final PlaySession session;
  final DateTime now;
  final double fraction;
  final Key barKey;

  @override
  State<_SessionRow> createState() => _SessionRowState();
}

class _SessionRowState extends State<_SessionRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final session = widget.session;
    final start = session.startedAt.toLocal();
    final end = start.add(Duration(seconds: session.durationSeconds));
    final clock = DateFormat('HH:mm');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MouseRegion(
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            decoration: BoxDecoration(
              color: _hovered ? scheme.onSurface.withValues(alpha: 0.04) : null,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        formatPlayDay(start, widget.now),
                        style: theme.textTheme.bodyMedium,
                      ),
                      Text(
                        '${clock.format(start)} – ${clock.format(end)}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  formatPlaytime(session.durationSeconds),
                  textAlign: TextAlign.right,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: ColoredBox(
              color: scheme.onSurface.withValues(alpha: 0.05),
              child: SizedBox(
                height: 4,
                child: FractionallySizedBox(
                  key: widget.barKey,
                  widthFactor: widget.fraction,
                  alignment: Alignment.centerLeft,
                  child: ColoredBox(
                    color: scheme.primary.withValues(alpha: 0.7),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            fontSize: 11.5,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 3),
        DefaultTextStyle.merge(
          style: theme.textTheme.bodyMedium?.copyWith(fontSize: 14),
          child: child,
        ),
      ],
    );
  }
}
