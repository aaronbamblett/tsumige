// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:intl/intl.dart';

String formatPlaytime(int seconds) {
  if (seconds < 60) return '<1 min';
  return seconds < 3600
      ? '${seconds ~/ 60} min'
      : '${(seconds / 3600).toStringAsFixed(1)} hrs';
}

/// "Today", "Yesterday", or a short date such as "Oct 12" (with the year
/// when it is not the current one), judged on the local calendar day.
String formatPlayDay(DateTime at, DateTime now) {
  final local = at.toLocal();
  final days = DateTime.utc(
    now.year,
    now.month,
    now.day,
  ).difference(DateTime.utc(local.year, local.month, local.day)).inDays;
  if (days == 0) return 'Today';
  if (days == 1) return 'Yesterday';
  return DateFormat(local.year == now.year ? 'MMM d' : 'MMM d, y')
      .format(local);
}

String formatVndbRating(double rating) =>
    'VNDB Rating ${(rating / 10).toStringAsFixed(1)}';
