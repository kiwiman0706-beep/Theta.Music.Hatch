import 'package:flutter/material.dart';

import '../../app.dart';
import '../../core/models.dart';
import '../../core/settings.dart';
import '../dialogs.dart';
import 'hud_shell.dart';
import 'hud_theme.dart';
import 'hud_widgets.dart';

void _play(List<Track> tracks, int i, {bool shuffle = false}) {
  services.player.playList(tracks, i, shuffle: shuffle);
  hudNav.selectTab(0);
}

String _fmt(Duration d) {
  final s = d.inSeconds;
  final h = s ~/ 3600;
  final m = (s % 3600) ~/ 60;
  final ss = (s % 60).toString().padLeft(2, '0');
  return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$ss' : '$m:$ss';
}

String _extOf(String path) {
  final f = path.substring(path.lastIndexOf('/') + 1);
  return f.contains('.') ? f.substring(f.lastIndexOf('.') + 1).toUpperCase() : '—';
}

// ------------------------------------------------------------------ 共通の枠

/// タブの最上段：「■ LIB.ARTISTS」・大きな数字・英字と日本語（ThetaHomeHatch の SYS.TIME と同じ並び）
class _RootHeader extends StatelessWidget {
  final String code;
  final String big;
  final String en;
  final String ja;
  const _RootHeader({required this.code, required this.big, required this.en, required this.ja});

  @override
  Widget build(BuildContext context) {
    final p = HudScope.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SectionLabel(code),
        const SizedBox(height: 2),
        Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(big,
                  style: TextStyle(
                      color: p.fg,
                      fontSize: 58,
                      height: 1.15,
                      fontWeight: p.pop ? FontWeight.bold : FontWeight.w300,
                      fontFamily: p.display)),
            ),
          ),
          const SizedBox(width: 16),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(en, style: TextStyle(color: p.fg, fontSize: 15, letterSpacing: 2, fontFamily: p.mono)),
            const SizedBox(height: 6),
            Text(ja, style: TextStyle(color: p.accent, fontSize: 15, letterSpacing: 1, fontFamily: p.mono)),
          ]),
        ]),
        const SizedBox(height: 6),
        const Ticks(),
        const SizedBox(height: 10),
      ]),
    );
  }
}

/// 詳細ページの最上段：戻る・題名
class _DetailHeader extends StatelessWidget {
  final String code;
  final String title;
  final String? sub;
  const _DetailHeader({required this.code, required this.title, this.sub});

  @override
  Widget build(BuildContext context) {
    final p = HudScope.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SectionLabel(code),
        const SizedBox(height: 8),
        Row(children: [
          PillButton(icon: Icons.chevron_left, onTap: hudNav.back, minHeight: 36),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: p.fg,
                      fontSize: 24,
                      fontFamily: p.display,
                      fontWeight: p.pop ? FontWeight.bold : FontWeight.w400)),
              if (sub != null)
                Text(sub!, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.accent, fontSize: 13, fontFamily: p.mono)),
            ]),
          ),
        ]),
        const SizedBox(height: 8),
        const Ticks(),
        const SizedBox(height: 10),
      ]),
    );
  }
}

