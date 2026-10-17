// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import 'model.dart';
import 'paths.dart';

const List<int> thumbWidths = [256, 512];

const int thumbPipelineVersion = 1;

const int webpQuality = 85;

const List<String> _originalExtensions = ['png', 'jpg', 'webp', 'gif'];

enum CoverError { unknownFormat, decodeFailed }

class CoverException implements Exception {
  final CoverError error;
  final String? message;

  const CoverException(this.error, [this.message]);

  const CoverException.unknownFormat([this.message])
      : error = CoverError.unknownFormat;

  const CoverException.decodeFailed([this.message])
      : error = CoverError.decodeFailed;

  @override
  String toString() =>
      'CoverException($error${message == null ? '' : ': $message'})';
}

class ThumbReport {
  int generated;
  final List<(String id, String error)> failed;

  ThumbReport({this.generated = 0, List<(String, String)>? failed})
      : failed = failed ?? [];
}

String _thumbPath(String root, String gameId, int width) => p.join(root,
    'covers', 'thumb', 'v$thumbPipelineVersion', '$width', '$gameId.webp');

String thumbPath(DataDir dir, String gameId, int width) =>
    _thumbPath(dir.root, gameId, width);

String _extensionFor(Uint8List bytes, String gameId) {
  if (bytes.isEmpty) {
    throw const CoverException.unknownFormat('empty bytes');
  }
  final ext = switch (img.findFormatForData(bytes)) {
    img.ImageFormat.png => 'png',
    img.ImageFormat.jpg => 'jpg',
    img.ImageFormat.webp => 'webp',
    img.ImageFormat.gif => 'gif',
    _ => null,
  };
  if (ext == null) {
    throw CoverException.unknownFormat(
        'unrecognised image bytes for game $gameId');
  }
  return ext;
}

Future<String> storeOriginal(
    DataDir dir, String gameId, Uint8List bytes) async {
  final ext = _extensionFor(bytes, gameId);
  await dir.coversOriginal.create(recursive: true);
  for (final other in _originalExtensions) {
    if (other == ext) continue;
    final stale = File(p.join(dir.coversOriginal.path, '$gameId.$other'));
    if (await stale.exists()) await stale.delete();
  }
  for (final width in thumbWidths) {
    final stale = File(thumbPath(dir, gameId, width));
    if (await stale.exists()) await stale.delete();
  }
  final name = '$gameId.$ext';
  final dest = File(p.join(dir.coversOriginal.path, name));
  final tmp = File('${dest.path}.$pid.tmp');
  await tmp.writeAsBytes(bytes, flush: true);
  await tmp.rename(dest.path);
  return name;
}

/// Stores a pane background under `covers/background`. Backgrounds have no
/// thumbnails: the pane draws the full image at its own width.
Future<String> storeBackground(
    DataDir dir, String gameId, Uint8List bytes) async {
  final ext = _extensionFor(bytes, gameId);
  await dir.coversBackground.create(recursive: true);
  for (final other in _originalExtensions) {
    if (other == ext) continue;
    final stale = File(p.join(dir.coversBackground.path, '$gameId.$other'));
    if (await stale.exists()) await stale.delete();
  }
  final name = '$gameId.$ext';
  final dest = File(p.join(dir.coversBackground.path, name));
  final tmp = File('${dest.path}.$pid.tmp');
  await tmp.writeAsBytes(bytes, flush: true);
  await tmp.rename(dest.path);
  return name;
}

void _renderThumbnails(String root, String gameId, Uint8List bytes,
    {void Function(String finalPath, String tmpPath)? onBeforeRename}) {
  img.Image decoded;
  try {
    final candidate = img.decodeImage(bytes);
    if (candidate == null) {
      throw const CoverException.decodeFailed('could not decode cover');
    }
    decoded = candidate;
  } catch (e) {
    if (e is CoverException) rethrow;
    throw CoverException.decodeFailed('$e');
  }
  // Lossless is this encoder's default, so lossy must be asked for explicitly.
  final encoder = img.WebPEncoder(lossless: false, quality: webpQuality);
  for (final width in thumbWidths) {
    final target = min(width, decoded.width);
    final resized = target == decoded.width
        ? decoded
        : img.copyResize(decoded,
            width: target, interpolation: img.Interpolation.average);
    final out = File(_thumbPath(root, gameId, width));
    out.parent.createSync(recursive: true);
    final tmp = File('${out.path}.$pid.tmp');
    tmp.writeAsBytesSync(encoder.encode(resized), flush: true);
    onBeforeRename?.call(out.path, tmp.path);
    tmp.renameSync(out.path);
  }
}

Future<void> writeThumbnails(
    DataDir dir, String gameId, String original,
    {void Function(String finalPath, String tmpPath)? onBeforeRename}) async {
  final bytes = await File(p.join(dir.coversOriginal.path, original))
      .readAsBytes();
  _renderThumbnails(dir.root, gameId, bytes,
      onBeforeRename: onBeforeRename);
}

(String, String?)? _renderJob(String root, String id, String original) {
  try {
    final bytes =
        File(p.join(root, 'covers', 'original', original)).readAsBytesSync();
    _renderThumbnails(root, id, bytes);
    return null;
  } catch (e) {
    return (id, '$e');
  }
}

// Top-level entry keeps the isolate message to three strings, so an
// onProgress closure holding UI state is never sent to the isolate.
Future<(String, String?)?> _runJob(String root, String id, String original) =>
    Isolate.run(() => _renderJob(root, id, original));

Future<ThumbReport> generateThumbnails(
  DataDir dir,
  List<(String id, String original)> jobs, {
  int? concurrency,
  void Function(int done, int total)? onProgress,
}) async {
  final total = jobs.length;
  final cap = max(1, concurrency ?? min(Platform.numberOfProcessors, 8));
  final report = ThumbReport();
  var done = 0;
  var next = 0;
  // One isolate job per worker keeps at most cap jobs in flight.
  Future<void> worker() async {
    while (true) {
      final i = next++;
      if (i >= total) return;
      final job = jobs[i];
      (String, String?)? outcome;
      try {
        outcome = await _runJob(dir.root, job.$1, job.$2);
      } catch (e) {
        outcome = (job.$1, '$e');
      }
      done++;
      if (outcome == null) {
        report.generated++;
      } else {
        report.failed.add((outcome.$1, outcome.$2 ?? 'unknown error'));
      }
      onProgress?.call(done, total);
    }
  }
  await Future.wait(List.generate(min(cap, total), (_) => worker()));
  return report;
}

Future<ThumbReport> ensureThumbnails(
  DataDir dir,
  Library library, {
  int? concurrency,
  void Function(int done, int total)? onProgress,
}) async {
  final jobs = <(String, String)>[];
  for (final game in library.games) {
    final cover = game.cover;
    if (cover == null) continue;
    var missing = false;
    for (final width in thumbWidths) {
      if (!File(thumbPath(dir, game.id, width)).existsSync()) {
        missing = true;
        break;
      }
    }
    if (missing) jobs.add((game.id, cover));
  }
  if (jobs.isEmpty) return ThumbReport();
  return generateThumbnails(dir, jobs,
      concurrency: concurrency, onProgress: onProgress);
}
