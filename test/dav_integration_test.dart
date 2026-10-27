// ローカル WebDAV サーバーに対するスキャン/書き出しの結合テスト。
// 環境変数 DAV_URL (例: http://127.0.0.1:8765), DAV_USER, DAV_PASS を設定したときだけ実行。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:theta_music/core/dsaudio.dart';
import 'package:theta_music/core/library.dart';
import 'package:theta_music/core/obsidian.dart';
import 'package:theta_music/core/scanner.dart';
import 'package:theta_music/core/settings.dart';

void main() {
  final url = Platform.environment['DAV_URL'];
  test('scan + obsidian export against WebDAV', () async {
    SharedPreferences.setMockInitialValues({
      'serverUrl': url!,
      'user': Platform.environment['DAV_USER'] ?? '',
      'password': Platform.environment['DAV_PASS'] ?? '',
      'musicPath': '/music',
      'obsidianPath': '/vault/Music',
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
  }, skip: url == null ? 'DAV_URL not set' : false);
}
