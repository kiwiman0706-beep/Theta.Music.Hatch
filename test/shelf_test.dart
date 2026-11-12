import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:theta_music/core/favorites.dart';
import 'package:theta_music/core/library.dart';
import 'package:theta_music/core/models.dart';
import 'package:theta_music/core/settings.dart';
import 'package:theta_music/core/shelf.dart';

Track t(String artist, String album, String title, int no) => Track(
    path: '/music/$artist/$album/$no.flac', size: 1, mtime: 0, title: title, artist: artist, album: album,
    trackNo: no, artPath: '/music/$artist/$album/cover.jpg');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('shelf: favorites and recent albums, with art files and resolvable keys', () async {
    SharedPreferences.setMockInitialValues({});
    final s = AppSettings();
    await s.load();
    final tmp = await Directory.systemTemp.createTemp('shelf');
    final lib = Library()..dirOverride = tmp;
    await lib.replace([
      t('宇多田ヒカル', 'First Love', 'Automatic', 1),
      t('宇多田ヒカル', 'First Love', 'First Love', 2),
      t('Radiohead', 'OK Computer', 'Karma Police', 6),
      t('Perfume', 'GAME', 'ポリリズム', 1),
    ], '/music');
    final fav = Favorites(lib)..dirOverride = tmp;
    fav.toggleAlbum(lib.albums.firstWhere((a) => a.title == 'OK Computer'));
    fav.toggleArtist(lib.artists.firstWhere((a) => a.name == 'Perfume'));
    fav.toggleTrack(lib.songs.firstWhere((x) => x.title == 'Automatic'));
    final rec = Recents()..dirOverride = tmp;
    rec.played(lib.songs.firstWhere((x) => x.title == 'First Love'));
    rec.played(lib.songs.firstWhere((x) => x.title == 'Karma Police'));

    final loaded = <String>[];
    final shelf = ShelfWriter(s, lib, fav, rec, (ref) async {
      loaded.add(ref.path);
      return Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xD9]);
    })..dirOverride = tmp;
    await shelf.write();

    final j = jsonDecode(await File('${tmp.path}/shelf/shelf.json').readAsString()) as Map;
    final items = (j['items'] as List).cast<Map>();
    expect([for (final i in items) '${i['section']}:${i['title']}'], [
      'favorites:お気に入りの曲',
      'favorites:OK Computer',
      'favorites:Perfume',
      'recent:OK Computer',
      'recent:First Love',
    ]);
    // ジャケットは md5.img で files/shelf/art に。同じジャケットは 1 つ
    for (final i in items) {
      expect(i['image'], matches(RegExp(r'^[0-9a-f]{32}\.img$')));
      expect(File('${tmp.path}/shelf/art/${i['image']}').existsSync(), isTrue);
    }
    // 押されたときに再生する曲が決まる
    for (final i in items) {
      expect(ShelfWriter.resolve(lib, fav, '${i['kind']}', '${i['key']}'), isNotNull, reason: '${i['title']}');
    }
    // 設定で出さないようにできる
    s.shelfRecent = false;
    expect(shelf.entries().every((e) => e['section'] == 'favorites'), isTrue);
  });
}
