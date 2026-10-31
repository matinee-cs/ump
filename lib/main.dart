import 'dart:convert';
import 'dart:ui';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;

import 'handler.dart';
import 'models.dart';
import 'store.dart';

// ───────────── UMP THEME ─────────────
const ink = Color(0xFF0C1410); // base
const moss = Color(0xFF172620); // surfaces
const mist = Color(0xFFE9F1E7); // text
const leaf = Color(0xFF8FE388); // brand green
const ember = Color(0xFFFFB347); // play / progress

late WeedHandler handler;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await store.load();
  handler = await AudioService.init(
    builder: () => WeedHandler(),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.weed.audio',
      androidNotificationChannelName: 'UMP playback',
      androidNotificationOngoing: true,
      // Android Auto: categories as a grid, songs as a list
      androidBrowsableRootExtras: {
        'android.media.browse.CONTENT_STYLE_SUPPORTED': true,
        'android.media.browse.CONTENT_STYLE_BROWSABLE_HINT': 2,
        'android.media.browse.CONTENT_STYLE_PLAYABLE_HINT': 1,
      },
    ),
  );
  runApp(const WeedApp());
}

ThemeData weedTheme() {
  final base = ThemeData.dark(useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: ink,
    colorScheme: const ColorScheme.dark(primary: leaf, secondary: ember, surface: moss),
    textTheme: GoogleFonts.bricolageGrotesqueTextTheme(base.textTheme).apply(bodyColor: mist, displayColor: mist),
    sliderTheme: SliderThemeData(
      trackHeight: 4,
      activeTrackColor: ember,
      inactiveTrackColor: mist.withOpacity(0.18),
      thumbColor: ember,
      overlayShape: SliderComponentShape.noOverlay,
      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: moss.withOpacity(0.92),
      indicatorColor: leaf.withOpacity(0.22),
      labelTextStyle: WidgetStatePropertyAll(GoogleFonts.bricolageGrotesque(fontSize: 12, fontWeight: FontWeight.w600)),
    ),
  );
}

class WeedApp extends StatelessWidget {
  const WeedApp({super.key});
  @override
  Widget build(BuildContext context) =>
      MaterialApp(title: 'UMP', debugShowCheckedModeBanner: false, theme: weedTheme(), home: const Shell());
}

// ───────────── SMALL HELPERS ─────────────
class Art extends StatelessWidget {
  final String url;
  final double size, radius;
  const Art(this.url, {super.key, this.size = 54, this.radius = 10});
  @override
  Widget build(BuildContext context) {
    final ph = Container(color: moss, child: const Icon(Icons.music_note_rounded, color: leaf));
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        width: size,
        height: size,
        child: url.isEmpty ? ph : Image.network(url, fit: BoxFit.cover, errorBuilder: (_, __, ___) => ph),
      ),
    );
  }
}

class Backdrop extends StatelessWidget {
  final String? art;
  const Backdrop({super.key, this.art});
  @override
  Widget build(BuildContext context) {
    final has = art != null && art!.isNotEmpty;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 900),
      child: !has
          ? Container(key: const ValueKey('none'), color: ink)
          : Stack(key: ValueKey(art), fit: StackFit.expand, children: [
              Container(color: ink),
              Opacity(
                opacity: 0.5,
                child: ImageFiltered(
                  imageFilter: ImageFilter.blur(sigmaX: 60, sigmaY: 60),
                  child: Image.network(art!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox()),
                ),
              ),
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [ink.withOpacity(0.35), ink.withOpacity(0.93)],
                  ),
                ),
              ),
            ]),
    );
  }
}

void toast(BuildContext c, String s) =>
    ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(s), duration: const Duration(seconds: 2)));

void playList(List<Track> l, int i) => handler.playItems(l.map((e) => e.toItem()).toList(), i);