/// 検索欄（角を落とした枠）
class _Search extends StatelessWidget {
  final ValueChanged<String> onChanged;
  const _Search({required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final p = HudScope.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 10, 10),
      child: Material(
        color: p.pop ? p.panel : p.raised,
        shape: p.shape(side: p.line),
        child: Row(children: [
          const SizedBox(width: 12),
          Icon(Icons.search, color: p.accent, size: 22),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              onChanged: onChanged,
              style: TextStyle(color: p.fg, fontFamily: p.mono, fontSize: 15),
              cursorColor: p.accent,
              decoration: InputDecoration(
                border: InputBorder.none,
                isDense: true,
                hintText: 'SEARCH  検索',
                hintStyle: TextStyle(color: p.faint, fontFamily: p.mono, letterSpacing: 1.5),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

/// 一覧の枠（残りの高さいっぱい）
class _ListPanel extends StatelessWidget {
  final String code;
  final String title;
  final int count;
  final IndexedWidgetBuilder itemBuilder;
  const _ListPanel({
    required this.code,
    required this.title,
    required this.count,
    required this.itemBuilder,
  });

  @override
  Widget build(BuildContext context) {
    final p = HudScope.of(context);
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 10, 10),
        child: HudPanel(
          code: code,
          title: title,
          expand: true,
          padding: const EdgeInsets.fromLTRB(4, 12, 4, 4),
          trailing: Text('$count', style: TextStyle(color: p.faint, fontSize: 11, fontFamily: p.mono)),
          child: count == 0
              ? const Note('見つかりません')
              : ListView.builder(itemCount: count, itemBuilder: itemBuilder, padding: EdgeInsets.zero),
        ),
      ),
    );
  }
}

Widget _emptyLibrary(BuildContext context) {
  return Padding(
    padding: const EdgeInsets.fromLTRB(14, 0, 10, 10),
    child: HudPanel(
      code: 'LIBRARY',
      title: 'ライブラリ',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Note(services.settings.configured
            ? 'ライブラリが空です。LIBRARY のタブで更新してください。'
            : '接続先が未設定です。SETUP で NAS（WebDAV か DS audio）を設定してください。'),
        const SizedBox(height: 8),
        PillButton(
          text: services.settings.configured ? 'ライブラリを更新' : '接続設定',
          primary: true,
          onTap: () => services.settings.configured ? hudNav.selectTab(6) : showServerDialog(context),
        ),
      ]),
    ),
  );
}

// ------------------------------------------------------------------ NOW

class NowPage extends StatelessWidget {
  const NowPage({super.key});

  @override
  Widget build(BuildContext context) {
    final p = HudScope.of(context);
    final pl = services.player;
    final t = pl.current;
    final s = services.settings;
    return ListView(padding: EdgeInsets.zero, children: [
      StreamBuilder<Duration>(
        stream: pl.audio.positionStream,
        builder: (context, snap) => _RootHeader(
          code: 'NOW.PLAYING',
          big: t == null ? '--:--' : _fmt(snap.data ?? Duration.zero),
          en: t == null ? 'STANDBY' : 'TRACK ${(pl.index + 1).toString().padLeft(2, '0')}/${pl.queue.length.toString().padLeft(2, '0')}',
          ja: t == null ? '待機中' : (pl.playing ? 'PLAY / 再生中' : 'PAUSE / 一時停止'),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 10, 10),
        child: t == null
            ? HudPanel(
                code: 'TRACK',
                title: '再生中の曲',
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Note('曲を選ぶと、ここに出ます。'),
                  const SizedBox(height: 8),
                  PillButton(
                    text: 'SHUFFLE ALL  全曲シャッフル',
                    icon: Icons.shuffle,
                    primary: true,
                    onTap: services.library.songs.isEmpty ? null : () => _play(services.library.songs, 0, shuffle: true),
                  ),
                ]),
              )
            : HudPanel(
                code: 'TRACK',
                title: '再生中の曲',
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 300),
                      child: HudArt(t.art),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(t.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: p.fg,
                          fontSize: 26,
                          height: 1.2,
                          fontFamily: p.display,
                          fontWeight: p.pop ? FontWeight.bold : FontWeight.w400)),
                  const SizedBox(height: 4),
                  Text(t.displayArtist, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.muted, fontSize: 14, fontFamily: p.mono)),
                  Text('${t.displayAlbum}${t.year != 0 ? '  ·  ${t.year}' : ''}',
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.accent, fontSize: 14, fontFamily: p.mono)),
                  const SizedBox(height: 12),
                  const _Seekbar(),
                  const SizedBox(height: 12),
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    PillButton(icon: Icons.skip_previous, onTap: pl.previous, minHeight: 48, iconSize: 26),
                    const SizedBox(width: 12),
                    PillButton(
                        icon: pl.playing ? Icons.pause : Icons.play_arrow,
                        primary: true,
                        onTap: pl.toggle,
                        minHeight: 56,
                        iconSize: 34),
                    const SizedBox(width: 12),
                    PillButton(icon: Icons.skip_next, onTap: pl.next, minHeight: 48, iconSize: 26),
                  ]),
                  const SizedBox(height: 12),
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    HudBadge('SHUF', width: 64, highlight: s.shuffle, onTap: () {
                      s.shuffle = !s.shuffle;
                      s.save();
                    }),
                    const SizedBox(width: 8),
                    HudBadge(
                      switch (s.repeat) {
                        RepeatSetting.off => 'RPT:OFF',
                        RepeatSetting.one => 'RPT:ONE',
                        RepeatSetting.all => 'RPT:ALL',
                      },
                      width: 76,
                      highlight: s.repeat != RepeatSetting.off,
                      onTap: () {
                        s.repeat = RepeatSetting.values[(s.repeat.index + 1) % 3];
                        s.save();
                      },
                    ),
                    const SizedBox(width: 8),
                    HudBadge(_extOf(t.path), width: 64),
                  ]),
                  if (pl.lastError != null) ...[
                    const SizedBox(height: 8),
                    Text(pl.lastError!, maxLines: 3, style: TextStyle(color: p.accent2 == p.accent ? Colors.redAccent : p.accent2, fontSize: 11)),
                  ],
                ]),
              ),
      ),
      const _StatusRow(),
      if (t != null) const _QueuePanel(),
      const SizedBox(height: 10),
    ]);
  }
}

