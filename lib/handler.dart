import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import 'models.dart';
import 'store.dart';

/// Audio brain: background play, notification, Android Auto, crossfade,
/// shuffle/repeat, queue, sleep timer, equalizer.
class WeedHandler extends BaseAudioHandler with QueueHandler, SeekHandler {
  final eqA = AndroidEqualizer();
  final eqB = AndroidEqualizer();
  late AudioPlayer _p = _mk(eqA); // active
  late AudioPlayer _q = _mk(eqB); // incoming (crossfade)

  AudioPlayer _mk(AndroidEqualizer e) =>
      AudioPlayer(audioPipeline: AudioPipeline(androidAudioEffects: [e]));

  int index = -1;
  bool fading = false, loading = false, _shuffle = false, _swapMeta = false;
  int _failedAt = -1, _errors = 0;
  List<MediaItem> _orig = [];
  List<Track> _lastSearch = [];
  AudioServiceRepeatMode _repeat = AudioServiceRepeatMode.none;
  Timer? _ramp, _sleep;
  final List<StreamSubscription> _subs = [];

  final ValueNotifier<DateTime?> sleepEnd = ValueNotifier(null);
  final Map<int, double> gains = {};
  bool eqOn = false;

  WeedHandler() {
    _bind();
  }

  // ───────── wiring ─────────
  void _bind() {
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
    _subs.add(_p.playbackEventStream.listen((_) => _broadcast(), onError: (_) {}));
    _subs.add(_p.playingStream.listen((_) => _broadcast()));
    _subs.add(_p.durationStream.listen((d) {
      final m = mediaItem.value;
      if (m != null && d != null && m.duration != d) mediaItem.add(m.copyWith(duration: d));
    }));
    _subs.add(_p.positionStream.listen(_onPos));
    _subs.add(_p.processingStateStream.listen(_onState));
  }

  void _broadcast() {
    final playing = _p.playing;
    playbackState.add(PlaybackState(
      controls: [
        MediaControl.skipToPrevious,
        playing ? MediaControl.pause : MediaControl.play,
        MediaControl.skipToNext,
      ],
      systemActions: const {MediaAction.seek, MediaAction.skipToNext, MediaAction.skipToPrevious},
      androidCompactActionIndices: const [0, 1, 2],
      processingState: loading
          ? AudioProcessingState.loading
          : const {
              ProcessingState.idle: AudioProcessingState.idle,
              ProcessingState.loading: AudioProcessingState.loading,
              ProcessingState.buffering: AudioProcessingState.buffering,
              ProcessingState.ready: AudioProcessingState.ready,
              ProcessingState.completed: AudioProcessingState.completed,
            }[_p.processingState]!,
      playing: playing,
      updatePosition: _p.position,
      bufferedPosition: _p.bufferedPosition,
      speed: _p.speed,
      queueIndex: index < 0 ? null : index,
      shuffleMode: _shuffle ? AudioServiceShuffleMode.all : AudioServiceShuffleMode.none,
      repeatMode: _repeat,
    ));
  }

  // ───────── loading ─────────
  Future<void> _load(AudioPlayer p, Track t) async {
    final f = store.downloads[t.id];
    if (f != null && File(f).existsSync()) {
      await p.setFilePath(f);
      return;
    }
    final m = await yt.videos.streamsClient.getManifest(t.id);
    await p.setUrl(m.audioOnly.withHighestBitrate().url.toString());
  }

  Future<void> _playAt(int i) async {
    final q = queue.value;
    if (i < 0 || i >= q.length) return;
    _ramp?.cancel();
    fading = false;
    _failedAt = -1;
    await _q.stop();
    index = i;
    final item = q[i];
    mediaItem.add(item);
    loading = true;
    _broadcast();
    try {
      await _load(_p, Track.fromItem(item));
      await _p.setVolume(1);
      _applyEq(eqA);
      _p.play();
      _errors = 0;
      store.addRecent(Track.fromItem(item));
    } catch (_) {
      loading = false;
      _broadcast();
      if (_errors++ < 3 && i + 1 < q.length) return _playAt(i + 1);
      return;
    }
    loading = false;
    _broadcast();
  }

  // ───────── auto-advance + crossfade ─────────
  int _autoNext() {
    final len = queue.value.length;
    if (_repeat == AudioServiceRepeatMode.one) return index;
    if (index + 1 < len) return index + 1;
    if (_repeat == AudioServiceRepeatMode.all && len > 0) return 0;
    return -1;
  }

