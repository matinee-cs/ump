import 'dart:ui';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';

import 'common.dart';
import 'lyrics.dart';
import 'models.dart';
import 'store.dart';

// ───────────── MINI PLAYER ─────────────
void openPlayer(BuildContext c) => Navigator.of(c).push(PageRouteBuilder(
      transitionDuration: const Duration(milliseconds: 520),
      reverseTransitionDuration: const Duration(milliseconds: 420),
      pageBuilder: (_, __, ___) => const NowPlayingPage(),
      transitionsBuilder: (_, a, __, child) {
        final curved = CurvedAnimation(parent: a, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic);
        return SlideTransition(position: Tween(begin: const Offset(0, 1), end: Offset.zero).animate(curved), child: child);
      },
    ));

class MiniBar extends StatelessWidget {
  const MiniBar({super.key});
  @override
  Widget build(BuildContext context) => StreamBuilder<MediaItem?>(
        stream: handler.mediaItem,
        builder: (_, s) {
          final m = s.data;
          return AnimatedSize(
            duration: const Duration(milliseconds: 380),
            curve: Curves.easeOutCubic,
            child: m == null
                ? const SizedBox(width: double.infinity)
                : Padding(padding: const EdgeInsets.fromLTRB(10, 0, 10, 8), child: MiniPlayer(item: m)),
          );
        },
      );
}

class MiniPlayer extends StatelessWidget {
  final MediaItem item;
  const MiniPlayer({super.key, required this.item});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onVerticalDragEnd: (d) {
        if ((d.primaryVelocity ?? 0) < -250) openPlayer(context);
      },
      child: Material(
        color: cs.secondaryContainer,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => openPlayer(context),
          child: Stack(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 4, 10),
              child: Row(children: [
                Hero(tag: 'cover', child: Art(item.artUri?.toString() ?? '', size: 48, radius: 18)),
                const SizedBox(width: 12),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: Column(
                      key: ValueKey(item.id),
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontWeight: FontWeight.w700, color: cs.onSecondaryContainer)),
                        Text(item.artist ?? '', maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 12, color: cs.onSecondaryContainer.withOpacity(0.7))),
                      ],
                    ),
                  ),
                ),
                PlayButton(size: 30, color: cs.onSecondaryContainer),
                IconButton(
                  icon: Icon(Icons.skip_next_rounded, size: 30, color: cs.onSecondaryContainer),
                  onPressed: handler.skipToNext,
                ),
              ]),
            ),
            Positioned(
              left: 0, right: 0, bottom: 0,
              child: StreamBuilder<Duration>(
                stream: AudioService.position,
                builder: (_, s) {
                  final d = item.duration?.inMilliseconds ?? 0;
                  final v = d > 0 ? ((s.data?.inMilliseconds ?? 0) / d).clamp(0.0, 1.0) : 0.0;
                  return LinearProgressIndicator(value: v, minHeight: 3, backgroundColor: Colors.transparent, color: cs.primary);
                },
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class PlayButton extends StatelessWidget {
  final double size;
  final Color? color;
  const PlayButton({super.key, required this.size, this.color});
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<PlaybackState>(
      stream: handler.playbackState,
      builder: (_, s) {
        final st = s.data;
        final playing = st?.playing ?? false;
        if (st?.processingState == AudioProcessingState.loading) {
          return Padding(
            padding: const EdgeInsets.all(12),
            child: SizedBox(width: size - 10, height: size - 10, child: CircularProgressIndicator(strokeWidth: 2.5, color: color)),
          );
        }
        return IconButton(
          iconSize: size,
          color: color,
          icon: AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            transitionBuilder: (c, a) => ScaleTransition(scale: a, child: FadeTransition(opacity: a, child: c)),
            child: Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded, key: ValueKey(playing)),
          ),
          onPressed: () => playing ? handler.pause() : handler.play(),
        );
      },
    );
  }
}

