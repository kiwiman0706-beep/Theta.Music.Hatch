import 'package:flutter/material.dart';

import '../app.dart';
import '../core/models.dart';
import '../core/search.dart';
import '../core/settings.dart';
import '../core/voice.dart';
import 'dialogs.dart';
import 'ipod_theme.dart';
import 'screens.dart';

void _play(List<Track> tracks, int i, {bool shuffle = false}) {
  services.player.playList(tracks, i, shuffle: shuffle);
  nav.showNowPlaying();
}

MenuScreen mainMenu() => MenuScreen(
      'iPod',
      () => [
        MenuItem('Music', chevron: true, onSelect: () => nav.push(musicMenu())),
        MenuItem('Favorites', chevron: true, onSelect: () => nav.push(favoritesMenu())),
        MenuItem('Search', chevron: true, onSelect: () => nav.push(searchStartMenu())),
        MenuItem('Library', chevron: true, onSelect: () => nav.push(libraryMenu())),
        MenuItem('Settings', chevron: true, onSelect: () => nav.push(settingsMenu())),
        MenuItem('Shuffle Songs', onSelect: () {
          final s = services.library.songs;
          if (s.isNotEmpty) _play(s, 0, shuffle: true);
        }),
        if (services.player.hasQueue) MenuItem('Now Playing', chevron: true, onSelect: nav.showNowPlaying),
      ],
      deps: [services.player, services.library],
      splitArt: true,
    );

List<MenuItem> _emptyHint() => [
      if (!services.settings.configured)
        MenuItem('サーバー未設定', chevron: true, onSelect: () => showServerDialog(nav.context))
      else
        MenuItem('Update Library…', chevron: true, onSelect: () => startScan(false)),
    ];

// ------------------------------------------------------------- お気に入り（中央ボタン長押しで登録）

void _favToast(bool on) => nav.toast(on ? '★ お気に入りに追加' : 'お気に入りから外しました');

MenuItem _trackItem(List<Track> list, int i) => MenuItem(
      list[i].title,
      starred: services.favorites.isTrack(list[i]),
      onSelect: () => _play(list, i),
      onLong: () => _favToast(services.favorites.toggleTrack(list[i])),
    );

MenuItem _albumItem(Album al, {String? label}) => MenuItem(
      label ?? al.title,
      chevron: true,
      starred: services.favorites.isAlbum(al),
      onSelect: () => nav.push(albumMenu(al)),
      onLong: () => _favToast(services.favorites.toggleAlbum(al)),
    );

MenuItem _artistItem(Artist a) => MenuItem(
      a.name,
      chevron: true,
      starred: services.favorites.isArtist(a),
      onSelect: () => nav.push(artistMenu(a)),
      onLong: () => _favToast(services.favorites.toggleArtist(a)),
    );

MenuScreen favoritesMenu() {
  final f = services.favorites;
  return MenuScreen(
    'Favorites',
    () => f.count == 0
        ? [const MenuItem('中央ボタン長押しで登録'), const MenuItem('（曲・アルバム・アーティスト）')]
        : [
            MenuItem('Shuffle Favorites', onSelect: () {
              final all = f.allTracks;
              if (all.isNotEmpty) _play(all, 0, shuffle: true);
            }),
            MenuItem('Songs', detail: '${f.tracks.length}', chevron: true,
                onSelect: () => nav.push(songsMenu(f.tracks, 'Fav Songs'))),
            MenuItem('Albums', detail: '${f.albums.length}', chevron: true,
                onSelect: () => nav.push(albumsMenu(f.albums, 'Fav Albums'))),
            MenuItem('Artists', detail: '${f.artists.length}', chevron: true,
                onSelect: () => nav.push(MenuScreen('Fav Artists', () => [for (final a in f.artists) _artistItem(a)],
                    deps: [f]))),
          ],
    deps: [f],
  );
}

// ------------------------------------------------------------- 検索（MENU 長押しで音声検索）

