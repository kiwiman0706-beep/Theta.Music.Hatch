import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:theta_music/core/favorites.dart';
import 'package:theta_music/core/library.dart';
import 'package:theta_music/core/move_log.dart';

void main() {
  const csv = '﻿元の場所,新しい場所,理由\r\n'
      '/music/邦楽/山下達郎,/music/▶邦楽/山下達郎,フォルダごと\r\n'
      '"/music/▶邦楽/山下達郎/RIDE ON TIME/01 ride on time.mp3","/music/▶邦楽/山下達郎/RIDE ON TIME (1980)/01 RIDE ON TIME.mp3","名前, 年"\r\n';

  test('parse the move log (BOM, header, quoted cells)', () {
    final m = MoveLog.parse(csv);
    expect(m.length, 2);
    expect(m[1].$2, '/music/▶邦楽/山下達郎/RIDE ON TIME (1980)/01 RIDE ON TIME.mp3');
  });

  test('remap follows folder and file moves in order, whatever is above the share', () {
    final m = MoveLog.parse(csv);
    expect(MoveLog.remap('/music/邦楽/山下達郎/RIDE ON TIME/01 ride on time.mp3', m),
        '/music/▶邦楽/山下達郎/RIDE ON TIME (1980)/01 RIDE ON TIME.mp3');
    expect(MoveLog.remap('/volume1/music/邦楽/山下達郎/FOR YOU/01 SPARKLE.mp3', m),
        '/volume1/music/▶邦楽/山下達郎/FOR YOU/01 SPARKLE.mp3');
    expect(MoveLog.remap('/music/邦楽/山下達郎2/a.mp3', m), '/music/邦楽/山下達郎2/a.mp3'); // 名前の途中
    expect(MoveLog.shareOf('/volume1/music/a/b.mp3'), '/music');
    expect(MoveLog.shareOf('/music'), '/music');
  });

  test('favorites follow the move log once', () async {
    final dir = await Directory.systemTemp.createTemp('fav');
    final f = Favorites(Library())..dirOverride = dir;
    await f.load();
    // 場所で覚えている曲（ライブラリに無くても、記録の付け替えは効く）
    final old = '/music/邦楽/山下達郎/RIDE ON TIME/01 ride on time.mp3';
    await f.applyMoveLog('dummy.csv', const []);
    expect(f.appliedMoveLog('dummy.csv'), isTrue);
    final g = Favorites(Library())..dirOverride = dir;
    await File('${dir.path}/favorites.json').writeAsString('{"tracks":["$old"]}');
    await g.load();
    expect(await g.applyMoveLog('20261119-100000.csv', MoveLog.parse(csv)), 1);
    expect(g.appliedMoveLog('20261119-100000.csv'), isTrue);
    final h = Favorites(Library())..dirOverride = dir;
    await h.load();
    expect(h.appliedMoveLog('20261119-100000.csv'), isTrue);
    expect(await File('${dir.path}/favorites.json').readAsString(), contains('RIDE ON TIME (1980)'));
  });
}
