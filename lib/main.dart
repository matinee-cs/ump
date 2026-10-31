import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'common.dart';
import 'handler.dart';
import 'models.dart';
import 'player.dart';
import 'store.dart';

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

  // Theme colour follows the album art
  String? lastArt;
  handler.mediaItem.listen((m) async {
    final art = m?.artUri?.toString();
    if (art == null || art == lastArt) return;
    lastArt = art;
    final c = await dominantColor(art);
    if (c != null) seed.value = c;
  });

  // Show the real reason when a song does not play
  handler.lastError.addListener(() {
    final e = handler.lastError.value;
    if (e == null) return;
    messengerKey.currentState
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text('Could not play:\n$e', maxLines: 6, overflow: TextOverflow.ellipsis),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 8),
      ));
  });

  runApp(const UmpApp());
}

class UmpApp extends StatelessWidget {
  const UmpApp({super.key});
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Color>(
      valueListenable: seed,
      builder: (_, c, __) {
        final cs = ColorScheme.fromSeed(seedColor: c, brightness: Brightness.dark);
        final base = ThemeData(useMaterial3: true, colorScheme: cs, brightness: Brightness.dark);
        return MaterialApp(
          title: 'UMP',
          debugShowCheckedModeBanner: false,
          scaffoldMessengerKey: messengerKey,
          themeAnimationDuration: const Duration(milliseconds: 800),
          themeAnimationCurve: Curves.easeOut,
          theme: base.copyWith(
            scaffoldBackgroundColor: cs.surface,
            textTheme: GoogleFonts.plusJakartaSansTextTheme(base.textTheme).apply(bodyColor: cs.onSurface, displayColor: cs.onSurface),
          ),
          home: const Shell(),
        );
      },
    );
  }
}

// ───────────── SHELL ─────────────
class Shell extends StatefulWidget {
  const Shell({super.key});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int tab = 0;
  static const tabs = [HomeTab(), SearchTab(), LibraryTab()];
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: AnimatedContainer(
        duration: const Duration(milliseconds: 700),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [cs.primaryContainer.withOpacity(0.55), cs.surface],
            stops: const [0.0, 0.5],
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 320),
            transitionBuilder: (c, a) => FadeTransition(
              opacity: a,
              child: SlideTransition(position: Tween(begin: const Offset(0, 0.02), end: Offset.zero).animate(a), child: c),
            ),
            child: KeyedSubtree(key: ValueKey(tab), child: tabs[tab]),
          ),
        ),
      ),
      bottomNavigationBar: Column(mainAxisSize: MainAxisSize.min, children: [
        const MiniBar(),
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
  }
}

// ───────────── TRACK TILE ─────────────
class TrackTile extends StatelessWidget {
  final Track t;
  final List<Track> list;
  final int i;
  final String? playlist;
  const TrackTile(this.t, this.list, this.i, {super.key, this.playlist});

