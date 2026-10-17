// Copyright (c) 2026 Contributors to the Suwayomi project
// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';

import '../../utils/extensions/l10n.dart';

class PopButton extends StatelessWidget {
  const PopButton({super.key, this.popText});
  final String? popText;
  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: () => Navigator.pop(context),
      child: Text(popText ?? context.l10n.cancel),
    );
  }
}
