// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';

/// Short-lived messages. Info sinks to the bottom, errors hang at the top.
class Toast {
  Toast(this._context);

  final BuildContext _context;

  void show(String msg) {
    final scheme = Theme.of(_context).colorScheme;
    Fluttertoast.showToast(
      msg: msg,
      gravity: ToastGravity.BOTTOM,
      backgroundColor: scheme.inverseSurface,
      textColor: scheme.onInverseSurface,
    );
  }

  void showError(String error) {
    final text = error.trim().isEmpty ? 'Something went wrong' : error.trim();
    final scheme = Theme.of(_context).colorScheme;
    Fluttertoast.showToast(
      msg: text,
      gravity: ToastGravity.TOP,
      backgroundColor: scheme.error,
      textColor: scheme.onError,
    );
  }

  void close() => Fluttertoast.cancel();
}