// ───────────── SEEK BAR ─────────────
class SeekBar extends StatefulWidget {
  final Duration duration;
  const SeekBar(this.duration, {super.key});
  @override
  State<SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends State<SeekBar> {
  double? drag;
  String fmt(Duration d) => '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final max = widget.duration.inMilliseconds.toDouble().clamp(1.0, double.infinity);
    return StreamBuilder<Duration>(
      stream: AudioService.position,
      builder: (_, s) {
        final pos = s.data ?? Duration.zero;
        final v = (drag ?? pos.inMilliseconds.toDouble()).clamp(0.0, max);
        final st = TextStyle(color: cs.onSurface.withOpacity(0.65), fontSize: 12, fontWeight: FontWeight.w600);
        return Column(children: [
          Slider(
            value: v,
            max: max,
            onChanged: (x) => setState(() => drag = x),
            onChangeEnd: (x) {
              handler.seek(Duration(milliseconds: x.round()));
              setState(() => drag = null);
            },
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text(fmt(Duration(milliseconds: v.round())), style: st),
              Text(fmt(widget.duration), style: st),
            ]),
          ),
        ]);
      },
    );
  }
}

// ───────────── NOW PLAYING ─────────────
class NowPlayingPage extends StatefulWidget {
  const NowPlayingPage({super.key});
  @override
  State<NowPlayingPage> createState() => _NowPlayingPageState();
}

