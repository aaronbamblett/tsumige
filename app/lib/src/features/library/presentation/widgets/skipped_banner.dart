// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';

import '../../../../core/model.dart';

/// Lists every library entry that failed to parse, with its index, title and
/// reason.
class SkippedBanner extends StatelessWidget {
  const SkippedBanner({super.key, required this.skipped});

  final List<SkippedEntry> skipped;

  @override
  Widget build(BuildContext context) {
    if (skipped.isEmpty) return const SizedBox.shrink();
    return Card(
      margin: const EdgeInsets.all(8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final entry in skipped)
            ListTile(
              dense: true,
              title: Text(entry.title ?? 'Untitled entry'),
              subtitle: Text('Entry ${entry.index}: ${entry.reason}'),
            ),
        ],
      ),
    );
  }
}
