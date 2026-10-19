// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Dialog size: 960 x 720, shrunk to 90% of a smaller window.
Size dialogShellSize(BuildContext context) {
  final window = MediaQuery.sizeOf(context);
  return Size(
    math.min(960.0, window.width * 0.9),
    math.min(720.0, window.height * 0.9),
  );
}

/// Shared dialog frame: a small label above a 20 px title, a close button,
/// dividers around the body, and a footer. Escape closes it. With
/// [shrinkToContent] the frame wraps a shrink-wrapping body up to [size]
/// instead of filling it.
class DialogShell extends StatelessWidget {
  const DialogShell({
    super.key,
    this.frameKey,
    this.autofocus = true,
    this.shrinkToContent = false,
    required this.size,
    required this.eyebrow,
    required this.title,
    required this.onClose,
    required this.body,
    required this.footer,
    this.closeKey,
  });

  final Size size;
  final String eyebrow;
  final String title;
  final VoidCallback onClose;
  final Widget body;
  final Widget footer;
  final Key? closeKey;
  final Key? frameKey;
  final bool autofocus;
  final bool shrinkToContent;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Dialog(
      insetPadding: EdgeInsets.zero,
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: Container(
        key: frameKey,
        width: size.width,
        height: shrinkToContent ? null : size.height,
        constraints: shrinkToContent
            ? BoxConstraints(maxHeight: size.height)
            : null,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: scheme.surfaceContainer,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Focus(
          autofocus: autofocus,
          onKeyEvent: (node, event) {
            if (event is KeyDownEvent &&
                event.logicalKey == LogicalKeyboardKey.escape) {
              onClose();
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: Column(
            mainAxisSize:
                shrinkToContent ? MainAxisSize.min : MainAxisSize.max,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 14, 12, 14),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            eyebrow,
                            style: TextStyle(
                              fontSize: 12.5,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      key: closeKey,
                      tooltip: 'Close',
                      icon: const Icon(Icons.close_rounded),
                      onPressed: onClose,
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: scheme.outlineVariant),
              if (shrinkToContent) Flexible(child: body) else Expanded(child: body),
              Divider(height: 1, color: scheme.outlineVariant),
              footer,
            ],
          ),
        ),
      ),
    );
  }
}