Future<String?> askName(BuildContext c) {
  final ctrl = TextEditingController();
  return showDialog<String>(
    context: c,
    builder: (_) => AlertDialog(
      backgroundColor: moss,
      title: const Text('New playlist'),
      content: TextField(controller: ctrl, autofocus: true, decoration: const InputDecoration(hintText: 'Playlist name')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
        TextButton(
          onPressed: () => Navigator.pop(c, ctrl.text.trim().isEmpty ? null : ctrl.text.trim()),
          child: const Text('Create'),
        ),
      ],
    ),
  );
}

void sheet(BuildContext c, Widget child, {double? height}) => showModalBottomSheet(
      context: c,
      isScrollControlled: true,
      backgroundColor: moss,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (_) => SizedBox(height: height, child: child),
    );

void pickPlaylist(BuildContext ctx, Track t) {
  sheet(
    ctx,
    ListenableBuilder(
      listenable: store,
      builder: (c, _) => ListView(shrinkWrap: true, children: [
        ListTile(
          leading: const Icon(Icons.add_rounded, color: leaf),
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
              toast(ctx, 'Added to $n');
            },
          ),
      ]),
    ),
  );
}

// ───────────── SHELL ─────────────
class Shell extends StatefulWidget {
  const Shell({super.key});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int tab = 0;
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<MediaItem?>(
      stream: handler.mediaItem,
      builder: (context, snap) {
        final m = snap.data;
        return Scaffold(
          body: Stack(children: [
            Positioned.fill(child: Backdrop(art: m?.artUri?.toString())),
            SafeArea(
              bottom: false,
              child: IndexedStack(index: tab, children: const [HomeTab(), SearchTab(), LibraryTab()]),
            ),
          ]),
          bottomNavigationBar: Column(mainAxisSize: MainAxisSize.min, children: [
            if (m != null) Padding(padding: const EdgeInsets.fromLTRB(10, 0, 10, 8), child: MiniPlayer(item: m)),
            NavigationBar(
              selectedIndex: tab,
              onDestinationSelected: (i) => setState(() => tab = i),
              destinations: const [
                NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home_rounded), label: 'Home'),
                NavigationDestination(icon: Icon(Icons.search_rounded), label: 'Search'),
                NavigationDestination(icon: Icon(Icons.library_music_outlined), selectedIcon: Icon(Icons.library_music_rounded), label: 'Library'),
              ],
            ),
          ]),
        );
      },
    );
  }
}

// ───────────── TRACK TILE ─────────────
class TrackTile extends StatelessWidget {
  final Track t;
  final List<Track> list;
  final int i;
  final String? playlist;
  const TrackTile(this.t, this.list, this.i, {super.key, this.playlist});

  PopupMenuItem<String> _it(String v, String label, IconData ic) => PopupMenuItem(
        value: v,
        child: Row(children: [Icon(ic, size: 20, color: leaf), const SizedBox(width: 12), Text(label)]),
      );

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (ctx, _) {
        final dl = store.downloads.containsKey(t.id);
        final prog = store.progress[t.id];
        return StreamBuilder<MediaItem?>(
          stream: handler.mediaItem,
          builder: (_, s) {
            final on = s.data?.id == t.id;
            return ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
              leading: Art(t.art),
              title: Text(t.title,
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontWeight: FontWeight.w600, color: on ? leaf : mist)),
              subtitle: Text(t.artist,
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: mist.withOpacity(0.55))),
              onTap: () => playList(list, i),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                if (prog != null)
                  SizedBox(width: 18, height: 18, child: CircularProgressIndicator(value: prog, strokeWidth: 2.5, color: leaf))
                else if (dl)
                  const Icon(Icons.download_done_rounded, size: 18, color: leaf),
                PopupMenuButton<String>(
                  color: moss,
                  icon: const Icon(Icons.more_vert_rounded),
                  onSelected: (v) {
                    switch (v) {
                      case 'next':
                        handler.playNext(t.toItem());
                        toast(ctx, 'Will play next');
                      case 'queue':
                        handler.addQueueItem(t.toItem());
                        toast(ctx, 'Added to queue');
                      case 'like':
                        store.toggleLike(t);
                      case 'pl':
                        pickPlaylist(ctx, t);
                      case 'dl':
                        store.download(t);
                        toast(ctx, 'Downloading…');
                      case 'rmdl':
                        store.deleteDownload(t);
                      case 'rm':
                        store.removeFromPlaylist(playlist!, t);
                    }
                  },
                  itemBuilder: (_) => [
                    _it('next', 'Play next', Icons.queue_play_next_rounded),
                    _it('queue', 'Add to queue', Icons.playlist_add_rounded),
                    _it('like', store.isLiked(t) ? 'Remove from liked' : 'Like', store.isLiked(t) ? Icons.favorite_rounded : Icons.favorite_border_rounded),
                    _it('pl', 'Add to playlist', Icons.queue_music_rounded),
                    dl ? _it('rmdl', 'Remove download', Icons.delete_outline_rounded) : _it('dl', 'Download', Icons.download_rounded),
                    if (playlist != null) _it('rm', 'Remove from this playlist', Icons.remove_circle_outline_rounded),
                  ],
                ),
              ]),
            );
          },
        );
      },
    );
  }
}

