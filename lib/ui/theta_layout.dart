import 'package:flutter/material.dart';

import '../app.dart';
import 'hud/hud_theme.dart';
import 'hud/hud_widgets.dart';
import 'menus.dart';
import 'screens.dart';
import 'visualizer_view.dart';

/// Theta スキンの配置（iPod の操作を HUD の見た目で）。
/// 横向き：左にタブ付きのリスト、右に再生中の曲とクリックホイール。縦向き：上にリスト、下に曲とホイール。

class ThetaTab {
  final String label;
  final IconData icon;
  final int group; // 0 よく使う（accent）・1 ライブラリ（widget）・2 管理（launch）
  final IPodScreen Function() root;
  const ThetaTab(this.label, this.icon, this.group, this.root);
}

/// ライブラリが空のときは、どのタブも「更新・接続設定」の案内（musicMenu）にする
IPodScreen _lib(IPodScreen Function() f) => services.library.tracks.isEmpty ? musicMenu() : f();

final thetaTabs = <ThetaTab>[
  ThetaTab('ARTISTS', Icons.person_outline, 1, () => _lib(artistsMenu)),
  ThetaTab('ALBUMS', Icons.album_outlined, 1, () => _lib(() => albumsMenu(services.library.albums, 'Albums'))),
  ThetaTab('SONGS', Icons.music_note_outlined, 1, () => _lib(() => songsMenu(services.library.songs, 'Songs'))),
  ThetaTab('GENRES', Icons.category_outlined, 1, () => _lib(genresMenu)),
  ThetaTab('FOLDERS', Icons.folder_outlined, 1, () => _lib(() => folderMenu(services.library.root))),
  ThetaTab('FAVS', Icons.star_border, 0, favoritesMenu),
  ThetaTab('SEARCH', Icons.search, 0, searchStartMenu),
  ThetaTab('LIBRARY', Icons.library_music_outlined, 2, libraryMenu),
  ThetaTab('SETUP', Icons.tune, 2, settingsMenu),
];