class _Seekbar extends StatelessWidget {
  const _Seekbar();

  @override
  Widget build(BuildContext context) {
    final p = HudScope.of(context);
    final pl = services.player;
    return StreamBuilder<Duration>(
      stream: pl.audio.positionStream,
      builder: (context, snap) {
        final pos = snap.data ?? Duration.zero;
        final dur = pl.audio.duration ?? Duration.zero;
        final v = dur.inMilliseconds == 0 ? 0.0 : pos.inMilliseconds / dur.inMilliseconds;
        final remain = dur - pos;
        void seek(Offset local, double width) {
          if (dur == Duration.zero) return;
          pl.audio.seek(dur * (local.dx / width).clamp(0.0, 1.0));
        }

        return LayoutBuilder(builder: (context, c) {
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (d) => seek(d.localPosition, c.maxWidth),
            onHorizontalDragUpdate: (d) => seek(d.localPosition, c.maxWidth),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                HudProgress(v),
                const SizedBox(height: 4),
                Row(children: [
                  Text('ELAPSED ${_fmt(pos)}', style: TextStyle(color: p.faint, fontSize: 11, fontFamily: p.mono, letterSpacing: 1)),
                  const Spacer(),
                  Text('REMAIN -${_fmt(remain.isNegative ? Duration.zero : remain)}',
                      style: TextStyle(color: p.faint, fontSize: 11, fontFamily: p.mono, letterSpacing: 1)),
                ]),
              ]),
            ),
          );
        });
      },
    );
  }
}

/// 接続先・曲数などの計器（ThetaHomeHatch の NET / TAILSCALE / NAS の並び）
class _StatusRow extends StatelessWidget {
  const _StatusRow();

  @override
  Widget build(BuildContext context) {
    final s = services.settings;
    final ds = s.source == MusicSource.dsaudio;
    final host = Uri.tryParse(ds ? s.dsUrl : s.serverUrl)?.host ?? '';
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 10, 10),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          ReadoutBox('SOURCE', ds ? 'DS AUDIO' : 'WEBDAV', accent: true),
          const SizedBox(width: 8),
          ReadoutBox('NAS', s.configured ? (host.isEmpty ? '設定済み' : host) : '未登録'),
          const SizedBox(width: 8),
          ReadoutBox('SONGS', '${services.library.tracks.length}'),
          const SizedBox(width: 8),
          ReadoutBox('QUEUE', '${services.player.queue.length}'),
        ]),
      ),
    );
  }
}

class _QueuePanel extends StatelessWidget {
  const _QueuePanel();

  @override
  Widget build(BuildContext context) {
    final p = HudScope.of(context);
    final pl = services.player;
    final start = pl.index.clamp(0, pl.queue.length);
    final end = (start + 30).clamp(0, pl.queue.length);
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 10, 0),
      child: HudPanel(
        code: 'QUEUE',
        title: 'この後の曲',
        padding: const EdgeInsets.fromLTRB(4, 12, 4, 4),
        child: Column(children: [
          for (var i = start; i < end; i++)
            HudRow(
              zebra: i - start,
              active: i == pl.index,
              onTap: () => pl.jumpTo(i),
              child: Row(children: [
                SizedBox(
                  width: 30,
                  child: Text((i + 1).toString().padLeft(2, '0'),
                      style: TextStyle(color: i == pl.index ? p.accent : p.faint, fontFamily: p.mono, fontSize: 12)),
                ),
                Expanded(child: TwoLines(pl.queue[i].title, pl.queue[i].displayArtist)),
              ]),
            ),
        ]),
      ),
    );
  }
}

