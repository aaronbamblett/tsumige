// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';

class Toast {
  Toast(this._context) {
    _fToast = FToast().init(_context);
  }

  final BuildContext _context;
  late FToast _fToast;

  void show(String msg) {
    final scheme = Theme.of(_context).colorScheme;
    _fToast.showToast(
      child: _ToastBody(
        text: msg,
        backgroundColor: scheme.inverseSurface,
        textColor: scheme.onInverseSurface,
      ),
      gravity: ToastGravity.BOTTOM,
      toastDuration: const Duration(seconds: 3),
    );
  }

  void showError(String error) {
    final text = error.trim().isEmpty ? 'Something went wrong' : error.trim();
    final scheme = Theme.of(_context).colorScheme;
    _fToast.showToast(
      child: _ToastBody(
        text: text,
        backgroundColor: scheme.error,
        textColor: scheme.onError,
      ),
      gravity: ToastGravity.TOP,
      toastDuration: const Duration(seconds: 5),
    );
  }

  void close() => _fToast.removeCustomToast();
}

class _ToastBody extends StatelessWidget {
  const _ToastBody({
    required this.text,
    required this.backgroundColor,
    required this.textColor,
  });

  final String text;
  final Color backgroundColor;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: backgroundColor,
      ),
      child: Text(
        text,
        style: TextStyle(color: textColor),
        textAlign: TextAlign.center,
      ),
    );
  }
}