  PopupMenuItem<String> _it(String v, String label, IconData ic) =>
      PopupMenuItem(value: v, child: Row(children: [Icon(ic, size: 20), const SizedBox(width: 12), Text(label)]));

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: store,
      builder: (ctx, _) {
        final dl = store.downloads.containsKey(t.id);
        final prog = store.progress[t.id];
        return StreamBuilder<MediaItem?>(
          stream: handler.mediaItem,
          builder: (_, s) {
            final on = s.data?.id == t.id;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
              decoration: BoxDecoration(
                color: on ? cs.secondaryContainer.withOpacity(0.7) : Colors.transparent,
                borderRadius: BorderRadius.circular(22),
              ),
              child: ListTile(
                contentPadding: const EdgeInsets.fromLTRB(10, 2, 4, 2),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
                leading: Stack(alignment: Alignment.center, children: [
                  Art(t.art, radius: 16),
                  if (on)
                    Container(
                      width: 54, height: 54,
                      decoration: BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(16)),
                      child: Center(
                        child: StreamBuilder<PlaybackState>(
                          stream: handler.playbackState,
                          builder: (_, p) => EqBars(color: Colors.white, animate: p.data?.playing ?? false),
                        ),
                      ),
                    ),
                ]),
                title: Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontWeight: FontWeight.w700, color: on ? cs.primary : cs.onSurface)),
                subtitle: Text(t.artist, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: cs.onSurface.withOpacity(0.6))),
                onTap: () => playList(list, i),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  if (prog != null)
                    SizedBox(width: 18, height: 18, child: CircularProgressIndicator(value: prog, strokeWidth: 2.5))
                  else if (dl)
                    Icon(Icons.download_done_rounded, size: 18, color: cs.primary),
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert_rounded),
                    onSelected: (v) {
                      switch (v) {
                        case 'next':
                          handler.playNext(t.toItem());
                          toast('Will play next');
                        case 'queue':
                          handler.addQueueItem(t.toItem());
                          toast('Added to queue');
                        case 'like':
                          store.toggleLike(t);
                        case 'pl':
                          pickPlaylist(ctx, t);
                        case 'dl':
                          store.download(t);
                          toast('Downloading…');
                        case 'rmdl':
                          store.deleteDownload(t);
                        case 'rm':
                          store.removeFromPlaylist(playlist!, t);
                      }
                    },
                    itemBuilder: (_) => [
                      _it('next', 'Play next', Icons.queue_play_next_rounded),
                      _it('queue', 'Add to queue', Icons.playlist_add_rounded),
                      _it('like', store.isLiked(t) ? 'Remove from liked' : 'Like',
                          store.isLiked(t) ? Icons.favorite_rounded : Icons.favorite_border_rounded),
                      _it('pl', 'Add to playlist', Icons.queue_music_rounded),
                      dl ? _it('rmdl', 'Remove download', Icons.delete_outline_rounded) : _it('dl', 'Download', Icons.download_rounded),
                      if (playlist != null) _it('rm', 'Remove from this playlist', Icons.remove_circle_outline_rounded),
                    ],
                  ),
                ]),
              ),
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
  String get greeting {
    final h = DateTime.now().hour;
    return h < 12 ? 'Good morning' : (h < 17 ? 'Good afternoon' : 'Good evening');
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final quick = store.recents.take(6).toList();
        final w = (MediaQuery.of(context).size.width - 20 * 2 - 10) / 2;
        var n = 0;
        return ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
              child: Row(children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Container(color: const Color(0xFF0C1410), width: 48, height: 48, child: Image.asset('assets/icon_fg.png', fit: BoxFit.cover)),
                ),
                const SizedBox(width: 14),
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(greeting, style: TextStyle(fontSize: 13, color: cs.onSurface.withOpacity(0.65), fontWeight: FontWeight.w600)),
                  const Text('UMP', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: -1, height: 1.05)),
                ]),
              ]),
            ),
            if (quick.isNotEmpty)
              FadeIn(
                index: n++,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Wrap(spacing: 10, runSpacing: 10, children: [
                    for (var i = 0; i < quick.length; i++)
                      Pressable(
                        onTap: () => playList(store.recents, i),
                        child: Container(
                          width: w,
                          decoration: BoxDecoration(color: cs.surfaceContainerHigh, borderRadius: BorderRadius.circular(18)),
                          child: Row(children: [
                            Art(quick[i].art, size: 52, radius: 18),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(quick[i].title, maxLines: 2, overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
                            ),
                            const SizedBox(width: 8),
                          ]),
                        ),
                      ),
                  ]),
                ),
              ),
            FutureBuilder<List<Track>>(
              future: store.recommended(),
              builder: (_, s) => (s.hasData && s.data!.isNotEmpty)
                  ? FadeIn(index: n++, child: Shelf('Recommended for you', s.data!))
                  : const SizedBox(),
            ),
            for (final e in shelfDefs.entries)
              FutureBuilder<List<Track>>(
                future: store.shelf(e.value),
                builder: (_, s) => s.hasData && s.data!.isNotEmpty
                    ? FadeIn(index: n++, child: Shelf(e.key, s.data!))
                    : Padding(
                        padding: const EdgeInsets.fromLTRB(20, 18, 20, 4),
                        child: Text(s.connectionState == ConnectionState.done ? '' : 'Loading ${e.key}…',
                            style: TextStyle(color: cs.onSurface.withOpacity(0.4))),
                      ),
              ),
          ],
        );
      },
    );
  }
}