// ------------------------------------------------------------------ ARTISTS

class ArtistsPage extends StatefulWidget {
  const ArtistsPage({super.key});
  @override
  State<ArtistsPage> createState() => _ArtistsPageState();
}

class _ArtistsPageState extends State<ArtistsPage> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final all = services.library.artists;
    final list = _q.isEmpty ? all : all.where((a) => a.name.toLowerCase().contains(_q)).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _RootHeader(code: 'LIB.ARTISTS', big: '${all.length}', en: 'ARTISTS', ja: 'アーティスト'),
      if (all.isEmpty) _emptyLibrary(context) else ...[
        _Search(onChanged: (v) => setState(() => _q = v.toLowerCase())),
        _ListPanel(
          code: 'ARTISTS',
          title: 'アーティスト',
          count: list.length,
          itemBuilder: (context, i) {
            final a = list[i];
            return HudRow(
              zebra: i,
              onTap: () => hudNav.open(ArtistDetail(artist: a)),
              child: Row(children: [
                Initial(a.name, size: 38),
                const SizedBox(width: 12),
                Expanded(child: TwoLines(a.name, '${a.albums.length} ALBUMS · ${a.tracks.length} SONGS')),
              ]),
            );
          },
        ),
      ],
    ]);
  }
}

class ArtistDetail extends StatelessWidget {
  final Artist artist;
  const ArtistDetail({super.key, required this.artist});

  @override
  Widget build(BuildContext context) {
    return ListView(padding: EdgeInsets.zero, children: [
      _DetailHeader(code: 'LIB.ARTIST', title: artist.name, sub: '${artist.albums.length} ALBUMS / ${artist.tracks.length} SONGS'),
      Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 10, 10),
        child: Row(children: [
          PillButton(text: 'PLAY ALL', icon: Icons.play_arrow, primary: true, onTap: () => _play(artist.tracks, 0)),
          const SizedBox(width: 10),
          PillButton(text: 'SHUFFLE', icon: Icons.shuffle, onTap: () => _play(artist.tracks, 0, shuffle: true)),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 10, 10),
        child: HudPanel(code: 'ALBUMS', title: 'アルバム', child: _AlbumGrid(albums: artist.albums, shrink: true)),
      ),
    ]);
  }
}

// ------------------------------------------------------------------ ALBUMS

class AlbumsPage extends StatefulWidget {
  final List<Album> albums;
  final String? genre; // ジャンルから開いたとき
  const AlbumsPage({super.key, required this.albums, this.genre});
  @override
  State<AlbumsPage> createState() => _AlbumsPageState();
}

class _AlbumsPageState extends State<AlbumsPage> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final all = widget.albums;
    final list = _q.isEmpty
        ? all
        : all.where((a) => a.title.toLowerCase().contains(_q) || a.artist.toLowerCase().contains(_q)).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (widget.genre != null)
        _DetailHeader(code: 'LIB.GENRE', title: widget.genre!, sub: '${all.length} ALBUMS')
      else
        _RootHeader(code: 'LIB.ALBUMS', big: '${all.length}', en: 'ALBUMS', ja: 'アルバム'),
      if (services.library.tracks.isEmpty) _emptyLibrary(context) else ...[
        _Search(onChanged: (v) => setState(() => _q = v.toLowerCase())),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 10, 10),
            child: HudPanel(
              code: 'ALBUMS',
              title: 'アルバム',
              expand: true,
              child: _AlbumGrid(albums: list),
            ),
          ),
        ),
      ],
    ]);
  }
}

class _AlbumGrid extends StatelessWidget {
  final List<Album> albums;
  final bool shrink;
  const _AlbumGrid({required this.albums, this.shrink = false});

