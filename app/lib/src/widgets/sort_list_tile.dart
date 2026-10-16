// Copyright (c) 2022 Contributors to the Suwayomi project
// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';

class SortListTile extends StatelessWidget {
  const SortListTile({
    super.key,
    required this.ascending,
    required this.selected,
    required this.onChanged,
    required this.onSelected,
    this.title,
    this.subtitle,
  });
  final bool ascending;
  final bool selected;
  final ValueChanged<bool?> onChanged;
  final VoidCallback onSelected;
  final Widget? title;
  final Widget? subtitle;
  @override
  Widget build(BuildContext context) {
    IconData icon =
        ascending ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded;

    return ListTile(
      leading: selected
          ? Icon(icon, color: Theme.of(context).colorScheme.primary)
          : SizedBox(width: Theme.of(context).iconTheme.size),
      title: title,
      subtitle: subtitle,
      onTap: () => selected ? onChanged(!ascending) : onSelected(),
    );
  }
}
