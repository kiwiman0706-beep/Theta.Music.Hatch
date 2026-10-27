import 'package:flutter/material.dart';

import '../app.dart';
import '../core/models.dart';
import '../core/settings.dart';
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
      () => [
        for (final a in services.library.artists)
          MenuItem(a.name, chevron: true, onSelect: () => nav.push(artistMenu(a))),
      ],
      letterIndex: true,
    );

MenuScreen artistMenu(Artist a) => MenuScreen(
      a.name,
      () => [
        MenuItem('All Songs', chevron: true, onSelect: () => nav.push(songsMenu(a.tracks, a.name, keepOrder: true))),
        for (final al in a.albums)
          MenuItem(al.title, chevron: true, onSelect: () => nav.push(albumMenu(al))),
      ],
    );

MenuScreen albumsMenu(List<Album> albums, String title) => MenuScreen(
      title,
      () => [
        for (final al in albums)
          MenuItem(al.title, chevron: true, onSelect: () => nav.push(albumMenu(al))),
      ],
      letterIndex: true,
    );

MenuScreen albumMenu(Album al) => MenuScreen(
      al.title,
      () => [
        for (var i = 0; i < al.tracks.length; i++)
          MenuItem(al.tracks[i].title, onSelect: () => _play(al.tracks, i)),
      ],
    );

MenuScreen songsMenu(List<Track> tracks, String title, {bool keepOrder = false}) => MenuScreen(
      title,
      () => [
        for (var i = 0; i < tracks.length; i++)
          MenuItem(tracks[i].title, onSelect: () => _play(tracks, i)),
      ],
      letterIndex: !keepOrder,
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
      for (var i = 0; i < files.length; i++) MenuItem(files[i].title, onSelect: () => _play(files, i)),
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
      MenuItem('Server', detail: s.configured ? Uri.tryParse(s.serverUrl)?.host ?? '' : '未設定', chevron: true,
          onSelect: () => showServerDialog(nav.context)),
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