class Shelf extends StatelessWidget {
  final String title;
  final List<Track> tracks;
  const Shelf(this.title, this.tracks, {super.key});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 12),
        child: Text(title, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
      ),
      SizedBox(
        height: 206,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          itemCount: tracks.length,
          itemBuilder: (_, i) {
            final t = tracks[i];
            return Pressable(
              onTap: () => playList(tracks, i),
              child: Container(
                width: 148,
                margin: const EdgeInsets.symmetric(horizontal: 6),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Art(t.art, size: 148, radius: 26),
                  const SizedBox(height: 10),
                  Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                  Text(t.artist, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: cs.onSurface.withOpacity(0.6), fontSize: 12)),
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
    FocusScope.of(context).unfocus();
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
    final cs = Theme.of(context).colorScheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Padding(
        padding: EdgeInsets.fromLTRB(22, 20, 20, 6),
        child: Text('Search', style: TextStyle(fontSize: 32, fontWeight: FontWeight.w800, letterSpacing: -1)),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: SearchBar(
          controller: ctrl,
          hintText: 'Songs, artists, albums',
          elevation: const WidgetStatePropertyAll(0),
          leading: const Icon(Icons.search_rounded),
          trailing: [
            if (ctrl.text.isNotEmpty)
              IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: () => setState(() {
                  ctrl.clear();
                  results = [];
                  msg = null;
                }),
              ),
          ],
          onChanged: (_) => setState(() {}),
          onSubmitted: run,
        ),
      ),
      AnimatedSize(
        duration: const Duration(milliseconds: 250),
        child: busy ? const LinearProgressIndicator(minHeight: 3) : const SizedBox(width: double.infinity),
      ),
      if (msg != null) Padding(padding: const EdgeInsets.all(20), child: Text(msg!, style: TextStyle(color: cs.onSurface.withOpacity(0.6)))),
      Expanded(
        child: results.isEmpty && !busy
            ? ListenableBuilder(
                listenable: store,
                builder: (_, __) => ListView(padding: const EdgeInsets.symmetric(horizontal: 20), children: [
                  if (store.history.isNotEmpty) ...[
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      const Text('Recent searches', style: TextStyle(fontWeight: FontWeight.w800)),
                      TextButton(onPressed: store.clearHistory, child: const Text('Clear')),
                    ]),
                    Wrap(spacing: 8, runSpacing: 4, children: [
                      for (final h in store.history) ActionChip(label: Text(h), onPressed: () => run(h)),
                    ]),
                  ] else
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text('Type a song or artist and press search.', style: TextStyle(color: cs.onSurface.withOpacity(0.5))),
                    ),
                ]),
              )
            : ListView.builder(
                padding: const EdgeInsets.only(bottom: 16),
                itemCount: results.length,
                itemBuilder: (_, i) => FadeIn(index: i, child: TrackTile(results[i], results, i)),
              ),
      ),
    ]);
  }
}

// ───────────── LIBRARY ─────────────
Route<T> fadeRoute<T>(Widget page) => PageRouteBuilder<T>(
      transitionDuration: const Duration(milliseconds: 380),
      reverseTransitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (_, __, ___) => page,
      transitionsBuilder: (_, a, __, child) {
        final c = CurvedAnimation(parent: a, curve: Curves.easeOutCubic);
        return FadeTransition(
          opacity: c,
          child: SlideTransition(position: Tween(begin: const Offset(0.06, 0), end: Offset.zero).animate(c), child: child),
        );
      },
    );