  @override
  Widget build(BuildContext context) {
    final p = HudScope.of(context);
    return LayoutBuilder(builder: (context, c) {
      final cols = (c.maxWidth / 150).floor().clamp(2, 5);
      return GridView.builder(
        shrinkWrap: shrink,
        physics: shrink ? const NeverScrollableScrollPhysics() : null,
        padding: EdgeInsets.zero,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: cols,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 0.74,
        ),
        itemCount: albums.length,
        itemBuilder: (context, i) {
          final a = albums[i];
          return GestureDetector(
            onTap: () => hudNav.open(AlbumDetail(album: a)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              HudArt(a.art),
              const SizedBox(height: 6),
              Text(a.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.fg, fontSize: 13)),
              Text(a.artist,
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.faint, fontSize: 11, fontFamily: p.mono)),
            ]),
          );
        },
      );
    });
  }
}

class AlbumDetail extends StatelessWidget {
  final Album album;
  const AlbumDetail({super.key, required this.album});

  @override
  Widget build(BuildContext context) {
    final p = HudScope.of(context);
    final cur = services.player.current?.path;
    return ListView(padding: EdgeInsets.zero, children: [
      _DetailHeader(code: 'LIB.ALBUM', title: album.title, sub: album.artist),
      Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 10, 10),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          HudArt(album.art, size: 128),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              ReadoutBox('YEAR', album.year == 0 ? '—' : '${album.year}'),
              const SizedBox(height: 6),
              ReadoutBox('TRACKS', '${album.tracks.length}', accent: true),
              const SizedBox(height: 6),
              ReadoutBox('GENRE', album.genre.isEmpty ? '—' : album.genre),
            ]),
          ),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 10, 10),
        child: Row(children: [
          PillButton(text: 'PLAY', icon: Icons.play_arrow, primary: true, onTap: () => _play(album.tracks, 0)),
          const SizedBox(width: 10),
          PillButton(text: 'SHUFFLE', icon: Icons.shuffle, onTap: () => _play(album.tracks, 0, shuffle: true)),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 10, 10),
        child: HudPanel(
          code: 'TRACKS',
          title: '曲',
          padding: const EdgeInsets.fromLTRB(4, 12, 4, 4),
          child: Column(children: [
            for (var i = 0; i < album.tracks.length; i++)
              HudRow(
                zebra: i,
                active: album.tracks[i].path == cur,
                onTap: () => _play(album.tracks, i),
                child: Row(children: [
                  SizedBox(
                    width: 34,
                    child: Text(
                      album.tracks[i].trackNo == 0 ? '--' : album.tracks[i].trackNo.toString().padLeft(2, '0'),
                      style: TextStyle(color: album.tracks[i].path == cur ? p.accent : p.faint, fontFamily: p.mono, fontSize: 12),
                    ),
                  ),
                  Expanded(
                    child: TwoLines(
                      album.tracks[i].title,
                      album.tracks[i].displayArtist == album.artist ? null : album.tracks[i].displayArtist,
                    ),
                  ),
                ]),
              ),
          ]),
        ),
      ),
    ]);
  }
}

// ------------------------------------------------------------------ SONGS

class SongsPage extends StatefulWidget {
  final List<Track> tracks;
  const SongsPage({super.key, required this.tracks});
  @override
  State<SongsPage> createState() => _SongsPageState();
}

class _SongsPageState extends State<SongsPage> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final p = HudScope.of(context);
    final all = widget.tracks;
    final list = _q.isEmpty
        ? all
        : all
            .where((t) =>
                t.title.toLowerCase().contains(_q) ||
                t.artist.toLowerCase().contains(_q) ||
                t.album.toLowerCase().contains(_q))
            .toList();
    final cur = services.player.current?.path;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _RootHeader(code: 'LIB.SONGS', big: '${all.length}', en: 'SONGS', ja: '曲'),
      if (all.isEmpty) _emptyLibrary(context) else ...[
        _Search(onChanged: (v) => setState(() => _q = v.toLowerCase())),
        _ListPanel(
          code: 'SONGS',
          title: '曲',
          count: list.length,
          itemBuilder: (context, i) => HudRow(
            zebra: i,
            active: list[i].path == cur,
            onTap: () => _play(list, i),
            child: Row(children: [
              HudBadge(_extOf(list[i].path), width: 44),
              const SizedBox(width: 10),
              Expanded(child: TwoLines(list[i].title, '${list[i].displayArtist} · ${list[i].displayAlbum}')),
              if (list[i].path == cur) Icon(Icons.graphic_eq, color: p.accent, size: 18),
            ]),
          ),
        ),
      ],
    ]);
  }
}

