// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:vnl/src/core/model.dart';

Game _full() => Game(
      id: 'g1',
      title: 'Sample Game',
      vndbId: 'v1',
      vndbOriginalTitle: '相称',
      developers: [
        const Developer(id: 'p1', name: 'Hacca', original: 'ハッカ'),
        const Developer(id: 'p2', name: 'Other'),
      ],
      lengthMinutes: 900,
      lengthVotes: 42,
      originalLanguage: 'ja',
      vndbTags: [
        const VndbTag(name: 'time loop', rating: 2.4, spoiler: 1, category: 'cont'),
        const VndbTag(name: 'comedy', rating: 1.0, spoiler: 0, category: 'tech'),
      ],
      relations: [
        const VnRelation(
          vndbId: 'v2',
          relation: 'seq',
          title: 'Sequel',
          imageUrl: 'https://t.vndb.org/cv/2.jpg',
          official: true,
        ),
      ],
      adultVndb: false,
      adultOverride: true,
      vndbDataFetchedAt: DateTime.utc(2026, 10, 17, 9),
    );

void main() {
  test('new fields round-trip through toJson and fromJson', () {
    final game = _full();
    final json = jsonDecode(jsonEncode(game.toJson())) as Map<String, Object?>;
    final back = Game.fromJson(json);
    expect(back.vndbOriginalTitle, '相称');
    expect(back.developers.map((d) => d.id), ['p1', 'p2']);
    expect(back.developers.first.original, 'ハッカ');
    expect(back.developers.last.original, isNull);
    expect(back.lengthMinutes, 900);
    expect(back.lengthVotes, 42);
    expect(back.originalLanguage, 'ja');
    expect(back.vndbTags.first.spoiler, 1);
    expect(back.vndbTags.first.rating, 2.4);
    expect(back.vndbTags.first.category, 'cont');
    expect(back.relations.single.vndbId, 'v2');
    expect(back.relations.single.relation, 'seq');
    expect(back.relations.single.official, isTrue);
    expect(back.relations.single.imageUrl, 'https://t.vndb.org/cv/2.jpg');
    expect(back.adultVndb, isFalse);
    expect(back.adultOverride, isTrue);
    expect(back.vndbDataFetchedAt, DateTime.utc(2026, 10, 17, 9));
    expect(back.tags, isEmpty);
  });

  test('a game saved without the new fields loads', () {
    final old = Game.fromJson({
      'id': 'g2',
      'title': 'Old',
      'tags': ['mine'],
      'vndb_id': 'v3',
      'vndb_rating': 70.5,
    });
    expect(old.title, 'Old');
    expect(old.tags, ['mine']);
    expect(old.vndbRating, 70.5);
    expect(old.vndbOriginalTitle, isNull);
    expect(old.developers, isEmpty);
    expect(old.lengthMinutes, isNull);
    expect(old.originalLanguage, isNull);
    expect(old.vndbTags, isEmpty);
    expect(old.relations, isEmpty);
    expect(old.adultVndb, isNull);
    expect(old.adultOverride, isNull);
    expect(old.vndbDataFetchedAt, isNull);
  });

  test('invalid new values read as null or empty', () {
    final game = Game.fromJson({
      'id': 'g3',
      'original_title': 42,
      'developers': [
        'not a map',
        {'name': 'no id'},
        {'id': 'p9', 'name': 'Kept'},
      ],
      'length_minutes': 'long',
      'length_votes': 1.5,
      'original_language': ['ja'],
      'vndb_tags': [
        {'name': 'ok', 'rating': 'high', 'spoiler': 'x'},
        {'rating': 2.0},
      ],
      'relations': [
        {'relation': 'seq'},
        {'vndb_id': 'v5', 'official': 'yes'},
      ],
      'adult_vndb': 'true',
      'adult_override': 1,
      'vndb_data_fetched_at': 'not a date',
    });
    expect(game.vndbOriginalTitle, isNull);
    expect(game.developers.map((d) => d.id), ['p9']);
    expect(game.lengthMinutes, isNull);
    expect(game.lengthVotes, isNull);
    expect(game.originalLanguage, isNull);
    expect(game.vndbTags.single.name, 'ok');
    expect(game.vndbTags.single.rating, 0);
    expect(game.vndbTags.single.spoiler, 0);
    expect(game.vndbTags.single.category, '');
    expect(game.relations.single.vndbId, 'v5');
    expect(game.relations.single.official, isFalse);
    expect(game.adultVndb, isNull);
    expect(game.adultOverride, isNull);
    expect(game.vndbDataFetchedAt, isNull);
  });

  test('isAdult takes the override, then VNDB, then false', () {
    expect(Game(id: 'a').isAdult, isFalse);
    expect(Game(id: 'a', adultVndb: true).isAdult, isTrue);
    expect(Game(id: 'a', adultVndb: false).isAdult, isFalse);
    expect(Game(id: 'a', adultVndb: true, adultOverride: false).isAdult, isFalse);
    expect(Game(id: 'a', adultVndb: false, adultOverride: true).isAdult, isTrue);
    expect(Game(id: 'a', adultOverride: true).isAdult, isTrue);
  });
}
