import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:theta_music/core/favorites.dart';
import 'package:theta_music/core/library.dart';
import 'package:theta_music/core/models.dart';
import 'package:theta_music/core/search.dart';

Track t(String artist, String album, String title, int no) =>
    Track(path: '/music/$artist/$album/$no $title.flac', size: 1, mtime: 0, title: title, artist: artist, album: album, trackNo: no);

Future<Library> lib() async {
  final l = Library()..dirOverride = await Directory.systemTemp.createTemp('lib');
  await l.replace([
    t('宇多田ヒカル', 'First Love', 'Automatic', 1),
    t('宇多田ヒカル', 'First Love', 'First Love', 2),
    t('宇多田ヒカル', 'Fantôme', '道', 1),
    t('サカナクション', 'DocumentaLy', 'アイデンティティ', 1),
    t('Radiohead', 'OK Computer', 'Paranoid Android', 2),
    t('Radiohead', 'OK Computer', 'Karma Police', 6),
  ], '/music');
  return l;
}

void main() {
  test('normalize: kana, width, case, spaces', () {
    expect(normalizeForSearch('サカナ クション'), normalizeForSearch('さかなくしょん'));
    expect(normalizeForSearch('ＯＫ　Ｃｏｍｐｕｔｅｒ'), 'okcomputer');
    expect(normalizeForSearch('First Love'), 'firstlove');
  });

  test('voice command parsing', () {
    var c = parseVoiceCommand('宇多田ヒカルをかけて');
    expect((c.query, c.play, c.shuffle), ('宇多田ヒカル', true, false));
    c = parseVoiceCommand('レディオヘッドをシャッフルで再生して');
    expect((c.query, c.play, c.shuffle), ('レディオヘッド', true, true));
    c = parseVoiceCommand('play karma police');
    expect((c.query, c.play), ('karma police', true));
    c = parseVoiceCommand('サカナクションの曲');
    expect((c.query, c.play), ('サカナクション', false));
  });

  test('search ranks artist > album > track and handles "Xの Y"', () async {
    final l = await lib();
    expect(search(l, '宇多田').best!.kind, HitKind.artist);
    expect(search(l, 'ok computer').best!.album!.title, 'OK Computer');
    expect(search(l, 'karma police').best!.track!.title, 'Karma Police');
    // 曲のときはアルバムの途中から続けて流す
    final (list, i) = search(l, 'karma police').best!.playable;
    expect((list.length, list[i].title), (2, 'Karma Police'));
    // 「アーティストの曲名」: First Love はアルバムと曲の両方にあるが、「の」の後ろで決まる
    final b = search(l, '宇多田ヒカルのAutomatic').best!;
    expect((b.kind, b.track!.title), (HitKind.track, 'Automatic'));
    expect(search(l, '存在しない').isEmpty, isTrue);
  });

  test('voice alternatives: picks the best candidate', () async {
    final l = await lib();
    final r = searchVoice(l, ['からまポリス', 'karma police をかけて'])!;
    expect(r.$1.best!.track!.title, 'Karma Police');
    expect(r.$2.play, isTrue);
  });

  test('favorites persist and resolve against the library', () async {
    final l = await lib();
    final dir = await Directory.systemTemp.createTemp('fav');
    final f = Favorites(l)..dirOverride = dir;
    expect(f.toggleTrack(l.songs.first), isTrue);
    f.toggleAlbum(l.albums.firstWhere((a) => a.title == 'OK Computer'));
    f.toggleArtist(l.artists.firstWhere((a) => a.name == 'サカナクション'));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final g = Favorites(l)..dirOverride = dir;
    await g.load();
    expect((g.tracks.length, g.albums.length, g.artists.length), (1, 1, 1));
    expect(g.allTracks.length, 4);
    expect(g.toggleTrack(l.songs.first), isFalse);
    expect(g.tracks, isEmpty);
  });
}