// ------------------------------------------------------------------ GENRES

class GenresPage extends StatelessWidget {
  const GenresPage({super.key});

  @override
  Widget build(BuildContext context) {
    final p = HudScope.of(context);
    final g = services.library.genres.entries.toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _RootHeader(code: 'LIB.GENRES', big: '${g.length}', en: 'GENRES', ja: 'ジャンル'),
      if (services.library.tracks.isEmpty)
        _emptyLibrary(context)
      else
        _ListPanel(
          code: 'GENRES',
          title: 'ジャンル',
          count: g.length,
          itemBuilder: (context, i) => HudRow(
            zebra: i,
            onTap: () {
              final albums = services.library.albums
                  .where((a) => a.tracks.any((t) => (t.genre.isEmpty ? 'Unknown Genre' : t.genre) == g[i].key))
                  .toList();
              hudNav.open(AlbumsPage(albums: albums, genre: g[i].key));
            },
            child: Row(children: [
              Expanded(child: Text(g[i].key, style: TextStyle(color: p.fg, fontSize: 15))),
              Text('${g[i].value.length}', style: TextStyle(color: p.faint, fontFamily: p.mono, fontSize: 12)),
              Icon(Icons.chevron_right, color: p.faint),
            ]),
          ),
        ),
    ]);
  }
}

// ------------------------------------------------------------------ FOLDERS

class FolderPage extends StatelessWidget {
  final String dir;
  const FolderPage({super.key, required this.dir});

  @override
  Widget build(BuildContext context) {
    final p = HudScope.of(context);
    final root = dir == services.library.root;
    final (subs, files) = services.library.folderChildren(dir);
    final name = dir.substring(dir.lastIndexOf('/') + 1);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (root)
        _RootHeader(code: 'LIB.FOLDERS', big: '${subs.length}', en: 'FOLDERS', ja: 'フォルダ')
      else
        _DetailHeader(code: 'LIB.FOLDER', title: name, sub: dir),
      if (services.library.tracks.isEmpty)
        _emptyLibrary(context)
      else
        _ListPanel(
          code: 'FILES',
          title: root ? (dir.isEmpty ? '/' : dir) : 'ファイル',
          count: subs.length + files.length,
          itemBuilder: (context, i) {
            if (i < subs.length) {
              return HudRow(
                zebra: i,
                onTap: () => hudNav.open(FolderPage(dir: '$dir/${subs[i]}')),
                child: Row(children: [
                  const HudBadge('DIR', highlight: true, width: 44),
                  const SizedBox(width: 10),
                  Expanded(child: Text(subs[i], maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.fg, fontSize: 15))),
                  Icon(Icons.chevron_right, color: p.faint),
                ]),
              );
            }
            final j = i - subs.length;
            return HudRow(
              zebra: i,
              onTap: () => _play(files, j),
              child: Row(children: [
                HudBadge(_extOf(files[j].path), width: 44),
                const SizedBox(width: 10),
                Expanded(child: TwoLines(files[j].title, files[j].fileName)),
              ]),
            );
          },
        ),
    ]);
  }
}

// ------------------------------------------------------------------ LIBRARY

class LibraryPage extends StatelessWidget {
  const LibraryPage({super.key});