class _NowPlayingPageState extends State<NowPlayingPage> {
  int view = 0; // 0 cover, 1 lyrics, 2 queue

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final h = MediaQuery.of(context).size.height;
    return StreamBuilder<MediaItem?>(
      stream: handler.mediaItem,
      builder: (context, snap) {
        final m = snap.data;
        if (m == null) return const Scaffold();
        final t = Track.fromItem(m);
        final art = m.artUri?.toString() ?? '';
        return Scaffold(
          body: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onVerticalDragEnd: (d) {
              if ((d.primaryVelocity ?? 0) > 800) Navigator.pop(context);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 600),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [cs.primaryContainer, cs.surface],
                  stops: const [0.0, 0.8],
                ),
              ),
              child: SafeArea(
                child: Column(children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
                    child: Row(children: [
                      IconButton(icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 32), onPressed: () => Navigator.pop(context)),
                      Expanded(
                        child: Center(
                          child: SegmentedButton<int>(
                            showSelectedIcon: false,
                            style: const ButtonStyle(visualDensity: VisualDensity.compact),
                            segments: const [
                              ButtonSegment(value: 0, label: Text('Cover')),
                              ButtonSegment(value: 1, label: Text('Lyrics')),
                              ButtonSegment(value: 2, label: Text('Queue')),
                            ],
                            selected: {view},
                            onSelectionChanged: (s) => setState(() => view = s.first),
                          ),
                        ),
                      ),
                      _MoreMenu(t: t, h: h),
                    ]),
                  ),
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 380),
                      switchInCurve: Curves.easeOutCubic,
                      transitionBuilder: (c, a) => FadeTransition(
                        opacity: a,
                        child: ScaleTransition(scale: Tween(begin: 0.96, end: 1.0).animate(a), child: c),
                      ),
                      child: switch (view) {
                        0 => _Cover(key: const ValueKey('c'), art: art),
                        1 => LyricsPanel(key: ValueKey('l${t.id}'), t: t),
                        _ => const QueuePanel(key: ValueKey('q')),
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(26, 6, 14, 0),
                    child: Row(children: [
                      Expanded(
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 320),
                          transitionBuilder: (c, a) => FadeTransition(
                              opacity: a,
                              child: SlideTransition(position: Tween(begin: const Offset(0, 0.25), end: Offset.zero).animate(a), child: c)),
                          child: Column(
                            key: ValueKey(m.id),
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(m.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.4)),
                              const SizedBox(height: 2),
                              Text(m.artist ?? '', maxLines: 1, overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontSize: 15, color: cs.primary, fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ),
                      ),
                      ListenableBuilder(
                        listenable: store,
                        builder: (_, __) {
                          final liked = store.isLiked(t);
                          return IconButton.filledTonal(
                            iconSize: 24,
                            onPressed: () => store.toggleLike(t),
                            icon: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 260),
                              transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
                              child: Icon(liked ? Icons.favorite_rounded : Icons.favorite_border_rounded, key: ValueKey(liked)),
                            ),
                          );
                        },
                      ),
                    ]),
                  ),
                  const SizedBox(height: 6),
                  SeekBar(m.duration ?? Duration.zero),
                  _Controls(cs: cs),
                  const SizedBox(height: 14),
                ]),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Cover extends StatelessWidget {
  final String art;
  const _Cover({super.key, required this.art});
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<PlaybackState>(
      stream: handler.playbackState,
      builder: (_, s) {
        final playing = s.data?.playing ?? false;
        return Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
            child: AnimatedScale(
              scale: playing ? 1.0 : 0.88,
              duration: const Duration(milliseconds: 500),
              curve: Curves.easeOutBack,
              child: Hero(
                tag: 'cover',
                child: AspectRatio(
                  aspectRatio: 1,
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(36),
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.45), blurRadius: 40, offset: const Offset(0, 18))],
                    ),
                    child: LayoutBuilder(builder: (_, c) => Art(art, size: c.maxWidth, radius: 36)),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Controls extends StatelessWidget {
  final ColorScheme cs;
  const _Controls({required this.cs});
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<PlaybackState>(
      stream: handler.playbackState,
      builder: (_, s) {
        final st = s.data;
        final playing = st?.playing ?? false;
        final loading = st?.processingState == AudioProcessingState.loading;
        final shuf = st?.shuffleMode == AudioServiceShuffleMode.all;
        final rep = st?.repeatMode ?? AudioServiceRepeatMode.none;
        return Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
          IconButton(
            icon: Icon(Icons.shuffle_rounded, color: shuf ? cs.primary : cs.onSurface.withOpacity(0.5)),
            onPressed: () => handler.setShuffleMode(shuf ? AudioServiceShuffleMode.none : AudioServiceShuffleMode.all),
          ),
          IconButton(iconSize: 40, icon: const Icon(Icons.skip_previous_rounded), onPressed: handler.skipToPrevious),
          // the button morphs: circle when paused, rounded square when playing
          GestureDetector(
            onTap: () => playing ? handler.pause() : handler.play(),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 320),
              curve: Curves.easeOutBack,
              width: 82,
              height: 76,
              decoration: BoxDecoration(color: cs.primary, borderRadius: BorderRadius.circular(playing ? 26 : 40)),
              child: Center(
                child: loading
                    ? SizedBox(width: 30, height: 30, child: CircularProgressIndicator(strokeWidth: 3, color: cs.onPrimary))
                    : AnimatedSwitcher(
                        duration: const Duration(milliseconds: 220),
                        transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
                        child: Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                            key: ValueKey(playing), size: 44, color: cs.onPrimary),
                      ),
              ),
            ),
          ),
          IconButton(iconSize: 40, icon: const Icon(Icons.skip_next_rounded), onPressed: handler.skipToNext),
          IconButton(
            icon: Icon(rep == AudioServiceRepeatMode.one ? Icons.repeat_one_rounded : Icons.repeat_rounded,
                color: rep == AudioServiceRepeatMode.none ? cs.onSurface.withOpacity(0.5) : cs.primary),
            onPressed: () => handler.setRepeatMode(switch (rep) {
              AudioServiceRepeatMode.none => AudioServiceRepeatMode.all,
              AudioServiceRepeatMode.all => AudioServiceRepeatMode.one,
              _ => AudioServiceRepeatMode.none,
            }),
          ),
        ]);
      },
    );
  }
}

class _MoreMenu extends StatelessWidget {
  final Track t;
  final double h;
  const _MoreMenu({required this.t, required this.h});
  @override
  Widget build(BuildContext context) {
    PopupMenuItem<String> it(String v, String l, IconData i) =>
        PopupMenuItem(value: v, child: Row(children: [Icon(i, size: 20), const SizedBox(width: 12), Text(l)]));
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert_rounded),
      onSelected: (v) {
        switch (v) {
          case 'pl':
            pickPlaylist(context, t);
          case 'dl':
            store.download(t);
            toast('Downloading…');
          case 'sleep':
            sheet(context, const SleepView());
          case 'cf':
            sheet(context, const CrossfadeView());
          case 'eq':
            sheet(context, const EqView(), height: h * 0.6);
        }
      },
      itemBuilder: (_) => [
        it('pl', 'Add to playlist', Icons.playlist_add_rounded),
        it('dl', 'Download', Icons.download_rounded),
        it('cf', 'Crossfade', Icons.blur_on_rounded),
        it('sleep', 'Sleep timer', Icons.bedtime_rounded),
        it('eq', 'Equalizer', Icons.equalizer_rounded),
      ],
    );
  }
}

