import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

final yt = YoutubeExplode();

AudioOnlyStreamInfo bestAudio(StreamManifest m) =>
    m.audioOnly.reduce((a, b) => a.bitrate.bitsPerSecond >= b.bitrate.bitsPerSecond ? a : b);

/// How YouTube's own apps introduce themselves. Same method BeatWave / Metrolist use:
/// ask the InnerTube "player" endpoint as the YouTube VR / Music app and get a direct audio URL.
class ClientProfile {
  final String name, version, id, ua, apiKey;
  final Map<String, dynamic> extra;
  const ClientProfile(this.name, this.version, this.id, this.ua, this.apiKey, this.extra);

  Map<String, dynamic> context() => {
        'client': {
          'clientName': name,
          'clientVersion': version,
          'hl': 'en',
          'gl': 'IN',
          ...extra,
          'userAgent': ua,
        }
      };
}

const _vrKey = 'AIzaSyA8eiZmM1FaDVjRy-df2KTyQ_vz_yYM39w';
const _vrExtra = {
  'deviceMake': 'Oculus',
  'deviceModel': 'Quest 3',
  'androidSdkVersion': 32,
  'osName': 'Android',
  'osVersion': '12L',
};

const kProfiles = <ClientProfile>[
  ClientProfile('ANDROID_VR', '1.65.10', '28',
      'com.google.android.apps.youtube.vr.oculus/1.65.10 (Linux; U; Android 12L; eureka-user Build/SQ3A.220605.009.A1) gzip',
      _vrKey, _vrExtra),
  ClientProfile('ANDROID_VR', '1.62.27', '28',
      'com.google.android.apps.youtube.vr.oculus/1.62.27 (Linux; U; Android 12L; eureka-user Build/SQ3A.220605.009.A1) gzip',
      _vrKey, _vrExtra),
  ClientProfile('ANDROID_VR', '1.61.48', '28',
      'com.google.android.apps.youtube.vr.oculus/1.61.48 (Linux; U; Android 12L; eureka-user Build/SQ3A.220605.009.A1) gzip',
      _vrKey, _vrExtra),
  ClientProfile('ANDROID_MUSIC', '7.27.52', '21',
      'com.google.android.apps.youtube.music/7.27.52 (Linux; U; Android 11) gzip',
      'AIzaSyAOghZGza2MQSZkY_zfZ370N-PUdXEo8AI',
      {'androidSdkVersion': 30, 'osName': 'Android', 'osVersion': '11'}),
];

class ResolvedStream {
  final String url, mime, via;
  final int? length;
  final Map<String, String> headers;
  ResolvedStream(this.url, this.mime, this.length, this.headers, this.via);
}

String shortErr(Object e) {
  final s = e.toString().replaceAll('Exception: ', '').replaceAll('\n', ' ');
  return s.length > 120 ? '${s.substring(0, 120)}…' : s;
}

Future<ResolvedStream> resolveWith(ClientProfile c, String videoId) async {
  final res = await http
      .post(
        Uri.parse('https://www.youtube.com/youtubei/v1/player?prettyPrint=false'),
        headers: {
          'Content-Type': 'application/json',
          'User-Agent': c.ua,
          'X-YouTube-Client-Name': c.id,
          'X-YouTube-Client-Version': c.version,
          'Origin': 'https://www.youtube.com',
          'X-Goog-Api-Key': c.apiKey,
        },
        body: jsonEncode({
          'context': c.context(),
          'videoId': videoId,
          'contentCheckOk': true,
          'racyCheckOk': true,
        }),
      )
      .timeout(const Duration(seconds: 15));
  if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
  final j = jsonDecode(res.body) as Map<String, dynamic>;
  final ps = j['playabilityStatus'] as Map?;
  if (ps?['status'] != 'OK') throw Exception(ps?['reason'] ?? ps?['status'] ?? 'not playable');
  final sd = j['streamingData'] as Map?;
  final all = [...(sd?['adaptiveFormats'] as List? ?? []), ...(sd?['formats'] as List? ?? [])];
  Map? best;
  for (final f in all) {
    final mime = f['mimeType'];
    if (mime is String && mime.startsWith('audio/') && f['url'] is String) {
      if (best == null || (f['bitrate'] ?? 0) > (best['bitrate'] ?? 0)) best = f as Map;
    }
  }
  if (best == null) throw Exception('no direct audio URL');
  return ResolvedStream(
    best['url'] as String,
    (best['mimeType'] as String).split(';').first,
    int.tryParse('${best['contentLength']}'),
    {'User-Agent': c.ua},
    '${c.name} ${c.version}',
  );
}

Future<ResolvedStream> resolveExplode(String id) async {
  final m = await yt.videos.streamsClient.getManifest(id);
  final a = bestAudio(m);
  return ResolvedStream(a.url.toString(), 'audio/${a.container.name}', a.size.totalBytes, {}, 'fallback');
}

/// Plays a stream in small byte-range chunks (needed when the CDN only serves bounded ranges).
class ChunkedSource extends StreamAudioSource {
  final ResolvedStream s;
  ChunkedSource(this.s);
  static const chunk = 1024 * 1024;

  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    final total = s.length!;
    start ??= 0;
    var stop = math.min(end ?? total, total);
    stop = math.min(stop, start + chunk);
    final req = http.Request('GET', Uri.parse(s.url))
      ..headers.addAll(s.headers)
      ..headers['Range'] = 'bytes=$start-${stop - 1}';
    final resp = await http.Client().send(req);
    if (resp.statusCode != 200 && resp.statusCode != 206) {
      throw Exception('CDN HTTP ${resp.statusCode}');
    }
    return StreamAudioResponse(
      sourceLength: total,
      contentLength: stop - start,
      offset: start,
      stream: resp.stream,
      contentType: s.mime,
    );
  }
}

/// Tries every client, then a chunked fetch, then the old package. Throws a readable error list.
Future<void> loadInto(AudioPlayer p, String id) async {
  final errs = <String>[];
  ResolvedStream? firstOk;
  for (final c in kProfiles) {
    try {
      final s = await resolveWith(c, id);
      firstOk ??= s;
      await p.setAudioSource(AudioSource.uri(Uri.parse(s.url), headers: s.headers));
      return;
    } catch (e) {
      errs.add('${c.name} ${c.version}: ${shortErr(e)}');
    }
  }
  if (firstOk?.length != null) {
    try {
      await p.setAudioSource(ChunkedSource(firstOk!));
      return;
    } catch (e) {
      errs.add('chunked: ${shortErr(e)}');
    }
  }
  try {
    final s = await resolveExplode(id);
    await p.setUrl(s.url);
    return;
  } catch (e) {
    errs.add('fallback: ${shortErr(e)}');
  }
  throw Exception(errs.join('\n'));
}
