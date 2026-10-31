import 'package:audio_service/audio_service.dart';

class Track {
  final String id, title, artist, art;
  final int? seconds;
  const Track(this.id, this.title, this.artist, this.art, this.seconds);

  factory Track.fromJson(Map<String, dynamic> j) =>
      Track(j['id'], j['t'], j['a'], j['i'], j['s']);

  Map<String, dynamic> toJson() => {'id': id, 't': title, 'a': artist, 'i': art, 's': seconds};

  MediaItem toItem({String? idOverride}) => MediaItem(
        id: idOverride ?? id,
        title: title,
        artist: artist,
        artUri: art.isEmpty ? null : Uri.parse(art),
        duration: seconds == null ? null : Duration(seconds: seconds!),
        extras: {'vid': id},
      );

  factory Track.fromItem(MediaItem m) => Track(
        (m.extras?['vid'] ?? m.id) as String,
        m.title,
        m.artist ?? '',
        m.artUri?.toString() ?? '',
        m.duration?.inSeconds,
      );
}