// ───────────── HOME ─────────────
const shelfDefs = {
  'Latest Hindi songs': 'latest hindi songs 2026',
  'Latest Punjabi songs': 'latest punjabi songs 2026',
  'Haryanvi hits': 'latest haryanvi songs 2026',
  'Punjabi hits': 'new punjabi song',
  'New Haryanvi': 'new haryanvi song',
  'Trending now': 'trending songs',
  'English pop': 'top english pop hits',
  'Lo-fi chill': 'lofi chill beats',
};

class HomeTab extends StatelessWidget {
  const HomeTab({super.key});
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) => ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
            child: Row(children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Container(color: ink, width: 46, height: 46, child: Image.asset('assets/icon_fg.png', fit: BoxFit.cover)),
              ),
              const SizedBox(width: 12),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('UMP', style: GoogleFonts.bricolageGrotesque(fontSize: 38, fontWeight: FontWeight.w800, letterSpacing: -1.5, height: 1.0)),
                Text('Unidentified Music Player', style: TextStyle(fontSize: 12, color: mist.withOpacity(0.55))),
              ]),
            ]),
          ),
          if (store.recents.isNotEmpty) Shelf('Pick up where you left off', store.recents),
          FutureBuilder<List<Track>>(
            future: store.recommended(),
            builder: (_, s) => (s.hasData && s.data!.isNotEmpty) ? Shelf('Recommended for you', s.data!) : const SizedBox(),
          ),
          for (final e in shelfDefs.entries)
            FutureBuilder<List<Track>>(
              future: store.shelf(e.value),
              builder: (_, s) => s.hasData && s.data!.isNotEmpty
                  ? Shelf(e.key, s.data!)
                  : Padding(
                      padding: const EdgeInsets.all(20),
                      child: Text(s.connectionState == ConnectionState.done ? '' : 'Loading ${e.key}…',
                          style: TextStyle(color: mist.withOpacity(0.4))),
                    ),
            ),
        ],
      ),
    );
  }
}

class Shelf extends StatelessWidget {
  final String title;
  final List<Track> tracks;
  const Shelf(this.title, this.tracks, {super.key});
  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
        child: Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -0.4)),
      ),
      SizedBox(
        height: 196,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          itemCount: tracks.length,
          itemBuilder: (_, i) {
            final t = tracks[i];
            return GestureDetector(
              onTap: () => playList(tracks, i),
              child: Container(
                width: 140,
                margin: const EdgeInsets.symmetric(horizontal: 6),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Art(t.art, size: 140, radius: 18),
                  const SizedBox(height: 8),
                  Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                  Text(t.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: mist.withOpacity(0.55), fontSize: 12)),
                ]),
              ),
            );
          },
        ),
      ),
    ]);
  }
}

// ───────────── SEARCH ─────────────
class SearchTab extends StatefulWidget {
  const SearchTab({super.key});
  @override
  State<SearchTab> createState() => _SearchTabState();
}

class _SearchTabState extends State<SearchTab> {
  final ctrl = TextEditingController();
  List<Track> results = [];
  bool busy = false;
  String? msg;