void pickPlaylist(BuildContext ctx, Track t) {
  sheet(
    ctx,
    ListenableBuilder(
      listenable: store,
      builder: (c, _) => ListView(shrinkWrap: true, children: [
        ListTile(
          leading: const Icon(Icons.add_rounded),
          title: const Text('New playlist'),
          onTap: () async {
            final n = await askName(c);
            if (n != null) {
              store.createPlaylist(n);
              store.addToPlaylist(n, t);
            }
            if (c.mounted) Navigator.pop(c);
          },
        ),
        for (final n in store.playlists.keys)
          ListTile(
            leading: const Icon(Icons.queue_music_rounded),
            title: Text(n),
            subtitle: Text('${store.playlists[n]!.length} songs'),
            onTap: () {
              store.addToPlaylist(n, t);
              Navigator.pop(c);
              toast('Added to $n');
            },
          ),
      ]),
    ),
  );
}

// ───────────── LYRICS (inside the player) ─────────────
class LyricsPanel extends StatefulWidget {
  final Track t;
  const LyricsPanel({super.key, required this.t});
  @override
  State<LyricsPanel> createState() => _LyricsPanelState();
}

class _LyricsPanelState extends State<LyricsPanel> {
  late final Future<Lyrics?> f = LyricsService.get(widget.t);
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return FutureBuilder<Lyrics?>(
      future: f,
      builder: (_, s) {
        if (s.connectionState != ConnectionState.done) {
          return Center(child: CircularProgressIndicator(color: cs.primary));
        }
        final l = s.data;
        if (l == null) {
          return Center(child: Text('No lyrics found for this song.', style: TextStyle(color: cs.onSurface.withOpacity(0.6))));
        }
        if (l.isSynced) return SyncedLyrics(lines: l.synced);
        return SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: Text(l.plain, style: const TextStyle(fontSize: 22, height: 1.6, fontWeight: FontWeight.w700)),
        );
      },
    );
  }
}

class SyncedLyrics extends StatefulWidget {
  final List<LyricLine> lines;
  const SyncedLyrics({super.key, required this.lines});
  @override
  State<SyncedLyrics> createState() => _SyncedLyricsState();
}

class _SyncedLyricsState extends State<SyncedLyrics> {
  late final keys = List.generate(widget.lines.length, (_) => GlobalKey());
  int cur = -2;

  int _indexAt(Duration p) {
    var idx = -1;
    final at = p + const Duration(milliseconds: 180);
    for (var i = 0; i < widget.lines.length; i++) {
      if (widget.lines[i].t <= at) {
        idx = i;
      } else {
        break;
      }
    }
    return idx;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return StreamBuilder<Duration>(
      stream: AudioService.position,
      builder: (_, s) {
        final idx = _indexAt(s.data ?? Duration.zero);
        if (idx != cur) {
          cur = idx;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            final c = idx >= 0 ? keys[idx].currentContext : null;
            if (c != null) {
              Scrollable.ensureVisible(c, alignment: 0.36, duration: const Duration(milliseconds: 650), curve: Curves.easeOutCubic);
            }
          });
        }
        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 150, horizontal: 26),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (var i = 0; i < widget.lines.length; i++)
              GestureDetector(
                key: keys[i],
                behavior: HitTestBehavior.opaque,
                onTap: () => handler.seek(widget.lines[i].t),
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 400),
                  opacity: i == idx ? 1 : (i < idx ? 0.28 : 0.4),
                  child: AnimatedScale(
                    duration: const Duration(milliseconds: 400),
                    curve: Curves.easeOutCubic,
                    alignment: Alignment.centerLeft,
                    scale: i == idx ? 1.0 : 0.88,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Text(
                        widget.lines[i].text.isEmpty ? '♪' : widget.lines[i].text,
                        style: TextStyle(fontSize: 28, height: 1.25, fontWeight: FontWeight.w800, color: cs.onSurface),
                      ),
                    ),
                  ),
                ),
              ),
          ]),
        );
      },
    );
  }
}

