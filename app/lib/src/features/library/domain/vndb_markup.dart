// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// VNDB description markup: `[b]`, `[i]`, `[url=...]` and `[spoiler]`,
/// nestable. An unclosed or unknown tag renders as literal text.
sealed class MarkupNode {
  const MarkupNode();
}

/// Plain text.
class TextNode extends MarkupNode {
  const TextNode(this.text);

  final String text;
}

/// Bold block.
class BoldNode extends MarkupNode {
  const BoldNode(this.children);

  final List<MarkupNode> children;
}

/// Italic block.
class ItalicNode extends MarkupNode {
  const ItalicNode(this.children);

  final List<MarkupNode> children;
}

/// Link block with its target url.
class LinkNode extends MarkupNode {
  const LinkNode(this.url, this.children);

  final String url;
  final List<MarkupNode> children;
}

/// Spoiler block, hidden until tapped.
class SpoilerNode extends MarkupNode {
  const SpoilerNode(this.children);

  final List<MarkupNode> children;
}

enum _TagKind { bold, italic, url, spoiler }

String _closeTag(_TagKind kind) => switch (kind) {
      _TagKind.bold => '[/b]',
      _TagKind.italic => '[/i]',
      _TagKind.url => '[/url]',
      _TagKind.spoiler => '[/spoiler]',
    };

MarkupNode _nodeFor(_TagKind kind, String? arg, List<MarkupNode> children) =>
    switch (kind) {
      _TagKind.bold => BoldNode(children),
      _TagKind.italic => ItalicNode(children),
      _TagKind.url => LinkNode(arg ?? '', children),
      _TagKind.spoiler => SpoilerNode(children),
    };

/// Parses one tag at [start] (which holds '['). Returns the kind, url arg and
/// total tag length, or null when the brackets hold no supported tag.
(_TagKind, String?, int)? _parseOpenTag(String s, int start) {
  final end = s.indexOf(']', start + 1);
  if (end < 0) return null;
  final body = s.substring(start + 1, end);
  final length = end - start + 1;
  switch (body) {
    case 'b':
      return (_TagKind.bold, null, length);
    case 'i':
      return (_TagKind.italic, null, length);
    case 'spoiler':
      return (_TagKind.spoiler, null, length);
  }
  if (body.startsWith('url=')) {
    final url = body.substring(4);
    if (url.isNotEmpty) return (_TagKind.url, url, length);
  }
  return null;
}

class _Parser {
  _Parser(this.s);

  final String s;

  (List<MarkupNode>, int, bool) parseNodes(int pos, String? closer) {
    final nodes = <MarkupNode>[];
    final text = StringBuffer();
    void flushText() {
      if (text.isNotEmpty) {
        nodes.add(TextNode(text.toString()));
        text.clear();
      }
    }

    while (pos < s.length) {
      if (closer != null && s.startsWith(closer, pos)) {
        flushText();
        return (nodes, pos + closer.length, true);
      }
      if (s[pos] != '[') {
        text.write(s[pos]);
        pos++;
        continue;
      }
      final open = _parseOpenTag(s, pos);
      if (open == null) {
        final end = s.indexOf(']', pos + 1);
        if (end < 0) {
          text.write(s.substring(pos));
          return (nodes..add(TextNode(text.toString())), s.length, false);
        }
        text.write(s.substring(pos, end + 1));
        pos = end + 1;
        continue;
      }
      final (kind, arg, length) = open;
      final (children, next, closed) =
          parseNodes(pos + length, _closeTag(kind));
      if (!closed) {
        flushText();
        nodes.add(TextNode(s.substring(pos)));
        return (nodes, s.length, false);
      }
      flushText();
      nodes.add(_nodeFor(kind, arg, children));
      pos = next;
    }
    flushText();
    return (nodes, pos, false);
  }
}

/// Parses VNDB markup into a node tree.
List<MarkupNode> parseVndbMarkup(String text) =>
    _Parser(text).parseNodes(0, null).$1;

/// Renders [parseVndbMarkup] output as text. Links open in the system browser;
/// spoilers paint as a solid block until tapped.
class VndbMarkupText extends StatefulWidget {
  const VndbMarkupText({super.key, required this.text});

  final String text;

  @override
  State<VndbMarkupText> createState() => _VndbMarkupTextState();
}

class _VndbMarkupTextState extends State<VndbMarkupText> {
  final _revealed = <int>{};
  final _recognizers = <GestureRecognizer>[];

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  void _disposeRecognizers() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
  }

  TapGestureRecognizer _tapRecognizer(VoidCallback onTap) {
    final recognizer = TapGestureRecognizer()..onTap = onTap;
    _recognizers.add(recognizer);
    return recognizer;
  }

  @override
  Widget build(BuildContext context) {
    _disposeRecognizers();
    final colorScheme = Theme.of(context).colorScheme;
    var spoilerIndex = 0;
    // Only the deepest span's recognizer fires, so styles and taps flatten
    // onto the leaf spans. A hidden spoiler's reveal tap wins over a link
    // inside it: the first tap reveals, the next opens the link.
    TextSpan spanFor(
        MarkupNode node, TextStyle? style, TapGestureRecognizer? recognizer) {
      TextStyle merged(TextStyle add) =>
          style == null ? add : style.merge(add);
      switch (node) {
        case TextNode(:final text):
          return TextSpan(
              text: text, style: style, recognizer: recognizer);
        case BoldNode(:final children):
          return TextSpan(children: [
            for (final child in children)
              spanFor(
                  child,
                  merged(
                      const TextStyle(fontWeight: FontWeight.bold)),
                  recognizer),
          ]);
        case ItalicNode(:final children):
          return TextSpan(children: [
            for (final child in children)
              spanFor(
                  child,
                  merged(
                      const TextStyle(fontStyle: FontStyle.italic)),
                  recognizer),
          ]);
        case LinkNode(:final url, :final children):
          return TextSpan(children: [
            for (final child in children)
              spanFor(
                  child,
                  merged(TextStyle(
                    color: colorScheme.primary,
                    decoration: TextDecoration.underline,
                  )),
                  _tapRecognizer(() {
                    final uri = Uri.tryParse(url);
                    if (uri != null) {
                      launchUrl(uri,
                          mode: LaunchMode.externalApplication);
                    }
                  })),
          ]);
        case SpoilerNode(:final children):
          final index = spoilerIndex++;
          if (_revealed.contains(index)) {
            return TextSpan(children: [
              for (final child in children)
                spanFor(child, style, recognizer),
            ]);
          }
          final hidden = colorScheme.onSurface;
          return TextSpan(children: [
            for (final child in children)
              spanFor(
                  child,
                  merged(TextStyle(
                      color: hidden, backgroundColor: hidden)),
                  _tapRecognizer(() =>
                      setState(() => _revealed.add(index)))),
          ]);
      }
    }

    final nodes = parseVndbMarkup(widget.text);
    return Text.rich(
      TextSpan(children: [
        for (final node in nodes) spanFor(node, null, null),
      ]),
    );
  }
}
