import 'package:flutter/material.dart';

import '../../app.dart';
import '../../core/clicker.dart';
import '../../core/models.dart';
import '../../core/obsidian.dart' show defaultVaultMusic;
import '../../core/search.dart';
import '../../core/series.dart';
import '../../core/settings.dart';
import '../../core/voice.dart';
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

void _favTrack(BuildContext context, Track t) =>
    hudToast(context, services.favorites.toggleTrack(t) ? '★ お気に入りに追加: ${t.title}' : 'お気に入りから外しました');
void _favAlbum(BuildContext context, Album a) =>
    hudToast(context, services.favorites.toggleAlbum(a) ? '★ お気に入りに追加: ${a.title}' : 'お気に入りから外しました');
void _favArtist(BuildContext context, Artist a) =>
    hudToast(context, services.favorites.toggleArtist(a) ? '★ お気に入りに追加: ${a.name}' : 'お気に入りから外しました');

/// 音声入力 → 「〜をかけて」なら再生、それ以外は検索結果へ
Future<void> hudVoiceSearch(BuildContext context) async {
  List<String>? alts;
  try {
    alts = await Voice.listen();
  } catch (e) {
    if (context.mounted) hudToast(context, '$e');
    return;
  }
  if (alts == null || !context.mounted) return;
  hudRunSearch(context, alts);
}