/// リストの左に付く縦のタブ（ThetaHomeHatch の端のタブと同じ作り。低いときは印だけ）
class ThetaTabs extends StatelessWidget {
  final int active;
  final void Function(int) onSelect;
  const ThetaTabs({super.key, required this.active, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final p = HudScope.of(context);
    return SizedBox(
      width: 40,
      child: Column(
        children: [
          for (var i = 0; i < thetaTabs.length; i++) ...[
            if (i > 0) SizedBox(height: thetaTabs[i].group != thetaTabs[i - 1].group ? 10 : 4),
            Expanded(child: _tab(p, i)),
          ],
        ],
      ),
    );
  }

  Widget _tab(Palette p, int i) {
    final t = thetaTabs[i];
    final on = i == active;
    final g = p.group(t.group);
    final bg = on ? (p.pop ? g : p.accent) : (p.pop ? p.panel : p.bg);
    final fg = on ? (p.pop && t.group != 0 ? p.fg : p.onAccent) : p.fg;
    final shape = p.rounded ? const BorderRadius.horizontal(left: Radius.circular(8)) : null;
    return Semantics(
      button: true,
      selected: on,
      label: t.label,
      child: GestureDetector(
        onTap: () => onSelect(i),
        child: Container(
          decoration: BoxDecoration(
            color: bg,
            border: Border.all(color: on && !p.pop ? p.accent : p.line, width: p.lineWidth),
            borderRadius: shape,
          ),
          child: Stack(
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: Container(width: 3, height: 18, color: on ? fg : g),
              ),
              LayoutBuilder(
                builder: (context, c) => Center(
                  child: c.maxHeight < 64
                      ? Icon(t.icon, size: 19, color: fg)
                      : FittedBox(
                          fit: BoxFit.scaleDown,
                          child: RotatedBox(
                            quarterTurns: 3,
                            child: Text(
                              t.label,
                              style: TextStyle(fontSize: 12, letterSpacing: 1.5, fontFamily: p.mono, color: fg),
                            ),
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _fmt(Duration d) {
  final s = d.inSeconds;
  final m = s ~/ 60;
  return '$m:${(s % 60).toString().padLeft(2, '0')}';
}

/// 再生中の曲（右の上・縦向きでは下）。押すとキューを開く
class ThetaNowPanel extends StatelessWidget {
  final bool large; // 横向き：ジャケットを大きく
  final VoidCallback onOpen;
  const ThetaNowPanel({super.key, required this.large, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final p = HudScope.of(context);
    final pl = services.player;
    final t = pl.current;
    final fav = t != null && services.favorites.isTrack(t);
    final title = Text(
      t?.title ?? '再生していません',
      maxLines: large ? 2 : 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: p.fg,
        fontSize: large ? 22 : 17,
        height: 1.2,
        fontFamily: p.display,
        fontWeight: p.pop ? FontWeight.bold : FontWeight.w400,
      ),
    );
    final sub = t == null
        ? Text('リストから曲を選んでください', style: TextStyle(color: p.faint, fontSize: 12))
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                t.displayArtist,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: p.muted, fontSize: 13, fontFamily: p.mono),
              ),
              Text(
                '${t.displayAlbum}${t.year != 0 ? '  ·  ${t.year}' : ''}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: p.accent, fontSize: 13, fontFamily: p.mono),
              ),
            ],
          );
    final progress = StreamBuilder<Duration>(
      stream: pl.audio.positionStream,
      builder: (context, snap) {
        final pos = snap.data ?? Duration.zero;
        final dur = pl.audio.duration ?? Duration.zero;
        final v = dur.inMilliseconds == 0 ? 0.0 : pos.inMilliseconds / dur.inMilliseconds;
        final remain = dur - pos;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            HudProgress(v),
            const SizedBox(height: 2),
            Row(
              children: [
                Text(
                  _fmt(pos),
                  style: TextStyle(color: p.faint, fontSize: 11, fontFamily: p.mono),
                ),
                const Spacer(),
                Text(
                  '-${_fmt(remain.isNegative ? Duration.zero : remain)}',
                  style: TextStyle(color: p.faint, fontSize: 11, fontFamily: p.mono),
                ),
              ],
            ),
          ],
        );
      },
    );
    final badges = Row(
      children: [
        Icon(pl.playing ? Icons.play_arrow : Icons.pause, size: 16, color: p.accent),
        const SizedBox(width: 6),
        Text(
          t == null ? '--' : '${pl.index + 1} / ${pl.queue.length}',
          style: TextStyle(color: p.muted, fontSize: 11, fontFamily: p.mono, letterSpacing: 1),
        ),
        const Spacer(),
        if (services.settings.shuffle) Icon(Icons.shuffle, size: 15, color: p.muted),
        if (services.settings.repeat.index != 0) ...[
          const SizedBox(width: 4),
          Icon(services.settings.repeat.index == 1 ? Icons.repeat_one : Icons.repeat, size: 15, color: p.muted),
        ],
        if (fav) ...[const SizedBox(width: 4), Icon(Icons.star, size: 15, color: p.accent)],
      ],
    );

    final body = large
        ? LayoutBuilder(
            builder: (context, c) {
              final art = (c.maxHeight - 150).clamp(60.0, c.maxWidth);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  badges,
                  const SizedBox(height: 6),
                  Center(
                    child: SizedBox(
                      width: art,
                      height: art,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          HudArt(t?.art, size: art),
                          // ジャケットに重ねるビジュアライザー（設定 → Visualizer）
                          Padding(
                            padding: const EdgeInsets.all(2),
                            child: VisualizerView(color: p.accent, peak: p.fg),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  title,
                  sub,
                  const Spacer(),
                  progress,
                ],
              );
            },
          )
        : Stack(
            children: [
              // 縦向き：曲の情報の後ろにうっすら
              Positioned.fill(
                child: Opacity(
                  opacity: 0.35,
                  child: VisualizerView(color: p.accent, peak: p.fg),
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      HudArt(t?.art, size: 54),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [title, sub]),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  badges,
                  const SizedBox(height: 4),
                  progress,
                ],
              ),
            ],
          );
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: t == null ? null : onOpen,
      child: HudPanel(
        code: 'NOW',
        title: '再生中',
        expand: large,
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: body,
      ),
    );
  }
}
