// File Station（接続方式 File Station）の結合テスト。
// 環境変数 DS_URL / DS_USER / DS_PASS を設定したときだけ実行（実際の NAS、または test/fake_dsm.py）。
// DS_MUSIC：曲のある共有フォルダ（既定 /music）
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:theta_music/core/dsaudio.dart';
import 'package:theta_music/core/library.dart';
import 'package:theta_music/core/scanner.dart';
import 'package:theta_music/core/settings.dart';

void main() {
  AppSettings.secure = null; // テストでは暗号化した保存先を使わない
  final url = Platform.environment['DS_URL'];
  test('File Station: scan with tags, art, range and stream', () async {
    SharedPreferences.setMockInitialValues({
      'source': MusicSource.filestation.index,
      'dsUrl': url!,
      'user': Platform.environment['DS_USER'] ?? '',
      'password': Platform.environment['DS_PASS'] ?? '',
      'musicPath': Platform.environment['DS_MUSIC'] ?? '/music',
    });
    final settings = AppSettings();
    await settings.load();
    final ds = DsAudioClient(settings);
    final otp = Platform.environment['DS_OTP'];
    if (otp != null) ds.setOtp(otp);
    final lib = Library()..dirOverride = await Directory.systemTemp.createTemp('lib');
    final scanner = Scanner(settings, lib, ds);
    await scanner.scan();
    expect(scanner.error, isNull, reason: scanner.status);
    expect(lib.tracks, isNotEmpty);
    for (final t in lib.tracks) {
      expect(t.id, isEmpty); // Audio Station の曲ではない
      // ignore: avoid_print
      print('${t.path} | ${t.title} | ${t.artist} | ${t.album} | art=${t.art?.key}');
    }
    expect(lib.tracks.any((t) => t.title.isNotEmpty && t.artist.isNotEmpty), isTrue);

    // 2 回目は差分スキャン（サイズ・更新日時が同じならタグを読み直さない）
    await scanner.scan();
    expect(scanner.tagsTotal, 0);

    // 再生用の URL：Range で途中から取れる（シークに要る）
    final t = lib.tracks.first;
    final (uri, headers) = await FileStationStore(ds).stream(t.path);
    final res = await http.get(uri, headers: {...headers, 'Range': 'bytes=10-19'});
    expect(res.statusCode, 206, reason: 'Range に応えないとシークできない');
    expect(res.bodyBytes.length, 10);
    final full = await ds.fsBytes(t.path);
    expect(res.bodyBytes, full.sublist(10, 20));
    expect(await ds.fsRange(t.path, 10, 10), full.sublist(10, 20));
  });
}