  void _onPos(Duration pos) {
    final d = _p.duration;
    final cfSec = store.crossfade;
    if (d == null || fading || cfSec <= 0 || _failedAt == index) return;
    final n = _autoNext();
    if (n < 0 || n == index) return;
    final cf = Duration(milliseconds: (cfSec * 1000).round());
    if (d > cf * 2 && d - pos <= cf) _crossfadeTo(n);
  }

  void _onState(ProcessingState s) {
    if (s == ProcessingState.completed && !fading) {
      final n = _autoNext();
      if (n >= 0) {
        _playAt(n);
      } else {
        _p.pause();
        _p.seek(Duration.zero);
      }
    }
  }

  Future<void> _crossfadeTo(int n) async {
    fading = true;
    _swapMeta = false;
    final next = queue.value[n];
    try {
      await _load(_q, Track.fromItem(next));
      await _q.setVolume(0);
      _applyEq(eqB);
      _q.play();
    } catch (_) {
      _failedAt = index;
      fading = false;
      return;
    }
    final totalMs = store.crossfade * 1000;
    final sw = Stopwatch()..start();
    _ramp = Timer.periodic(const Duration(milliseconds: 50), (t) {
      final x = (sw.elapsedMilliseconds / totalMs).clamp(0.0, 1.0);
      // equal-power curve keeps loudness smooth through the blend
      _p.setVolume(math.cos(x * math.pi / 2));
      _q.setVolume(math.sin(x * math.pi / 2));
      if (x >= 0.5 && !_swapMeta) {
        _swapMeta = true;
        mediaItem.add(next);
      }
      if (x >= 1) {
        t.cancel();
        _finishSwap(n);
      }
    });
  }

  void _finishSwap(int n) {
    final old = _p;
    _p = _q;
    _q = old;
    old.stop();
    index = n;
    fading = false;
    mediaItem.add(queue.value[n]);
    _bind();
    _broadcast();
    store.addRecent(Track.fromItem(queue.value[n]));
  }

  // ───────── transport ─────────
  Future<void> playItems(List<MediaItem> items, int start) async {
    _shuffle = false;
    _orig = [];
    queue.add(List.of(items));
    await _playAt(start);
  }

  @override
  Future<void> play() async {
    _p.play();
  }

  @override
  Future<void> pause() => _p.pause();

  @override
  Future<void> seek(Duration position) => _p.seek(position);

  @override
  Future<void> skipToQueueItem(int i) => _playAt(i);

  @override
  Future<void> skipToNext() async {
    final len = queue.value.length;
    final n = index + 1 < len ? index + 1 : (_repeat == AudioServiceRepeatMode.all && len > 0 ? 0 : -1);
    if (n >= 0) await _playAt(n);
  }

  @override
  Future<void> skipToPrevious() async {
    if (_p.position > const Duration(seconds: 3) || index <= 0) {
      await _p.seek(Duration.zero);
    } else {
      await _playAt(index - 1);
    }
  }

  @override
  Future<void> stop() async {
    _ramp?.cancel();
    fading = false;
    await _p.stop();
    await _q.stop();
    await super.stop();
  }

  @override
  Future<void> onTaskRemoved() async {
    if (!_p.playing) await stop();
  }