  @override
  Widget build(BuildContext context) {
    final p = HudScope.of(context);
    final lib = services.library;
    return ListenableBuilder(
      listenable: Listenable.merge([services.scanner, services.obsidian]),
      builder: (context, _) {
        final sc = services.scanner;
        final ob = services.obsidian;
        final s = services.settings;
        final at = lib.scannedAt;
        return ListView(padding: EdgeInsets.zero, children: [
          _RootHeader(code: 'LIB.STATUS', big: '${lib.tracks.length}', en: 'LIBRARY', ja: 'ライブラリ'),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 10, 10),
            child: Row(children: [
              Expanded(child: ReadoutBox('ALBUMS', '${lib.albums.length}')),
              const SizedBox(width: 8),
              Expanded(child: ReadoutBox('ARTISTS', '${lib.artists.length}')),
              const SizedBox(width: 8),
              Expanded(child: ReadoutBox('GENRES', '${lib.genres.length}')),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 10, 10),
            child: HudPanel(
              code: 'SCAN',
              title: 'ライブラリの更新',
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  Expanded(
                    child: ReadoutBox('SOURCE', s.source == MusicSource.dsaudio ? 'DS AUDIO' : 'WEBDAV', accent: true),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ReadoutBox(
                        'LAST SCAN',
                        at == null
                            ? '未スキャン'
                            : '${at.month.toString().padLeft(2, '0')}.${at.day.toString().padLeft(2, '0')} ${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}'),
                  ),
                ]),
                const SizedBox(height: 10),
                if (sc.running || sc.status.isNotEmpty) ...[
                  Text(
                    sc.running
                        ? 'DIR ${sc.dirs}  FILE ${sc.files}${sc.tagsTotal > 0 ? '  TAG ${sc.tagsDone}/${sc.tagsTotal}' : ''}'
                        : sc.status,
                    maxLines: 3,
                    style: TextStyle(color: sc.error != null ? Colors.redAccent : p.muted, fontFamily: p.mono, fontSize: 12),
                  ),
                  const SizedBox(height: 6),
                  if (sc.running) HudProgress(sc.tagsTotal == 0 ? 0 : sc.tagsDone / sc.tagsTotal),
                  const SizedBox(height: 10),
                ],
                Note(s.source == MusicSource.dsaudio
                    ? 'Audio Station が作ったライブラリ（曲・タグ）をそのまま取り込みます。'
                    : 'NAS のフォルダを巡回してタグを読みます。2 回目からは変わったファイルだけ読み直します。'),
                const SizedBox(height: 6),
                Wrap(spacing: 10, runSpacing: 10, children: [
                  if (sc.running)
                    PillButton(text: 'CANCEL 中止', onTap: sc.cancel)
                  else ...[
                    PillButton(
                      text: 'UPDATE 更新',
                      icon: Icons.sync,
                      primary: true,
                      onTap: () => s.configured ? sc.scan() : showServerDialog(context),
                    ),
                    if (s.source == MusicSource.webdav)
                      PillButton(text: 'REBUILD 全部読み直す', onTap: () => s.configured ? sc.scan(full: true) : showServerDialog(context)),
                  ],
                ]),
              ]),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 10, 10),
            child: HudPanel(
              code: 'OBSIDIAN',
              title: 'Vault へ書き出し',
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                ReadoutBox('VAULT', s.obsidianPath.isEmpty ? '未設定' : s.obsidianPath, accent: s.obsidianPath.isNotEmpty),
                const SizedBox(height: 8),
                if (ob.running || ob.status.isNotEmpty) ...[
                  Text(ob.running ? 'NOTE ${ob.done}/${ob.total}' : ob.status,
                      style: TextStyle(color: p.muted, fontFamily: p.mono, fontSize: 12)),
                  const SizedBox(height: 6),
                  if (ob.running) HudProgress(ob.total == 0 ? 0 : ob.done / ob.total),
                  const SizedBox(height: 8),
                ],
                const Note('Albums/・Artists/ にノートを作ります。ノートに書き足したメモは、書き出し直しても残ります。'),
                const SizedBox(height: 6),
                Wrap(spacing: 10, runSpacing: 10, children: [
                  PillButton(
                    text: 'EXPORT 書き出す',
                    icon: Icons.upload,
                    primary: true,
                    onTap: ob.running || lib.tracks.isEmpty
                        ? null
                        : () async {
                            if (s.obsidianPath.trim().isEmpty) await showObsidianDialog(context);
                            if (s.obsidianPath.trim().isNotEmpty) await ob.export();
                          },
                  ),
                  PillButton(text: 'FOLDER 書き出し先', onTap: () => showObsidianDialog(context)),
                ]),
              ]),
            ),
          ),
        ]);
      },
    );
  }
}