  Future<void> run(String q) async {
    q = q.trim();
    if (q.isEmpty) return;
    ctrl.text = q;
    store.addHistory(q);
    setState(() {
      busy = true;
      msg = null;
    });
    try {
      final r = await store.search(q);
      setState(() {
        results = r;
        if (r.isEmpty) msg = 'No results for "$q".';
      });
    } catch (_) {
      setState(() => msg = 'Search failed. Check your internet and try again.');
    }
    setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 4),
        child: Text('Search', style: GoogleFonts.bricolageGrotesque(fontSize: 34, fontWeight: FontWeight.w800, letterSpacing: -1)),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: TextField(
          controller: ctrl,
          onSubmitted: run,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: 'Songs, artists',
            filled: true,
            fillColor: mist.withOpacity(0.10),
            prefixIcon: const Icon(Icons.search_rounded),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
          ),
        ),
      ),
      if (busy) const LinearProgressIndicator(minHeight: 2, color: leaf, backgroundColor: Colors.transparent),
      if (msg != null) Padding(padding: const EdgeInsets.all(20), child: Text(msg!, style: TextStyle(color: mist.withOpacity(0.6)))),
      Expanded(
        child: results.isEmpty && !busy
            ? ListenableBuilder(
                listenable: store,
                builder: (_, __) => ListView(padding: const EdgeInsets.symmetric(horizontal: 16), children: [
                  if (store.history.isNotEmpty) ...[
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      const Text('Recent searches', style: TextStyle(fontWeight: FontWeight.w700)),
                      TextButton(onPressed: store.clearHistory, child: const Text('Clear')),
                    ]),
                    Wrap(spacing: 8, runSpacing: 4, children: [
                      for (final h in store.history) ActionChip(label: Text(h), backgroundColor: moss, onPressed: () => run(h)),
                    ]),
                  ] else
                    Text('Type a song or artist and press search.', style: TextStyle(color: mist.withOpacity(0.5))),
                ]),
              )
            : ListView.builder(
                padding: const EdgeInsets.only(bottom: 16),
                itemCount: results.length,
                itemBuilder: (_, i) => TrackTile(results[i], results, i),
              ),
      ),
    ]);
  }
}

// ───────────── LIBRARY ─────────────
class LibraryTab extends StatelessWidget {
  const LibraryTab({super.key});

  Widget _row(BuildContext c, IconData ic, String title, int n, Widget page) => ListTile(
        leading: Container(
          width: 54, height: 54,
          decoration: BoxDecoration(color: leaf.withOpacity(0.15), borderRadius: BorderRadius.circular(12)),
          child: Icon(ic, color: leaf),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text('$n songs', style: TextStyle(color: mist.withOpacity(0.55))),
        onTap: () => Navigator.push(c, MaterialPageRoute(builder: (_) => page)),
      );

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (c, _) => ListView(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
          child: Text('Library', style: GoogleFonts.bricolageGrotesque(fontSize: 34, fontWeight: FontWeight.w800, letterSpacing: -1)),
        ),
        _row(c, Icons.favorite_rounded, 'Liked songs', store.liked.length, ListPage('Liked songs', () => store.liked)),
        _row(c, Icons.download_done_rounded, 'Downloads', store.dlTracks.length, ListPage('Downloads', () => store.dlTracks)),
        _row(c, Icons.history_rounded, 'Recently played', store.recents.length, ListPage('Recently played', () => store.recents)),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 8, 0),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const Text('Playlists', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            TextButton.icon(
              icon: const Icon(Icons.add_rounded),
              label: const Text('New'),
              onPressed: () async {
                final n = await askName(c);
                if (n != null) store.createPlaylist(n);
              },
            ),
          ]),
        ),
        for (final n in store.playlists.keys)
          _row(c, Icons.queue_music_rounded, n, store.playlists[n]!.length,
              ListPage(n, () => store.playlists[n] ?? [], playlist: n)),
        const SizedBox(height: 24),
      ]),
    );
  }
}