// ───────────── QUEUE ─────────────
class QueuePanel extends StatelessWidget {
  const QueuePanel({super.key});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return StreamBuilder<List<MediaItem>>(
      stream: handler.queue,
      builder: (_, s) {
        final q = s.data ?? [];
        return ReorderableListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          itemCount: q.length,
          onReorder: (o, n) {
            if (n > o) n--;
            handler.moveQueueItem(o, n);
          },
          itemBuilder: (_, i) {
            final m = q[i];
            final cur = i == handler.index;
            return ListTile(
              key: ValueKey('q$i${m.id}'),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              tileColor: cur ? cs.primaryContainer.withOpacity(0.6) : null,
              leading: Art(m.artUri?.toString() ?? '', size: 46),
              title: Text(m.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontWeight: FontWeight.w700, color: cur ? cs.primary : cs.onSurface)),
              subtitle: Text(m.artist ?? '', maxLines: 1, overflow: TextOverflow.ellipsis),
              onTap: () => handler.skipToQueueItem(i),
              trailing: cur
                  ? EqBars(color: cs.primary)
                  : IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => handler.removeQueueItemAt(i)),
            );
          },
        );
      },
    );
  }
}

// ───────────── SHEETS ─────────────
class CrossfadeView extends StatelessWidget {
  const CrossfadeView({super.key});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: store,
        builder: (_, __) => Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text('Crossfade', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              Text(store.crossfade == 0 ? 'Off' : '${store.crossfade.round()} s',
                  style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w700)),
            ]),
            const SizedBox(height: 4),
            const Text('Songs blend into each other instead of stopping.'),
            Slider(value: store.crossfade, min: 0, max: 12, divisions: 12, onChanged: store.setCrossfade),
          ]),
        ),
      );
}

class SleepView extends StatelessWidget {
  const SleepView({super.key});
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<DateTime?>(
        valueListenable: handler.sleepEnd,
        builder: (c, end, _) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(end == null ? 'Sleep timer' : 'Stops at ${TimeOfDay.fromDateTime(end).format(c)}',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 14),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final m in [15, 30, 45, 60, 90])
                ActionChip(label: Text('$m min'), onPressed: () {
                  handler.setSleep(m);
                  Navigator.pop(c);
                }),
              if (end != null)
                FilledButton.tonal(onPressed: () {
                  handler.setSleep(null);
                  Navigator.pop(c);
                }, child: const Text('Turn off')),
            ]),
          ]),
        ),
      );
}

class EqView extends StatefulWidget {
  const EqView({super.key});
  @override
  State<EqView> createState() => _EqViewState();
}

class _EqViewState extends State<EqView> {
  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: handler.eqA.parameters.timeout(const Duration(seconds: 3)),
      builder: (_, s) {
        if (s.hasError) {
          return const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('Equalizer is not available right now.')));
        }
        if (!s.hasData) return const Center(child: CircularProgressIndicator());
        final p = s.data!;
        return ListView(padding: const EdgeInsets.fromLTRB(24, 0, 24, 24), children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const Text('Equalizer', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            TextButton(onPressed: () async { await handler.resetEq(); setState(() {}); }, child: const Text('Reset')),
          ]),
          for (var i = 0; i < p.bands.length; i++)
            Row(children: [
              SizedBox(
                width: 64,
                child: Text(
                  p.bands[i].centerFrequency < 1000
                      ? '${p.bands[i].centerFrequency.round()} Hz'
                      : '${(p.bands[i].centerFrequency / 1000).toStringAsFixed(1)} kHz',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
              Expanded(
                child: Slider(
                  value: (handler.gains[i] ?? 0).clamp(p.minDecibels, p.maxDecibels),
                  min: p.minDecibels,
                  max: p.maxDecibels,
                  onChanged: (v) {
                    handler.setBand(i, v);
                    setState(() {});
                  },
                ),
              ),
            ]),
        ]);
      },
    );
  }
}
