import 'dart:convert';

import 'package:http/http.dart' as http;

import 'models.dart';

class LyricLine {
  final Duration t;
  final String text;
  const LyricLine(this.t, this.text);
}

class Lyrics {
  final List<LyricLine> synced;
  final String plain;
  const Lyrics(this.synced, this.plain);
  bool get isSynced => synced.isNotEmpty;
}

/// Time-synced lyrics from LRCLIB (free, no key).
class LyricsService {
  static final Map<String, Lyrics?> _cache = {};

  static String clean(String t) => t
      .replaceAll(RegExp(r'\(.*?\)|\[.*?\]|official|video|lyrical|lyrics|audio|hd|4k|\|.*', caseSensitive: false), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  static List<LyricLine> parseLrc(String lrc) {
    final out = <LyricLine>[];
    final tag = RegExp(r'\[(\d+):(\d+)(?:[.:](\d+))?\]');
    for (final line in lrc.split('\n')) {
      final ms = tag.allMatches(line).toList();
      if (ms.isEmpty) continue;
      final text = line.replaceAll(tag, '').trim();
      for (final m in ms) {
        final frac = m.group(3) ?? '0';
        final millis = int.parse(frac.padRight(3, '0').substring(0, 3));
        out.add(LyricLine(
            Duration(minutes: int.parse(m.group(1)!), seconds: int.parse(m.group(2)!), milliseconds: millis), text));
      }
    }
    out.sort((a, b) => a.t.compareTo(b.t));
    return out;
  }

  static Future<Lyrics?> get(Track t) async {
    if (_cache.containsKey(t.id)) return _cache[t.id];
    Lyrics? result;
    try {
      final q = clean(t.title);
      final r = await http
          .get(Uri.parse('https://lrclib.net/api/search?q=${Uri.encodeQueryComponent(q)}'))
          .timeout(const Duration(seconds: 12));
      final list = (jsonDecode(r.body) as List).cast<Map>();
      int dist(Map e) => t.seconds == null || e['duration'] == null
          ? 0
          : ((e['duration'] as num).toInt() - t.seconds!).abs();
      final synced = list.where((e) => (e['syncedLyrics'] ?? '').toString().trim().isNotEmpty).toList()
        ..sort((a, b) => dist(a).compareTo(dist(b)));
      if (synced.isNotEmpty && dist(synced.first) <= 15) {
        final e = synced.first;
        result = Lyrics(parseLrc(e['syncedLyrics'] as String), (e['plainLyrics'] ?? '').toString());
      } else {
        final plain = list.where((e) => (e['plainLyrics'] ?? '').toString().trim().isNotEmpty).toList();
        if (plain.isNotEmpty) result = Lyrics(const [], plain.first['plainLyrics'] as String);
      }
    } catch (_) {}
    return _cache[t.id] = result;
  }
}