class ListPage extends StatelessWidget {
  final String title;
  final List<Track> Function() tracks;
  final String? playlist;
  const ListPage(this.title, this.tracks, {super.key, this.playlist});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
        backgroundColor: Colors.transparent,
        actions: [
          if (playlist != null)
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: () {
                store.deletePlaylist(playlist!);
                Navigator.pop(context);
              },
            ),
        ],
      ),
      body: ListenableBuilder(
        listenable: store,
        builder: (c, _) {
          final l = tracks();
          if (l.isEmpty) {
            return Center(child: Text('Nothing here yet.', style: TextStyle(color: mist.withOpacity(0.5))));
          }
          return ListView.builder(
            itemCount: l.length + 1,
            itemBuilder: (_, i) {
              if (i == 0) {
                return Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: Row(children: [
                    Expanded(
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(backgroundColor: ember, foregroundColor: ink),
                        icon: const Icon(Icons.play_arrow_rounded),
                        label: const Text('Play'),
                        onPressed: () => playList(l, 0),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.shuffle_rounded),
                        label: const Text('Shuffle'),
                        onPressed: () async {
                          await handler.playItems(l.map((e) => e.toItem()).toList(), 0);
                          await handler.setShuffleMode(AudioServiceShuffleMode.all);
                        },
                      ),
                    ),
                  ]),
                );
              }
              return TrackTile(l[i - 1], l, i - 1, playlist: playlist);
            },
          );
        },
      ),
    );
  }
}

// ───────────── PLAYER WIDGETS ─────────────
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
        final busy = st?.processingState == AudioProcessingState.loading;
        if (busy) {
          return Padding(
            padding: const EdgeInsets.all(12),
            child: SizedBox(width: size - 10, height: size - 10, child: CircularProgressIndicator(strokeWidth: 2.5, color: color ?? ember)),
          );
        }
        return IconButton(
          iconSize: size,
          color: color,
          icon: Icon((st?.playing ?? false) ? Icons.pause_rounded : Icons.play_arrow_rounded),
          onPressed: () => (st?.playing ?? false) ? handler.pause() : handler.play(),
        );
      },
    );
  }
}

class MiniPlayer extends StatelessWidget {
  final MediaItem item;
  const MiniPlayer({super.key, required this.item});
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => const NowPlaying(),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: moss.withOpacity(0.75),
              border: Border.all(color: mist.withOpacity(0.10)),
              borderRadius: BorderRadius.circular(22),
            ),
            child: Row(children: [
              Art(item.artUri?.toString() ?? '', size: 48, radius: 14),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                  Text(item.artist ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: mist.withOpacity(0.6))),
                ]),
              ),
              const PlayButton(size: 30),
              IconButton(icon: const Icon(Icons.skip_next_rounded, size: 30), onPressed: handler.skipToNext),
            ]),
          ),
        ),
      ),
    );
  }
}

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
    final max = widget.duration.inMilliseconds.toDouble().clamp(1.0, double.infinity);
    return StreamBuilder<Duration>(
      stream: AudioService.position,
      builder: (_, s) {
        final pos = s.data ?? Duration.zero;
        final v = (drag ?? pos.inMilliseconds.toDouble()).clamp(0.0, max);
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
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text(fmt(Duration(milliseconds: v.round())), style: TextStyle(color: mist.withOpacity(0.6), fontSize: 12)),
              Text(fmt(widget.duration), style: TextStyle(color: mist.withOpacity(0.6), fontSize: 12)),
            ]),
          ),
        ]);
      },
    );
  }
}

// ───────────── NOW PLAYING ─────────────
class NowPlaying extends StatelessWidget {
  const NowPlaying({super.key});

