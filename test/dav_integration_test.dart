// ローカル WebDAV サーバーに対するスキャン/書き出しの結合テスト。
// 環境変数 DAV_URL (例: http://127.0.0.1:8765), DAV_USER, DAV_PASS を設定したときだけ実行。
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
  AppSettings.secure = null; // テストでは暗号化した保存先を使わない
  final url = Platform.environment['DAV_URL'];
  test('scan + obsidian export against WebDAV', () async {
    SharedPreferences.setMockInitialValues({
      'serverUrl': url!,
      'user': Platform.environment['DAV_USER'] ?? '',
      'password': Platform.environment['DAV_PASS'] ?? '',
      'musicPath': '/music',
      'obsidianPath': '/vault/Theta Vault/Music',
    });
    final settings = AppSettings();
    await settings.load();
    final lib = Library()..dirOverride = await Directory.systemTemp.createTemp('lib');
    final scanner = Scanner(settings, lib, DsAudioClient(settings));
    await scanner.scan();
    expect(scanner.error, isNull, reason: scanner.status);
    for (final t in lib.tracks) {
      // ignore: avoid_print
      print('${t.path}\n   ${t.toJson()}');
    }
    expect(lib.tracks, isNotEmpty);

    // 2 回目は差分スキャン（タグ読み直しなし）
    await scanner.scan();
    expect(scanner.tagsTotal, 0);

    final ex = ObsidianExporter(settings, lib, settings.client);
    await ex.export();
    // ignore: avoid_print
    print(ex.status);
    expect(ex.status, startsWith('完了: '));

    // 一覧（.base）と Vault の登録（.theta/vault.json）
    final dav = settings.client();
    expect(await dav.getText('/vault/Theta Vault/Music/アルバム.base'), contains('file.inFolder("Music/Albums")'));
    expect(await dav.getText('/vault/Theta Vault/.theta/vault.json'), contains('"music"'));
    final note = (await dav.getText('/vault/Theta Vault/Music/Albums/宇多田ヒカル - First Love.md'))!;
    expect(note, contains('theta: music/album@1'));
    expect(note, contains('nas_path: "nas://music/'));
    expect(note, contains('[[Music/Artists/宇多田ヒカル|宇多田ヒカル]]'));
    dav.close();

    // お気に入りを付けて書き出し → 新しい端末（空のお気に入り）で Vault から戻す
    final favDir = await Directory.systemTemp.createTemp('fav');
    final fav = Favorites(lib)..dirOverride = favDir;
    fav.toggleAlbum(lib.albums.first);
    fav.toggleArtist(lib.artists.last);
    fav.toggleTrack(lib.songs.first);
    await ObsidianExporter(settings, lib, settings.client, favorites: fav).export();
    final fresh = Favorites(lib)..dirOverride = await Directory.systemTemp.createTemp('fav2');
    final ex2 = ObsidianExporter(settings, lib, settings.client, favorites: fresh);
    final n = await ex2.restoreFavorites();
    // ignore: avoid_print
    print(ex2.status);
    expect(n, 3);
    expect((fresh.albums.length, fresh.artists.length, fresh.tracks.length), (1, 1, 1));
  }, skip: url == null ? 'DAV_URL not set' : false);
}