class LibraryTab extends StatelessWidget {
  const LibraryTab({super.key});

  Widget _card(BuildContext c, IconData ic, String title, int n, Color bg, Color fg, Widget page) => Expanded(
        child: Pressable(
          onTap: () => Navigator.push(c, fadeRoute(page)),
          child: Container(
            height: 116,
            margin: const EdgeInsets.symmetric(horizontal: 5),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(26)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Icon(ic, color: fg, size: 28),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: TextStyle(color: fg, fontWeight: FontWeight.w800, fontSize: 14)),
                Text('$n songs', style: TextStyle(color: fg.withOpacity(0.7), fontSize: 12)),
              ]),
            ]),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: store,
      builder: (c, _) => ListView(children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(22, 20, 20, 14),
          child: Text('Library', style: TextStyle(fontSize: 32, fontWeight: FontWeight.w800, letterSpacing: -1)),
        ),
        FadeIn(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 11),
            child: Row(children: [
              _card(c, Icons.favorite_rounded, 'Liked', store.liked.length, cs.primaryContainer, cs.onPrimaryContainer,
                  ListPage('Liked songs', () => store.liked)),
              _card(c, Icons.download_done_rounded, 'Downloads', store.dlTracks.length, cs.secondaryContainer, cs.onSecondaryContainer,
                  ListPage('Downloads', () => store.dlTracks)),
              _card(c, Icons.history_rounded, 'Recent', store.recents.length, cs.tertiaryContainer, cs.onTertiaryContainer,
                  ListPage('Recently played', () => store.recents)),
            ]),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 24, 12, 6),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const Text('Playlists', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
            FilledButton.tonalIcon(
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
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 2),
            leading: Container(
              width: 54, height: 54,
              decoration: BoxDecoration(color: cs.surfaceContainerHigh, borderRadius: BorderRadius.circular(16)),
              child: Icon(Icons.queue_music_rounded, color: cs.primary),
            ),
            title: Text(n, style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text('${store.playlists[n]!.length} songs'),
            onTap: () => Navigator.push(c, fadeRoute(ListPage(n, () => store.playlists[n] ?? [], playlist: n))),
          ),
        if (store.playlists.isEmpty)
          Padding(padding: const EdgeInsets.all(22), child: Text('No playlists yet.', style: TextStyle(color: cs.onSurface.withOpacity(0.5)))),
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
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      bottomNavigationBar: const SafeArea(top: false, child: MiniBar()),
      body: ListenableBuilder(
        listenable: store,
        builder: (c, _) {
          final l = tracks();
          return CustomScrollView(slivers: [
            SliverAppBar.large(
              title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
              backgroundColor: cs.surface,
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
            if (l.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: Text('Nothing here yet.', style: TextStyle(color: cs.onSurface.withOpacity(0.5)))),
              )
            else ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                  child: Row(children: [
                    Expanded(
                      child: FilledButton.icon(
                        icon: const Icon(Icons.play_arrow_rounded),
                        label: const Text('Play'),
                        onPressed: () => playList(l, 0),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton.tonalIcon(
                        icon: const Icon(Icons.shuffle_rounded),
                        label: const Text('Shuffle'),
                        onPressed: () async {
                          await handler.playItems(l.map((e) => e.toItem()).toList(), 0);
                          await handler.setShuffleMode(AudioServiceShuffleMode.all);
                        },
                      ),
                    ),
                  ]),
                ),
              ),
              SliverList.builder(
                itemCount: l.length,
                itemBuilder: (_, i) => FadeIn(index: i, child: TrackTile(l[i], l, i, playlist: playlist)),
              ),
            ],
          ]);
        },
      ),
    );
  }
}