  Widget _chip(IconData ic, String label, VoidCallback f) => InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: f,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Column(children: [
            Icon(ic, color: leaf),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(fontSize: 11, color: mist.withOpacity(0.7))),
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.of(context).size.height;
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
      child: SizedBox(
        height: h * 0.94,
        child: StreamBuilder<MediaItem?>(
          stream: handler.mediaItem,
          builder: (context, snap) {
            final m = snap.data;
            if (m == null) return const SizedBox();
            final art = m.artUri?.toString() ?? '';
            final t = Track.fromItem(m);
            return Stack(children: [
              Positioned.fill(child: Backdrop(art: art)),
              SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(28, 14, 28, 28),
                child: Column(children: [
                  Container(width: 40, height: 5, decoration: BoxDecoration(color: mist.withOpacity(0.3), borderRadius: BorderRadius.circular(3))),
                  const SizedBox(height: 26),
                  StreamBuilder<PlaybackState>(
                    stream: handler.playbackState,
                    builder: (_, s) {
                      final playing = s.data?.playing ?? false;
                      return AnimatedScale(
                        scale: playing ? 1.0 : 0.86,
                        duration: const Duration(milliseconds: 450),
                        curve: Curves.easeOutBack,
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(30),
                            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 40, offset: const Offset(0, 20))],
                          ),
                          child: AspectRatio(aspectRatio: 1, child: LayoutBuilder(builder: (_, c) => Art(art, size: c.maxWidth, radius: 30))),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 28),
                  Row(children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(m.title, maxLines: 2, overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
                        const SizedBox(height: 4),
                        Text(m.artist ?? '', style: const TextStyle(fontSize: 15, color: leaf)),
                      ]),
                    ),
                    ListenableBuilder(
                      listenable: store,
                      builder: (_, __) => IconButton(
                        iconSize: 28,
                        color: store.isLiked(t) ? ember : mist,
                        icon: Icon(store.isLiked(t) ? Icons.favorite_rounded : Icons.favorite_border_rounded),
                        onPressed: () => store.toggleLike(t),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 10),
                  SeekBar(m.duration ?? Duration.zero),
                  StreamBuilder<PlaybackState>(
                    stream: handler.playbackState,
                    builder: (_, s) {
                      final st = s.data;
                      final shuf = st?.shuffleMode == AudioServiceShuffleMode.all;
                      final rep = st?.repeatMode ?? AudioServiceRepeatMode.none;
                      return Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                        IconButton(
                          icon: Icon(Icons.shuffle_rounded, color: shuf ? leaf : mist.withOpacity(0.5)),
                          onPressed: () => handler.setShuffleMode(shuf ? AudioServiceShuffleMode.none : AudioServiceShuffleMode.all),
                        ),
                        IconButton(iconSize: 42, icon: const Icon(Icons.skip_previous_rounded), onPressed: handler.skipToPrevious),
                        Container(
                          decoration: const BoxDecoration(color: ember, shape: BoxShape.circle),
                          child: const PlayButton(size: 50, color: ink),
                        ),
                        IconButton(iconSize: 42, icon: const Icon(Icons.skip_next_rounded), onPressed: handler.skipToNext),
                        IconButton(
                          icon: Icon(
                            rep == AudioServiceRepeatMode.one ? Icons.repeat_one_rounded : Icons.repeat_rounded,
                            color: rep == AudioServiceRepeatMode.none ? mist.withOpacity(0.5) : leaf,
                          ),
                          onPressed: () => handler.setRepeatMode(switch (rep) {
                            AudioServiceRepeatMode.none => AudioServiceRepeatMode.all,
                            AudioServiceRepeatMode.all => AudioServiceRepeatMode.one,
                            _ => AudioServiceRepeatMode.none,
                          }),
                        ),
                      ]);
                    },
                  ),
                  const SizedBox(height: 22),
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    decoration: BoxDecoration(color: mist.withOpacity(0.07), borderRadius: BorderRadius.circular(20)),
                    child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                      _chip(Icons.lyrics_rounded, 'Lyrics', () => sheet(context, LyricsView(m), height: h * 0.8)),
                      _chip(Icons.queue_music_rounded, 'Queue', () => sheet(context, const QueueView(), height: h * 0.8)),
                      _chip(Icons.blur_on_rounded, 'Crossfade', () => sheet(context, const CrossfadeView())),
                      _chip(Icons.nightlight_round, 'Sleep', () => sheet(context, const SleepView())),
                      _chip(Icons.equalizer_rounded, 'EQ', () => sheet(context, const EqView(), height: h * 0.6)),
                    ]),
                  ),
                ]),
              ),
            ]);
          },
        ),
      ),
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
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text('Crossfade', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              Text(store.crossfade == 0 ? 'Off' : '${store.crossfade.round()} s',
                  style: const TextStyle(color: ember, fontWeight: FontWeight.w700)),
            ]),
            const SizedBox(height: 4),
            Text('Songs blend into each other instead of stopping.', style: TextStyle(color: mist.withOpacity(0.6))),
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
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 28),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(end == null ? 'Sleep timer' : 'Stops at ${TimeOfDay.fromDateTime(end).format(c)}',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final m in [15, 30, 45, 60, 90])
                ActionChip(label: Text('$m min'), backgroundColor: ink, onPressed: () {
                  handler.setSleep(m);
                  Navigator.pop(c);
                }),
              if (end != null)
                ActionChip(label: const Text('Turn off'), backgroundColor: ember, labelStyle: const TextStyle(color: ink), onPressed: () {
                  handler.setSleep(null);
                  Navigator.pop(c);
                }),
            ]),
          ]),
        ),
      );
}

