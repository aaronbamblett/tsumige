// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';

import '../../../../../core/model.dart';

class RoutesTab extends StatelessWidget {
  const RoutesTab({super.key, required this.game});

  final Game game;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: game.routes.isEmpty
          ? Text(
              'No routes',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 4,
              children: [
                for (final route in game.routes)
                  Row(
                    children: [
                      Expanded(child: Text(route.name)),
                      if (route.completed)
                        const Icon(Icons.check_rounded),
                      if (route.name == game.activeRoute)
                        const Padding(
                          padding: EdgeInsets.only(left: 8),
                          child: Text('Active'),
                        ),
                    ],
                  ),
              ],
            ),
    );
  }
}
