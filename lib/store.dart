import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import 'models.dart';

final yt = YoutubeExplode();
final store = Store();

/// Everything saved on the phone: likes, playlists, history, downloads, settings.
class Store extends ChangeNotifier {
  late SharedPreferences _sp;
  List<Track> liked = [], recents = [], dlTracks = [];
  Map<String, List<Track>> playlists = {};
  List<String> history = [];
  Map<String, String> downloads = {}; // videoId -> file path
  Map<String, double> progress = {}; // videoId -> 0..1 while downloading
  double crossfade = 6;
  final Map<String, List<Track>> _shelves = {};

  List<Track> _rd(String k) => (jsonDecode(_sp.getString(k) ?? '[]') as List)
      .map((e) => Track.fromJson(Map<String, dynamic>.from(e)))
      .toList();

  Future<void> load() async {
    _sp = await SharedPreferences.getInstance();
    liked = _rd('liked');
    recents = _rd('recents');
    dlTracks = _rd('dltracks');
    final pl = jsonDecode(_sp.getString('playlists') ?? '{}') as Map<String, dynamic>;
    playlists = pl.map((k, v) => MapEntry(
        k, (v as List).map((e) => Track.fromJson(Map<String, dynamic>.from(e))).toList()));
    history = _sp.getStringList('history') ?? [];
    downloads = Map<String, String>.from(jsonDecode(_sp.getString('downloads') ?? '{}'));
    crossfade = _sp.getDouble('crossfade') ?? 6;
  }

  String _enc(List<Track> l) => jsonEncode(l.map((e) => e.toJson()).toList());

  void _save() {
    _sp.setString('liked', _enc(liked));
    _sp.setString('recents', _enc(recents));
    _sp.setString('dltracks', _enc(dlTracks));
    _sp.setString('playlists', jsonEncode(playlists.map((k, v) => MapEntry(k, v.map((e) => e.toJson()).toList()))));
    _sp.setStringList('history', history);
    _sp.setString('downloads', jsonEncode(downloads));
    _sp.setDouble('crossfade', crossfade);
    notifyListeners();
  }

  // ── search & discover ──
  Future<List<Track>> search(String q) async {
    final r = await yt.search.search(q);
    return r
        .map((v) => Track(v.id.value, v.title, v.author, v.thumbnails.highResUrl, v.duration?.inSeconds))
        .toList();
  }

  Future<List<Track>> shelf(String q) async {
    if (_shelves[q] != null) return _shelves[q]!;
    try {
      return _shelves[q] = await search(q);
    } catch (_) {
      return [];
    }
  }

  Future<List<Track>> trending() => shelf('trending songs');

  void addHistory(String q) {
    history.remove(q);
    history.insert(0, q);
    if (history.length > 12) history = history.sublist(0, 12);
    _save();
  }

  void clearHistory() {
    history = [];
    _save();
  }

  // ── likes ──
  bool isLiked(Track t) => liked.any((x) => x.id == t.id);
  void toggleLike(Track t) {
    isLiked(t) ? liked.removeWhere((x) => x.id == t.id) : liked.insert(0, t);
    _save();
  }

  // ── recents ──
  void addRecent(Track t) {
    recents.removeWhere((x) => x.id == t.id);
    recents.insert(0, t);
    if (recents.length > 40) recents = recents.sublist(0, 40);
    _save();
  }

  // ── playlists ──
  void createPlaylist(String name) {
    playlists.putIfAbsent(name, () => []);
    _save();
  }

  void deletePlaylist(String name) {
    playlists.remove(name);
    _save();
  }

  void addToPlaylist(String name, Track t) {
    final l = playlists.putIfAbsent(name, () => []);
    if (!l.any((x) => x.id == t.id)) l.add(t);
    _save();
  }

  void removeFromPlaylist(String name, Track t) {
    playlists[name]?.removeWhere((x) => x.id == t.id);
    _save();
  }

  // ── settings ──
  void setCrossfade(double v) {
    crossfade = v;
    _save();
  }

  // ── downloads ──
  Future<void> download(Track t) async {
    if (downloads.containsKey(t.id) || progress.containsKey(t.id)) return;
    progress[t.id] = 0;
    notifyListeners();
    try {
      final m = await yt.videos.streamsClient.getManifest(t.id);
      final info = m.audioOnly.withHighestBitrate();
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/${t.id}.${info.container.name}');
      final sink = file.openWrite();
      final total = info.size.totalBytes;
      var got = 0, lastTick = 0;
      await for (final chunk in yt.videos.streamsClient.get(info)) {
        sink.add(chunk);
        got += chunk.length;
        if (got - lastTick > total / 50) {
          lastTick = got;
          progress[t.id] = got / total;
          notifyListeners();
        }
      }
      await sink.flush();
      await sink.close();
      downloads[t.id] = file.path;
      if (!dlTracks.any((x) => x.id == t.id)) dlTracks.insert(0, t);
    } catch (_) {}
    progress.remove(t.id);
    _save();
  }

  Future<void> deleteDownload(Track t) async {
    final p = downloads.remove(t.id);
    dlTracks.removeWhere((x) => x.id == t.id);
    if (p != null && File(p).existsSync()) File(p).deleteSync();
    _save();
  }
}