class QueueView extends StatelessWidget {
  const QueueView({super.key});
  @override
  Widget build(BuildContext context) => StreamBuilder<List<MediaItem>>(
        stream: handler.queue,
        builder: (_, s) {
          final q = s.data ?? [];
          return Column(children: [
            const Padding(padding: EdgeInsets.all(18), child: Text('Up next', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800))),
            Expanded(
              child: ReorderableListView.builder(
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
                    leading: Art(m.artUri?.toString() ?? '', size: 46),
                    title: Text(m.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: cur ? leaf : mist, fontWeight: FontWeight.w600)),
                    subtitle: Text(m.artist ?? '', maxLines: 1, overflow: TextOverflow.ellipsis),
                    onTap: () => handler.skipToQueueItem(i),
                    trailing: cur
                        ? const Icon(Icons.graphic_eq_rounded, color: leaf)
                        : IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => handler.removeQueueItemAt(i)),
                  );
                },
              ),
            ),
          ]);
        },
      );
}

class LyricsView extends StatelessWidget {
  final MediaItem m;
  const LyricsView(this.m, {super.key});

  Future<String> _fetch() async {
    final clean = m.title
        .replaceAll(RegExp(r'\(.*?\)|\[.*?\]|official|video|lyrical|lyrics|audio|hd|4k|\|.*', caseSensitive: false), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    try {
      final r = await http.get(Uri.parse('https://lrclib.net/api/search?q=${Uri.encodeQueryComponent(clean)}'));
      final list = jsonDecode(r.body) as List;
      for (final e in list) {
        final p = e['plainLyrics'];
        if (p is String && p.trim().isNotEmpty) return p;
      }
    } catch (_) {}
    return 'Lyrics not found for this song.';
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<String>(
        future: _fetch(),
        builder: (_, s) => ListView(padding: const EdgeInsets.all(24), children: [
          const Text('Lyrics', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 14),
          if (!s.hasData) const Center(child: CircularProgressIndicator(color: leaf)) else Text(s.data!, style: const TextStyle(fontSize: 18, height: 1.6)),
        ]),
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
          return const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('Equalizer is not available on this phone.')));
        }
        if (!s.hasData) return const Center(child: CircularProgressIndicator(color: leaf));
        final p = s.data!;
        return ListView(padding: const EdgeInsets.all(24), children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const Text('Equalizer', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            TextButton(onPressed: () async { await handler.resetEq(); setState(() {}); }, child: const Text('Reset')),
          ]),
          for (var i = 0; i < p.bands.length; i++)
            Row(children: [
              SizedBox(width: 62, child: Text('${(p.bands[i].centerFrequency / 1000).toStringAsFixed(p.bands[i].centerFrequency < 1000 ? 2 : 1)} kHz', style: TextStyle(fontSize: 12, color: mist.withOpacity(0.7)))),
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