MenuScreen searchStartMenu() => MenuScreen('Search', () => [
      MenuItem('Voice Search', detail: 'MENU 長押し', onSelect: voiceSearch),
      MenuItem('Type…', onSelect: () async {
        final q = await showTextSearchDialog(nav.context);
        if (q != null && q.trim().isNotEmpty) _runSearch([q]);
      }),
    ]);

Future<void> voiceSearch() async {
  if (services.library.tracks.isEmpty) {
    nav.toast('ライブラリが空です');
    return;
  }
  final ctx = nav.context;
  List<String>? alts;
  try {
    alts = await Voice.listen();
  } on VoiceUnavailable {
    // 音声入力が無い端末では文字で
    if (!ctx.mounted) return;
    final q = await showTextSearchDialog(ctx);
    alts = q == null || q.trim().isEmpty ? null : [q];
  } catch (e) {
    nav.toast('音声入力エラー: $e');
    return;
  }
  if (alts != null) _runSearch(alts);
}

void _runSearch(List<String> alts) {
  final r = searchVoice(services.library, alts);
  if (r == null) return;
  final (res, cmd) = r;
  final best = res.best;
  // 「〜をかけて」なら、いちばん当たったものをすぐ再生
  if (cmd.play && best != null) {
    final (list, i) = best.playable;
    services.player.playList(list, i, shuffle: cmd.shuffle);
    nav.showNowPlaying();
    nav.toast('再生: ${best.label}');
    return;
  }
  nav.push(searchMenu(res));
}

MenuScreen searchMenu(SearchResult r) => MenuScreen(
      r.query.isEmpty ? 'Search' : r.query,
      () => [
        if (r.best != null)
          MenuItem('Play: ${r.best!.label}', onSelect: () {
            final (list, i) = r.best!.playable;
            _play(list, i);
          }),
        if (r.isEmpty) MenuItem('見つかりません', detail: r.query),
        for (final a in r.artists) MenuItem(a.name, detail: 'Artist', chevron: true,
            starred: services.favorites.isArtist(a), onSelect: () => nav.push(artistMenu(a)),
            onLong: () => _favToast(services.favorites.toggleArtist(a))),
        for (final al in r.albums) MenuItem(al.title, detail: 'Album', chevron: true,
            starred: services.favorites.isAlbum(al), onSelect: () => nav.push(albumMenu(al)),
            onLong: () => _favToast(services.favorites.toggleAlbum(al))),
        for (var i = 0; i < r.tracks.length; i++) MenuItem(r.tracks[i].title, detail: 'Song',
            starred: services.favorites.isTrack(r.tracks[i]), onSelect: () => _play(r.tracks, i),
            onLong: () => _favToast(services.favorites.toggleTrack(r.tracks[i]))),
        MenuItem('Search Again', chevron: true, onSelect: voiceSearch),
      ],
      deps: [services.favorites],
    );

// ------------------------------------------------------------- 一覧

MenuScreen musicMenu() => MenuScreen(
      'Music',
      () => services.library.tracks.isEmpty
          ? _emptyHint()
          : [
              MenuItem('Artists', chevron: true, onSelect: () => nav.push(artistsMenu())),
              MenuItem('Albums', chevron: true, onSelect: () => nav.push(albumsMenu(services.library.albums, 'Albums'))),
              MenuItem('Songs', chevron: true, onSelect: () => nav.push(songsMenu(services.library.songs, 'Songs'))),
              MenuItem('Genres', chevron: true, onSelect: () => nav.push(genresMenu())),
              MenuItem('Folders', chevron: true,
                  onSelect: () => nav.push(folderMenu(services.library.root))),
            ],
      deps: [services.library],
    );

MenuScreen artistsMenu() => MenuScreen(
      'Artists',
      () => [for (final a in services.library.artists) _artistItem(a)],
      letterIndex: true,
      deps: [services.favorites],
    );

MenuScreen artistMenu(Artist a) => MenuScreen(
      a.name,
      () => [
        MenuItem('All Songs', chevron: true, onSelect: () => nav.push(songsMenu(a.tracks, a.name, keepOrder: true))),
        for (final al in a.albums) _albumItem(al),
      ],
      deps: [services.favorites],
    );

