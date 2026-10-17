// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter_test/flutter_test.dart';
import 'package:vnl/src/features/library/domain/vndb_markup.dart';

void main() {
  test('[b]x[/b] parses to a bold node containing text x', () {
    final nodes = parseVndbMarkup('[b]x[/b]');
    expect(nodes, hasLength(1));
    expect(nodes.first, isA<BoldNode>());
    final children = (nodes.first as BoldNode).children;
    expect(children, hasLength(1));
    expect(children.first, isA<TextNode>());
    expect((children.first as TextNode).text, 'x');
  });

  test('[url=...]...[/url] parses to a link node', () {
    final nodes = parseVndbMarkup('[url=https://vndb.org]VNDB[/url]');
    expect(nodes, hasLength(1));
    expect(nodes.first, isA<LinkNode>());
    final link = nodes.first as LinkNode;
    expect(link.url, 'https://vndb.org');
    expect(link.children, hasLength(1));
    expect(link.children.first, isA<TextNode>());
    expect((link.children.first as TextNode).text, 'VNDB');
  });

  test('[spoiler]x[/spoiler] parses to a spoiler', () {
    final nodes = parseVndbMarkup('[spoiler]x[/spoiler]');
    expect(nodes, hasLength(1));
    expect(nodes.first, isA<SpoilerNode>());
    final children = (nodes.first as SpoilerNode).children;
    expect(children, hasLength(1));
    expect((children.first as TextNode).text, 'x');
  });

  test('[b][i]x[/i][/b] parses to bold > italic > text', () {
    final nodes = parseVndbMarkup('[b][i]x[/i][/b]');
    expect(nodes, hasLength(1));
    expect(nodes.first, isA<BoldNode>());
    final boldChildren = (nodes.first as BoldNode).children;
    expect(boldChildren, hasLength(1));
    expect(boldChildren.first, isA<ItalicNode>());
    final italicChildren = (boldChildren.first as ItalicNode).children;
    expect(italicChildren, hasLength(1));
    expect((italicChildren.first as TextNode).text, 'x');
  });

  test('unclosed [b]x gives literal text', () {
    final nodes = parseVndbMarkup('[b]x');
    expect(nodes, hasLength(1));
    expect(nodes.first, isA<TextNode>());
    expect((nodes.first as TextNode).text, '[b]x');
  });

  test('unknown [foo]x[/foo] gives literal text', () {
    final nodes = parseVndbMarkup('[foo]x[/foo]');
    expect(nodes, hasLength(1));
    expect(nodes.first, isA<TextNode>());
    expect((nodes.first as TextNode).text, '[foo]x[/foo]');
  });

  test('plain text gives a single text node', () {
    final nodes = parseVndbMarkup('hello world');
    expect(nodes, hasLength(1));
    expect(nodes.first, isA<TextNode>());
    expect((nodes.first as TextNode).text, 'hello world');
  });

  test('isOpenableUrl allows only http and https', () {
    expect(isOpenableUrl('https://vndb.org'), isTrue);
    expect(isOpenableUrl('http://x'), isTrue);
    expect(isOpenableUrl('file:///etc/passwd'), isFalse);
    expect(isOpenableUrl('smb://h/s'), isFalse);
    expect(isOpenableUrl('javascript:alert(1)'), isFalse);
    expect(isOpenableUrl('not a url'), isFalse);
  });
}
