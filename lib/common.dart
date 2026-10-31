import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'handler.dart';
import 'models.dart';

late WeedHandler handler;
final messengerKey = GlobalKey<ScaffoldMessengerState>();

/// Theme colour follows the album art (Material You style).
final seed = ValueNotifier<Color>(const Color(0xFF4E9F6B));

Future<Color?> dominantColor(String url) async {
  try {
    final provider = ResizeImage(NetworkImage(url), width: 32, height: 32);
    final comp = Completer<ui.Image>();
    final stream = provider.resolve(ImageConfiguration.empty);
    late ImageStreamListener l;
    l = ImageStreamListener((info, _) {
      if (!comp.isCompleted) comp.complete(info.image);
      stream.removeListener(l);
    }, onError: (e, s) {
      if (!comp.isCompleted) comp.completeError(e);
    });
    stream.addListener(l);
    final img = await comp.future.timeout(const Duration(seconds: 6));
    final bd = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (bd == null) return null;
    double r = 0, g = 0, b = 0, ws = 0;
    for (var i = 0; i + 3 < bd.lengthInBytes; i += 4) {
      final R = bd.getUint8(i), G = bd.getUint8(i + 1), B = bd.getUint8(i + 2);
      final mx = math.max(R, math.max(G, B)), mn = math.min(R, math.min(G, B));
      final sat = (mx - mn) / 255.0;
      final w = 0.05 + sat * sat * (mx / 255.0);
      r += R * w;
      g += G * w;
      b += B * w;
      ws += w;
    }
    return Color.fromARGB(255, (r / ws).round(), (g / ws).round(), (b / ws).round());
  } catch (_) {
    return null;
  }
}

void toast(String s) => messengerKey.currentState
  ?..hideCurrentSnackBar()
  ..showSnackBar(SnackBar(content: Text(s), behavior: SnackBarBehavior.floating, duration: const Duration(seconds: 2)));

void sheet(BuildContext c, Widget child, {double? height}) => showModalBottomSheet(
      context: c,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => SizedBox(height: height, child: child),
    );

void playList(List<Track> l, int i) => handler.playItems(l.map((e) => e.toItem()).toList(), i);

Future<String?> askName(BuildContext c) {
  final ctrl = TextEditingController();
  return showDialog<String>(
    context: c,
    builder: (_) => AlertDialog(
      title: const Text('New playlist'),
      content: TextField(controller: ctrl, autofocus: true, decoration: const InputDecoration(hintText: 'Playlist name')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
        FilledButton(
          onPressed: () => Navigator.pop(c, ctrl.text.trim().isEmpty ? null : ctrl.text.trim()),
          child: const Text('Create'),
        ),
      ],
    ),
  );
}

// ───────── small animated widgets ─────────
class Art extends StatelessWidget {
  final String url;
  final double size, radius;
  const Art(this.url, {super.key, this.size = 54, this.radius = 14});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ph = Container(color: cs.surfaceContainerHighest, child: Icon(Icons.music_note_rounded, color: cs.primary));
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        width: size,
        height: size,
        child: url.isEmpty
            ? ph
            : Stack(fit: StackFit.expand, children: [
                ph,
                Image.network(
                  url,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox(),
                  frameBuilder: (c, child, frame, sync) =>
                      AnimatedOpacity(opacity: frame == null ? 0 : 1, duration: const Duration(milliseconds: 350), child: child),
                ),
              ]),
      ),
    );
  }
}

class FadeIn extends StatelessWidget {
  final Widget child;
  final int index;
  const FadeIn({super.key, required this.child, this.index = 0});
  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: Duration(milliseconds: 380 + index.clamp(0, 8) * 60),
        curve: Curves.easeOutCubic,
        builder: (_, v, c) => Opacity(opacity: v, child: Transform.translate(offset: Offset(0, (1 - v) * 20), child: c)),
        child: child,
      );
}

class Pressable extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  const Pressable({super.key, required this.child, required this.onTap});
  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool down = false;
  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => down = true),
        onTapCancel: () => setState(() => down = false),
        onTapUp: (_) => setState(() => down = false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: down ? 0.95 : 1,
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOut,
          child: widget.child,
        ),
      );
}

/// Little dancing bars shown on the song that is playing.
class EqBars extends StatefulWidget {
  final Color color;
  final double size;
  final bool animate;
  const EqBars({super.key, required this.color, this.size = 18, this.animate = true});
  @override
  State<EqBars> createState() => _EqBarsState();
}

class _EqBarsState extends State<EqBars> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..repeat();
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        builder: (_, __) {
          final t = _c.value * 2 * math.pi;
          return SizedBox(
            width: widget.size,
            height: widget.size,
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, crossAxisAlignment: CrossAxisAlignment.end, children: [
              for (var i = 0; i < 3; i++)
                Container(
                  width: widget.size / 5,
                  height: widget.size * (widget.animate ? 0.3 + 0.7 * (0.5 + 0.5 * math.sin(t + i * 2.1)) : 0.4),
                  decoration: BoxDecoration(color: widget.color, borderRadius: BorderRadius.circular(2)),
                ),
            ]),
          );
        },
      );
}