MenuScreen albumsMenu(List<Album> albums, String title) => MenuScreen(
      title,
      () => [for (final al in albums) _albumItem(al)],
      letterIndex: true,
      deps: [services.favorites],
    );

MenuScreen albumMenu(Album al) => MenuScreen(
      al.title,
      () => [for (var i = 0; i < al.tracks.length; i++) _trackItem(al.tracks, i)],
      deps: [services.favorites],
    );

MenuScreen songsMenu(List<Track> tracks, String title, {bool keepOrder = false}) => MenuScreen(
      title,
      () => [for (var i = 0; i < tracks.length; i++) _trackItem(tracks, i)],
      letterIndex: !keepOrder,
      deps: [services.favorites],
    );

MenuScreen genresMenu() => MenuScreen(
      'Genres',
      () => [
        for (final e in services.library.genres.entries)
          MenuItem(e.key, chevron: true, onSelect: () {
            final albums = <String, Album>{};
            for (final a in services.library.albums) {
              if (a.tracks.any((t) => (t.genre.isEmpty ? 'Unknown Genre' : t.genre) == e.key)) {
                albums[a.title + a.artist] = a;
              }
            }
            nav.push(albumsMenu(albums.values.toList(), e.key));
          }),
      ],
      letterIndex: true,
    );

MenuScreen folderMenu(String dir) {
  final (subs, files) = services.library.folderChildren(dir);
  final name = dir == services.library.root ? 'Folders' : dir.substring(dir.lastIndexOf('/') + 1);
  return MenuScreen(
    name,
    () => [
      for (final s in subs) MenuItem(s, chevron: true, onSelect: () => nav.push(folderMenu('$dir/$s'))),
      for (var i = 0; i < files.length; i++) _trackItem(files, i),
    ],
    letterIndex: true,
  );
}

// ------------------------------------------------------------- Library

void startScan(bool full) {
  if (!services.settings.configured) {
    showServerDialog(nav.context);
    return;
  }
  services.scanner.scan(full: full);
  nav.push(scanScreen());
}

InfoScreen scanScreen() => InfoScreen(
      'Library',
      (context) {
        final s = services.scanner;
        final frac = s.tagsTotal == 0 ? 0.0 : s.tagsDone / s.tagsTotal;
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(s.running ? 'スキャン中…' : 'スキャン', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
          const SizedBox(height: 8),
          Text('フォルダ: ${s.dirs}'),
          Text('曲: ${s.files}'),
          if (s.tagsTotal > 0) Text('タグ: ${s.tagsDone} / ${s.tagsTotal}'),
          const SizedBox(height: 8),
          IPodBar(s.running && s.tagsTotal == 0 ? 0 : (s.running ? frac : 1)),
          const SizedBox(height: 8),
          Text(s.status, maxLines: 3, overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13, color: s.error != null ? Colors.red : LcdColors.sub)),
          const Spacer(),
          Text(s.running ? '中央ボタンでキャンセル' : 'MENU で戻る',
              style: const TextStyle(fontSize: 12, color: LcdColors.sub)),
        ]);
      },
      source: services.scanner,
      select: () {
        if (services.scanner.running) services.scanner.cancel();
      },
    );

InfoScreen exportScreen() => InfoScreen(
      'Obsidian',
      (context) {
        final o = services.obsidian;
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Obsidian へ書き出し', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
          const SizedBox(height: 8),
          Text(services.settings.obsidianPath, style: const TextStyle(fontSize: 12, color: LcdColors.sub)),
          const SizedBox(height: 8),
          if (o.total > 0) Text('${o.done} / ${o.total} ノート'),
          const SizedBox(height: 8),
          IPodBar(o.total == 0 ? 0 : o.done / o.total),
          const SizedBox(height: 8),
          Text(o.status, maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
        ]);
      },
      source: services.obsidian,
    );