// ------------------------------------------------------------------ SETUP

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final p = HudScope.of(context);
    final s = services.settings;
    final ds = s.source == MusicSource.dsaudio;
    final host = Uri.tryParse(ds ? s.dsUrl : s.serverUrl)?.host ?? '';
    void set(VoidCallback f) {
      f();
      s.save();
    }

    Widget choice(String label, bool on, VoidCallback tap) => HudBadge(label, highlight: on, onTap: tap, width: 78);

    return ListView(padding: EdgeInsets.zero, children: [
      _RootHeader(code: 'SYS.SETUP', big: 'SETUP', en: 'SETTINGS', ja: '設定'),
      Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 10, 10),
        child: HudPanel(
          code: 'SOURCE',
          title: '接続先',
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(child: ReadoutBox('MODE', ds ? 'DS AUDIO' : 'WEBDAV', accent: true)),
              const SizedBox(width: 8),
              Expanded(child: ReadoutBox('HOST', s.configured ? host : '未登録')),
            ]),
            const SizedBox(height: 8),
            const Note('Tailscale を ON にしてから、NAS の Tailscale IP か MagicDNS 名で接続します。'),
            Align(
              alignment: Alignment.centerLeft,
              child: PillButton(text: '接続設定', icon: Icons.dns_outlined, primary: true, onTap: () => showServerDialog(context)),
            ),
          ]),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 10, 10),
        child: HudPanel(
          code: 'SKIN',
          title: '見た目',
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(spacing: 8, runSpacing: 8, children: [
              choice('THETA', s.skin == 'theta', () => set(() => s.skin = 'theta')),
              choice('IPOD', s.skin == 'ipod', () => set(() => s.skin = 'ipod')),
            ]),
            const SizedBox(height: 12),
            Text('THEME', style: TextStyle(color: p.faint, fontSize: 10, letterSpacing: 1.5, fontFamily: p.mono)),
            const SizedBox(height: 6),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final t in hudThemes)
                choice(t == 'scifi' ? 'SCI-FI' : t.toUpperCase(), s.hudTheme == t, () => set(() => s.hudTheme = t)),
            ]),
          ]),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 10, 10),
        child: HudPanel(
          code: 'PLAYBACK',
          title: '再生とスキャン',
          padding: const EdgeInsets.fromLTRB(4, 12, 4, 4),
          child: Column(children: [
            _toggleRow(context, 0, 'SHUFFLE', 'シャッフル', s.shuffle, () => set(() => s.shuffle = !s.shuffle)),
            _toggleRow(context, 1, 'REPEAT', 'リピート', s.repeat != RepeatSetting.off,
                () => set(() => s.repeat = RepeatSetting.values[(s.repeat.index + 1) % 3]),
                value: s.repeat.name.toUpperCase()),
            _toggleRow(context, 2, 'READ TAGS', 'タグを読む（WebDAV）', s.readTags, () => set(() => s.readTags = !s.readTags)),
            _toggleRow(context, 3, 'TRANSCODE', 'MP3 に変換（DS audio）', s.dsTranscode,
                () => set(() => s.dsTranscode = !s.dsTranscode)),
          ]),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 10, 10),
        child: HudPanel(
          code: 'ABOUT',
          title: 'このアプリ',
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('THETA MUSIC HATCH',
                style: TextStyle(color: p.fg, fontSize: 20, fontFamily: p.display, letterSpacing: 1)),
            const Note('NAS（WebDAV / DS audio）を Tailscale 経由で再生します。見出しの書体は Oswald・Share Tech Mono（SIL OFL）。'),
          ]),
        ),
      ),
    ]);
  }

  Widget _toggleRow(BuildContext context, int i, String en, String ja, bool on, VoidCallback tap, {String? value}) {
    final p = HudScope.of(context);
    return HudRow(
      zebra: i,
      onTap: tap,
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(en, style: TextStyle(color: p.fg, fontSize: 14, fontFamily: p.mono, letterSpacing: 1)),
            Text(ja, style: TextStyle(color: p.faint, fontSize: 11)),
          ]),
        ),
        HudBadge(value ?? (on ? 'ON' : 'OFF'), highlight: on, onTap: tap, width: 56),
      ]),
    );
  }
}