void hudRunSearch(BuildContext context, List<String> alts) {
  final r = searchVoice(services.library, alts);
  if (r == null) return;
  final (res, cmd) = r;
  final best = res.best;
  if (cmd.play && best != null) {
    final (list, i) = best.playable;
    services.player.playList(list, i, shuffle: cmd.shuffle);
    hudNav.selectTab(nowTab);
    hudToast(context, 'PLAY: ${best.label}');
    return;
  }
  hudNav.open(SearchPage(initial: cmd.query));
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

/// 検索欄（角を落とした枠）。右のマイクで音声入力
class _Search extends StatefulWidget {
  final ValueChanged<String> onChanged;
  final ValueChanged<String>? onSubmitted;
  /// マイクで認識したとき（既定は欄に文字を入れる）
  final void Function(List<String> alternatives)? onVoice;
  final String initial;
  final bool autofocus;
  const _Search({required this.onChanged, this.onSubmitted, this.onVoice, this.initial = '', this.autofocus = false});

  @override
  State<_Search> createState() => _SearchState();
}

class _SearchState extends State<_Search> {
  late final TextEditingController _c = TextEditingController(text: widget.initial);

  @override
  void didUpdateWidget(_Search old) {
    super.didUpdateWidget(old);
    // 音声で検索語が変わったとき、欄にも反映
    if (widget.initial != old.initial && widget.initial != _c.text) _c.text = widget.initial;
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Future<void> _voice() async {
    List<String>? alts;
    try {
      alts = await Voice.listen();
    } catch (e) {
      if (mounted) hudToast(context, '$e');
      return;
    }
    if (alts == null || !mounted) return;
    if (widget.onVoice != null) {
      widget.onVoice!(alts);
      return;
    }
    final q = parseVoiceCommand(alts.first).query;
    _c.text = q;
    widget.onChanged(q);
  }

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
              controller: _c,
              autofocus: widget.autofocus,
              onChanged: widget.onChanged,
              onSubmitted: widget.onSubmitted,
              textInputAction: TextInputAction.search,
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
          IconButton(
            tooltip: '音声検索',
            onPressed: _voice,
            icon: Icon(Icons.mic_none, color: p.accent),
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
          onTap: () => services.settings.configured ? hudNav.selectTab(libraryTab) : showServerDialog(context),
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
      // ライブラリ全体の検索。マイクで「〜をかけて」と言うとすぐ再生
      _Search(
        onChanged: (_) {},
        onSubmitted: (q) {
          if (q.trim().isNotEmpty) hudRunSearch(context, [q]);
        },
        onVoice: (alts) => hudRunSearch(context, alts),
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
                    const SizedBox(width: 8),
                    HudBadge(services.favorites.isTrack(t) ? '★ FAV' : '☆ FAV',
                        width: 70, highlight: services.favorites.isTrack(t), onTap: () => _favTrack(context, t)),
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
              onLongPress: () => _favTrack(context, pl.queue[i]),
              child: Row(children: [
                SizedBox(
                  width: 30,
                  child: Text((i + 1).toString().padLeft(2, '0'),
                      style: TextStyle(color: i == pl.index ? p.accent : p.faint, fontFamily: p.mono, fontSize: 12)),
                ),
                Expanded(child: TwoLines(pl.queue[i].title, pl.queue[i].displayArtist)),
                if (services.favorites.isTrack(pl.queue[i])) const FavStar(true, size: 16),
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
              onLongPress: () => _favArtist(context, a),
              child: Row(children: [
                Initial(a.name, size: 38),
                const SizedBox(width: 12),
                Expanded(child: TwoLines(a.name, '${a.albums.length} ALBUMS · ${a.tracks.length} SONGS')),
                if (services.favorites.isArtist(a)) const FavStar(true),
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
          const SizedBox(width: 10),
          PillButton(
            icon: services.favorites.isArtist(artist) ? Icons.star : Icons.star_border,
            text: 'FAV',
            onTap: () => _favArtist(context, artist),
          ),
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
            onLongPress: () => _favAlbum(context, a),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Stack(children: [
                HudArt(a.art),
                if (services.favorites.isAlbum(a))
                  Positioned(
                    right: 4,
                    top: 4,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      color: p.bg.withValues(alpha: 0.7),
                      child: const FavStar(true, size: 16),
                    ),
                  ),
              ]),
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
          const SizedBox(width: 10),
          PillButton(
            icon: services.favorites.isAlbum(album) ? Icons.star : Icons.star_border,
            text: 'FAV',
            onTap: () => _favAlbum(context, album),
          ),
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
                onLongPress: () => _favTrack(context, album.tracks[i]),
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
                  GestureDetector(
                    onTap: () => _favTrack(context, album.tracks[i]),
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: FavStar(services.favorites.isTrack(album.tracks[i])),
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
            onLongPress: () => _favTrack(context, list[i]),
            child: Row(children: [
              HudBadge(_extOf(list[i].path), width: 44),
              const SizedBox(width: 10),
              Expanded(child: TwoLines(list[i].title, '${list[i].displayArtist} · ${list[i].displayAlbum}')),
              if (list[i].path == cur) Icon(Icons.graphic_eq, color: p.accent, size: 18),
              if (services.favorites.isTrack(list[i])) const FavStar(true, size: 16),
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
                ReadoutBox('VAULT', s.obsidianPath.isEmpty ? defaultVaultMusic : s.obsidianPath, accent: true),
                const SizedBox(height: 8),
                if (ob.running || ob.status.isNotEmpty) ...[
                  Text(ob.running ? 'NOTE ${ob.done}/${ob.total}' : ob.status,
                      style: TextStyle(color: p.muted, fontFamily: p.mono, fontSize: 12)),
                  const SizedBox(height: 6),
                  if (ob.running) HudProgress(ob.total == 0 ? 0 : ob.done / ob.total),
                  const SizedBox(height: 8),
                ],
                const Note('Theta Vault の Music/ に、アルバム・アーティストのノートと一覧（.base）を作ります。'
                    'ノートに書き足したメモは、書き出し直しても残ります。お気に入りは favorite: true で、別の端末・入れ直したときに戻せます。'),
                const SizedBox(height: 6),
                Wrap(spacing: 10, runSpacing: 10, children: [
                  PillButton(
                    text: 'EXPORT 書き出す',
                    icon: Icons.upload,
                    primary: true,
                    onTap: ob.running || lib.tracks.isEmpty
                        ? null
                        : ob.export,
                  ),
                  PillButton(
                    text: 'RESTORE お気に入りを戻す',
                    onTap: ob.running || lib.tracks.isEmpty ? null : ob.restoreFavorites,
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
                choice(switch (t) { 'scifi' => 'SCI-FI', 'term' => 'TERMINAL', _ => t.toUpperCase() }, s.hudTheme == t,
                    () {
                  set(() => s.hudTheme = t);
                  // シリーズに合わせるなら、Home にも同じスキンを伝える（ui.skin）
                  if (s.followSeriesSkin) Series.tell('ui.skin', t);
                }),
            ]),
            const SizedBox(height: 4),
            _toggleRow(context, 0, 'FOLLOW HOME', 'スキンをシリーズ（Theta Home Hatch）に合わせる', s.followSeriesSkin,
                () => set(() => s.followSeriesSkin = !s.followSeriesSkin)),
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
            _toggleRow(context, 4, 'FAV = RATING', 'お気に入りを DS audio の★評価と同期', s.dsFavRating > 0,
                () => set(() => s.dsFavRating = switch (s.dsFavRating) { 4 => 5, 5 => 0, 0 => 3, _ => 4 }),
                value: s.dsFavRating == 0 ? 'OFF' : '★${s.dsFavRating}+'),
            _toggleRow(context, 5, 'CLICKER', 'カリカリ音（iPod スキン・メディア音量）', s.clicker, () async {
              set(() => s.clicker = !s.clicker);
              if (s.clicker) {
                final ok = await Clicker.test();
                if (context.mounted) hudToast(context, ok ? 'クリック音はメディアの音量で鳴ります' : 'クリック音を鳴らせませんでした');
              }
            }),
            _toggleRow(context, 6, 'HAPTICS', 'ホイールの振動（iPod スキン）', s.haptics, () => set(() => s.haptics = !s.haptics)),
            _toggleRow(context, 7, 'HOME: FAVORITES', 'Theta Home の棚にお気に入りを出す', s.shelfFavorites,
                () => set(() => s.shelfFavorites = !s.shelfFavorites)),
            _toggleRow(context, 8, 'HOME: RECENT', 'Theta Home の棚に最近再生したアルバムを出す', s.shelfRecent,
                () => set(() => s.shelfRecent = !s.shelfRecent)),
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
            const SizedBox(height: 6),
            const _UpdateBox(),
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

// ------------------------------------------------------------------ FAVS

class FavsPage extends StatelessWidget {
  const FavsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final p = HudScope.of(context);
    final f = services.favorites;
    final tracks = f.tracks, albums = f.albums, artists = f.artists;
    final cur = services.player.current?.path;
    return ListView(padding: EdgeInsets.zero, children: [
      _RootHeader(code: 'LIB.FAVORITES', big: '${f.count}', en: 'FAVORITES', ja: 'お気に入り'),
      if (f.count == 0)
        const Padding(
          padding: EdgeInsets.fromLTRB(14, 0, 10, 10),
          child: HudPanel(
            code: 'HOW TO',
            title: '登録のしかた',
            child: Note('曲・アルバム・アーティストの ★ を押すか、行を長押しすると、ここに並びます。'
                'iPod スキンでは中央ボタンの長押しです。'),
          ),
        )
      else ...[
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 10, 10),
          child: Wrap(spacing: 10, runSpacing: 10, children: [
            PillButton(text: 'PLAY ALL', icon: Icons.play_arrow, primary: true, onTap: () => _play(f.allTracks, 0)),
            PillButton(text: 'SHUFFLE', icon: Icons.shuffle, onTap: () => _play(f.allTracks, 0, shuffle: true)),
          ]),
        ),
        if (artists.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 10, 10),
            child: HudPanel(
              code: 'ARTISTS',
              title: 'アーティスト',
              padding: const EdgeInsets.fromLTRB(4, 12, 4, 4),
              child: Column(children: [
                for (var i = 0; i < artists.length; i++)
                  HudRow(
                    zebra: i,
                    onTap: () => hudNav.open(ArtistDetail(artist: artists[i])),
                    onLongPress: () => _favArtist(context, artists[i]),
                    child: Row(children: [
                      Initial(artists[i].name, size: 34),
                      const SizedBox(width: 12),
                      Expanded(child: TwoLines(artists[i].name, '${artists[i].tracks.length} SONGS')),
                      const FavStar(true),
                    ]),
                  ),
              ]),
            ),
          ),
        if (albums.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 10, 10),
            child: HudPanel(code: 'ALBUMS', title: 'アルバム', child: _AlbumGrid(albums: albums, shrink: true)),
          ),
        if (tracks.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 10, 10),
            child: HudPanel(
              code: 'SONGS',
              title: '曲',
              padding: const EdgeInsets.fromLTRB(4, 12, 4, 4),
              child: Column(children: [
                for (var i = 0; i < tracks.length; i++)
                  HudRow(
                    zebra: i,
                    active: tracks[i].path == cur,
                    onTap: () => _play(tracks, i),
                    onLongPress: () => _favTrack(context, tracks[i]),
                    child: Row(children: [
                      HudBadge(_extOf(tracks[i].path), width: 44),
                      const SizedBox(width: 10),
                      Expanded(child: TwoLines(tracks[i].title, '${tracks[i].displayArtist} · ${tracks[i].displayAlbum}')),
                      GestureDetector(
                        onTap: () => _favTrack(context, tracks[i]),
                        child: const Padding(padding: EdgeInsets.all(6), child: FavStar(true)),
                      ),
                    ]),
                  ),
              ]),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 10, 10),
          child: Note('長押しか ★ で外せます。Obsidian に書き出すと favorite: true が付きます。',),
        ),
      ],
      SizedBox(height: p.pop ? 6 : 0),
    ]);
  }
}

// ------------------------------------------------------------------ SEARCH

class SearchPage extends StatefulWidget {
  final String initial;
  const SearchPage({super.key, this.initial = ''});
  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  late String _q = widget.initial;

  @override
  Widget build(BuildContext context) {
    final p = HudScope.of(context);
    final r = search(services.library, _q, limit: 30);
    final best = r.best;
    Widget section(String code, String title, List<Widget> rows) => Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 10, 10),
          child: HudPanel(
            code: code,
            title: title,
            padding: const EdgeInsets.fromLTRB(4, 12, 4, 4),
            trailing: Text('${rows.length}', style: TextStyle(color: p.faint, fontSize: 11, fontFamily: p.mono)),
            child: Column(children: rows),
          ),
        );
    return ListView(padding: EdgeInsets.zero, children: [
      _DetailHeader(code: 'LIB.SEARCH', title: _q.isEmpty ? 'SEARCH' : _q, sub: '検索・音声検索'),
      _Search(
        initial: _q,
        autofocus: _q.isEmpty,
        onChanged: (v) => setState(() => _q = v),
        onVoice: (alts) {
          final v = searchVoice(services.library, alts);
          if (v == null) return;
          if (v.$2.play && v.$1.best != null) {
            hudRunSearch(context, alts);
          } else {
            setState(() => _q = v.$2.query);
          }
        },
      ),
      if (_q.trim().isNotEmpty && r.isEmpty)
        const Padding(padding: EdgeInsets.fromLTRB(14, 0, 10, 10), child: Note('見つかりません。')),
      if (best != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 10, 10),
          child: HudPanel(
            code: 'BEST',
            title: 'いちばん近い',
            child: Row(children: [
              Expanded(
                child: TwoLines(
                  best.label,
                  switch (best.kind) { HitKind.artist => 'ARTIST', HitKind.album => 'ALBUM', HitKind.track => 'SONG' },
                  bold: true,
                ),
              ),
              PillButton(
                icon: Icons.play_arrow,
                text: 'PLAY',
                primary: true,
                onTap: () {
                  final (list, i) = best.playable;
                  _play(list, i);
                },
              ),
            ]),
          ),
        ),
      if (r.artists.isNotEmpty)
        section('ARTISTS', 'アーティスト', [
          for (var i = 0; i < r.artists.length; i++)
            HudRow(
              zebra: i,
              onTap: () => hudNav.open(ArtistDetail(artist: r.artists[i])),
              onLongPress: () => _favArtist(context, r.artists[i]),
              child: Row(children: [
                Initial(r.artists[i].name, size: 34),
                const SizedBox(width: 12),
                Expanded(child: TwoLines(r.artists[i].name, '${r.artists[i].albums.length} ALBUMS')),
                if (services.favorites.isArtist(r.artists[i])) const FavStar(true),
              ]),
            ),
        ]),
      if (r.albums.isNotEmpty)
        section('ALBUMS', 'アルバム', [
          for (var i = 0; i < r.albums.length; i++)
            HudRow(
              zebra: i,
              onTap: () => hudNav.open(AlbumDetail(album: r.albums[i])),
              onLongPress: () => _favAlbum(context, r.albums[i]),
              child: Row(children: [
                HudArt(r.albums[i].art, size: 40),
                const SizedBox(width: 12),
                Expanded(child: TwoLines(r.albums[i].title, r.albums[i].artist)),
                if (services.favorites.isAlbum(r.albums[i])) const FavStar(true),
              ]),
            ),
        ]),
      if (r.tracks.isNotEmpty)
        section('SONGS', '曲', [
          for (var i = 0; i < r.tracks.length; i++)
            HudRow(
              zebra: i,
              onTap: () => _play(r.tracks, i),
              onLongPress: () => _favTrack(context, r.tracks[i]),
              child: Row(children: [
                HudBadge(_extOf(r.tracks[i].path), width: 44),
                const SizedBox(width: 10),
                Expanded(child: TwoLines(r.tracks[i].title, '${r.tracks[i].displayArtist} · ${r.tracks[i].displayAlbum}')),
                if (services.favorites.isTrack(r.tracks[i])) const FavStar(true, size: 16),
              ]),
            ),
        ]),
      const Padding(
        padding: EdgeInsets.fromLTRB(14, 0, 10, 10),
        child: Note('マイクで「〇〇をかけて」「〇〇をシャッフルで再生」と言うと、すぐに流します。'
            '「アーティストの曲名」の言い方もできます。'),
      ),
    ]);
  }
}

/// 今の版・新しい版と「更新する」（更新はハブに頼む。無ければ Releases ページ。spec §6.1）
class _UpdateBox extends StatefulWidget {
  const _UpdateBox();
  @override
  State<_UpdateBox> createState() => _UpdateBoxState();
}

class _UpdateBoxState extends State<_UpdateBox> {
  String _version = '';
  String? _latest;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    Series.version().then((v) {
      if (mounted) setState(() => _version = v);
    });
  }

  Future<void> _check() async {
    setState(() => _checking = true);
    final l = await Series.latest();
    if (!mounted) return;
    setState(() {
      _checking = false;
      _latest = l ?? '';
    });
    if (l == null) hudToast(context, '新しい版を調べられませんでした');
  }

  @override
  Widget build(BuildContext context) {
    final hasNew = (_latest ?? '').isNotEmpty && _version.isNotEmpty && Series.newer(_latest!, _version);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(child: ReadoutBox('VERSION', _version.isEmpty ? '—' : _version)),
        const SizedBox(width: 8),
        Expanded(
          child: ReadoutBox('LATEST', _latest == null ? '未確認' : (_latest!.isEmpty ? '—' : _latest!), accent: hasNew),
        ),
      ]),
      const SizedBox(height: 8),
      Wrap(spacing: 10, runSpacing: 10, children: [
        PillButton(text: _checking ? '確認中…' : '更新を確認', icon: Icons.refresh, onTap: _checking ? null : _check),
        PillButton(
          text: '更新する',
          icon: Icons.system_update_alt,
          primary: hasNew,
          onTap: () async {
            final how = await Series.requestUpdate().catchError((_) => '');
            if (context.mounted && how == 'browser') hudToast(context, 'Theta Home Hatch が無いので、Releases ページを開きました');
          },
        ),
      ]),
    ]);
  }
}