String _ago(DateTime? t) {
  if (t == null) return '未スキャン';
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 60) return '${d.inMinutes}分前';
  if (d.inHours < 24) return '${d.inHours}時間前';
  return '${d.inDays}日前';
}

MenuScreen libraryMenu() => MenuScreen(
      'Library',
      () => [
        MenuItem('Update Library', detail: _ago(services.library.scannedAt), onSelect: () => startScan(false)),
        MenuItem('Rebuild Library', onSelect: () => startScan(true)),
        MenuItem('Export to Obsidian', onSelect: () async {
          if (services.settings.obsidianPath.trim().isEmpty) {
            await showObsidianDialog(nav.context);
            if (services.settings.obsidianPath.trim().isEmpty) return;
          }
          services.obsidian.export();
          nav.push(exportScreen());
        }),
        MenuItem('Songs', detail: '${services.library.tracks.length}'),
        MenuItem('Albums', detail: '${services.library.albums.length}'),
        MenuItem('Artists', detail: '${services.library.artists.length}'),
      ],
      deps: [services.library],
    );

// ------------------------------------------------------------- Settings

MenuScreen settingsMenu() {
  final s = services.settings;
  void save() => s.save();
  return MenuScreen(
    'Settings',
    () => [
      MenuItem('Source', detail: s.source == MusicSource.dsaudio ? 'DS audio' : 'WebDAV', chevron: true,
          onSelect: () => showServerDialog(nav.context)),
      MenuItem('Skin', detail: 'iPod', onSelect: () {
        // ThetaHomeHatch 風の画面へ
        s.skin = 'theta';
        save();
      }),
      MenuItem('Shuffle', detail: s.shuffle ? 'Songs' : 'Off', onSelect: () {
        s.shuffle = !s.shuffle;
        save();
      }),
      MenuItem('Repeat', detail: switch (s.repeat) { RepeatSetting.off => 'Off', RepeatSetting.one => 'One', RepeatSetting.all => 'All' },
          onSelect: () {
        s.repeat = RepeatSetting.values[(s.repeat.index + 1) % 3];
        save();
      }),
      MenuItem('Clicker', detail: s.clicker ? 'On' : 'Off', onSelect: () {
        s.clicker = !s.clicker;
        save();
      }),
      MenuItem('Haptics', detail: s.haptics ? 'On' : 'Off', onSelect: () {
        s.haptics = !s.haptics;
        save();
      }),
      if (s.source == MusicSource.dsaudio)
        MenuItem('Fav = Rating', detail: s.dsFavRating == 0 ? 'Off' : '★${s.dsFavRating}+', onSelect: () {
          // DS audio の★評価との同期: ★4以上 → ★5 だけ → 同期しない → ★3以上
          s.dsFavRating = switch (s.dsFavRating) { 4 => 5, 5 => 0, 0 => 3, _ => 4 };
          save();
        }),
      MenuItem('Body Color', detail: s.blackBody ? 'Black' : 'Silver', onSelect: () {
        s.blackBody = !s.blackBody;
        save();
      }),
      MenuItem('Read Tags', detail: s.readTags ? 'On' : 'Off', onSelect: () {
        s.readTags = !s.readTags;
        save();
      }),
      MenuItem('Obsidian Folder', detail: s.obsidianPath.isEmpty ? '未設定' : null, chevron: true,
          onSelect: () => showObsidianDialog(nav.context)),
      MenuItem('About', chevron: true, onSelect: () => nav.push(aboutScreen())),
    ],
    deps: [s],
  );
}

InfoScreen aboutScreen() => InfoScreen('About', (context) {
      final l = services.library;
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Theta Music', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        const Text('NAS (WebDAV) + Tailscale player', style: TextStyle(fontSize: 12, color: LcdColors.sub)),
        const SizedBox(height: 10),
        Text('Songs: ${l.tracks.length}'),
        Text('Albums: ${l.albums.length}'),
        Text('Artists: ${l.artists.length}'),
        Text('Root: ${l.root}', maxLines: 1, overflow: TextOverflow.ellipsis),
      ]);
    });