  // ───────── shuffle / repeat ─────────
  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode m) async {
    final on = m != AudioServiceShuffleMode.none;
    if (on == _shuffle) return;
    _shuffle = on;
    final q = [...queue.value];
    if (on) {
      _orig = List.of(q);
      if (index >= 0 && index < q.length) {
        final cur = q.removeAt(index);
        q.shuffle();
        q.insert(0, cur);
        index = 0;
      } else {
        q.shuffle();
      }
    } else {
      final cur = (index >= 0 && index < q.length) ? q[index] : null;
      final restored = List.of(_orig);
      _orig = [];
      index = cur == null ? -1 : restored.indexWhere((e) => e.id == cur.id);
      if (index < 0 && restored.isNotEmpty && cur != null) index = 0;
      q
        ..clear()
        ..addAll(restored);
    }
    queue.add(q);
    _broadcast();
  }

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode m) async {
    _repeat = m;
    _broadcast();
  }

  // ───────── queue editing ─────────
  @override
  Future<void> addQueueItem(MediaItem m) async {
    if (index < 0) return playItems([m], 0);
    queue.add([...queue.value, m]);
    if (_orig.isNotEmpty) _orig = [..._orig, m];
  }

  Future<void> playNext(MediaItem m) async {
    if (index < 0) return playItems([m], 0);
    final q = [...queue.value];
    q.insert(math.min(index + 1, q.length), m);
    queue.add(q);
  }

  @override
  Future<void> removeQueueItemAt(int i) async {
    if (i == index) return;
    final q = [...queue.value];
    q.removeAt(i);
    if (i < index) index--;
    queue.add(q);
    _broadcast();
  }

  void moveQueueItem(int o, int n) {
    final q = [...queue.value];
    final m = q.removeAt(o);
    q.insert(n, m);
    if (o == index) {
      index = n;
    } else if (o < index && n >= index) {
      index--;
    } else if (o > index && n <= index) {
      index++;
    }
    queue.add(q);
    _broadcast();
  }

  // ───────── sleep timer ─────────
  void setSleep(int? minutes) {
    _sleep?.cancel();
    sleepEnd.value = minutes == null ? null : DateTime.now().add(Duration(minutes: minutes));
    if (minutes != null) {
      _sleep = Timer(Duration(minutes: minutes), () {
        _p.pause();
        sleepEnd.value = null;
      });
    }
  }

  // ───────── equalizer ─────────
  Future<void> setBand(int i, double v) async {
    gains[i] = v;
    eqOn = true;
    await _applyEq(eqA);
    await _applyEq(eqB);
  }

  Future<void> resetEq() async {
    gains.clear();
    eqOn = false;
    for (final e in [eqA, eqB]) {
      try {
        final p = await e.parameters.timeout(const Duration(seconds: 2));
        for (final b in p.bands) {
          b.setGain(0);
        }
        await e.setEnabled(false);
      } catch (_) {}
    }
  }

  Future<void> _applyEq(AndroidEqualizer e) async {
    if (!eqOn) return;
    try {
      await e.setEnabled(true);
      final p = await e.parameters.timeout(const Duration(seconds: 2));
      gains.forEach((i, g) {
        if (i < p.bands.length) p.bands[i].setGain(g);
      });
    } catch (_) {}
  }

  // ───────── Android Auto browse tree ─────────
  MediaItem _folder(String id, String title) => MediaItem(id: id, title: title, playable: false);

  Future<List<Track>> _tracksFor(String key) async {
    if (key == 'liked') return store.liked;
    if (key == 'recent') return store.recents;
    if (key == 'downloads') return store.dlTracks;
    if (key == 'trending') return store.trending();
    if (key == 'search') return _lastSearch;
    if (key.startsWith('pl:')) return store.playlists[key.substring(3)] ?? [];
    return [];
  }

  @override
  Future<List<MediaItem>> getChildren(String parentMediaId, [Map<String, dynamic>? options]) async {
    if (parentMediaId == AudioService.browsableRootId) {
      return [
        _folder('liked', 'Liked songs'),
        _folder('recent', 'Recently played'),
        _folder('playlists', 'Playlists'),
        _folder('downloads', 'Downloads'),
        _folder('trending', 'Trending'),
      ];
    }
    if (parentMediaId == 'playlists') {
      return store.playlists.keys.map((k) => _folder('pl:$k', k)).toList();
    }
    final list = await _tracksFor(parentMediaId);
    return list.map((t) => t.toItem(idOverride: '$parentMediaId|${t.id}')).toList();
  }

  @override
  Future<List<MediaItem>> search(String query, [Map<String, dynamic>? extras]) async {
    try {
      _lastSearch = await store.search(query);
    } catch (_) {
      _lastSearch = [];
    }
    return _lastSearch.map((t) => t.toItem(idOverride: 'search|${t.id}')).toList();
  }

  @override
  Future<void> playFromMediaId(String mediaId, [Map<String, dynamic>? extras]) async {
    final i = mediaId.indexOf('|');
    if (i < 0) return;
    final key = mediaId.substring(0, i), id = mediaId.substring(i + 1);
    final list = await _tracksFor(key);
    final idx = list.indexWhere((t) => t.id == id);
    if (idx < 0) return;
    await playItems(list.map((t) => t.toItem()).toList(), idx);
  }

  @override
  Future<void> playFromSearch(String query, [Map<String, dynamic>? extras]) async {
    final r = await store.search(query);
    if (r.isNotEmpty) {
      _lastSearch = r;
      await playItems(r.map((t) => t.toItem()).toList(), 0);
    }
  }
}
