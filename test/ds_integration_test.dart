// DS audio（Audio Station API）の結合テスト。
// 環境変数 DS_URL / DS_USER / DS_PASS を設定したときだけ実行（実際の NAS、または test/fake_dsm.py）。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:theta_music/core/dsaudio.dart';
import 'package:theta_music/core/favorites.dart';
import 'package:theta_music/core/library.dart';
import 'package:theta_music/core/obsidian.dart';
import 'package:theta_music/core/scanner.dart';
import 'package:theta_music/core/settings.dart';

void main() {
  final url = Platform.environment['DS_URL'];
  test('Audio Station: login, song list, stream, cover, obsidian via File Station', () async {
    SharedPreferences.setMockInitialValues({
      'source': MusicSource.dsaudio.index,
      'dsUrl': url!,
      'user': Platform.environment['DS_USER'] ?? '',
      'password': Platform.environment['DS_PASS'] ?? '',
      'obsidianPath': Platform.environment['DS_VAULT'] ?? '/home/ThetaMusicTest',
    });
    final settings = AppSettings();
    await settings.load();
    final ds = DsAudioClient(settings);
    final lib = Library()..dirOverride = await Directory.systemTemp.createTemp('lib');
    final scanner = Scanner(settings, lib, ds);
    await scanner.scan();
    final otp = Platform.environment['DS_OTP'];
    if (otp != null) {
      // 2 段階認証: 最初はコードを求められ、入れるとデバイストークンが保存される
      expect(scanner.error, contains('2 段階認証'));
      ds.setOtp(otp);
      await scanner.scan();
      expect(settings.dsDid, isNotEmpty);
      ds.reset();
      await scanner.scan(); // 次からはトークンだけで通る
    }
    expect(scanner.error, isNull, reason: scanner.status);
    expect(lib.tracks, isNotEmpty);
    // ignore: avoid_print
    print('${lib.tracks.length} songs, root=${lib.root}, first=${lib.tracks.first.toJson()}');

    final t = lib.tracks.first;
    final uri = await ds.streamUri(t.id, 'mp3');
    final res = await HttpClient().getUrl(uri).then((r) => r.close());
    expect(res.statusCode, anyOf(200, 206));
    await res.drain<void>();
    final cover = await ds.cover(t.id);
    // ignore: avoid_print
    print('cover: ${cover?.length ?? 'none'} bytes');

    // お気に入り = DS audio の★評価（★4以上）。登録で★5 を NAS に書き、更新後も残る
    final fav = Favorites(lib, favRating: () => settings.dsFavRating, setRating: ds.setRating)
      ..dirOverride = await Directory.systemTemp.createTemp('fav');
    expect(fav.isTrack(t), isFalse);
    expect(fav.toggleTrack(t), isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(fav.syncError, isNull);
    await scanner.scan();
    final again = lib.tracks.firstWhere((x) => x.id == t.id);
    expect(again.rating, 5);
    expect(fav.isTrack(again), isTrue);
    expect(fav.toggleTrack(again), isFalse);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    await scanner.scan();
    expect(lib.tracks.firstWhere((x) => x.id == t.id).rating, 0);

    final ex = ObsidianExporter(settings, lib, () => ds);
    await ex.export();
    // ignore: avoid_print
    print(ex.status);
    expect(ex.status, startsWith('完了: '));
    // 2 回目（既存ノートの取得とマージ）
    await ex.export();
    expect(ex.status, startsWith('完了: '));
  }, skip: url == null ? 'DS_URL not set' : false);
}
