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
  final String title; // モードの一覧での名前
  final IconData icon;
  final int group; // 0 よく使う（accent）・1 ライブラリ（widget）・2 管理（launch）
  final IPodScreen Function() root;
  const ThetaTab(this.label, this.title, this.icon, this.group, this.root);
}

/// ライブラリが空のときは、どのタブも「更新・接続設定」の案内（musicMenu）にする
IPodScreen _lib(IPodScreen Function() f) => services.library.tracks.isEmpty ? musicMenu() : f();

/// モード（iPod の Music メニューと同じ並び。いちばん上はお気に入り）
final thetaTabs = <ThetaTab>[
  ThetaTab('FAVS', 'Favorites', Icons.star_border, 0, favoritesMenu),
  ThetaTab('ARTISTS', 'Artists', Icons.person_outline, 1, () => _lib(artistsMenu)),
  ThetaTab('ALBUMS', 'Albums', Icons.album_outlined, 1,
      () => _lib(() => albumsMenu(services.library.albums, 'Albums', pinFavorites: true))),
  ThetaTab('SONGS', 'Songs', Icons.music_note_outlined, 1,
      () => _lib(() => songsMenu(services.library.songs, 'Songs', pinFavorites: true))),
  ThetaTab('GENRES', 'Genres', Icons.category_outlined, 1, () => _lib(genresMenu)),
  ThetaTab('FOLDERS', 'Folders', Icons.folder_outlined, 1, () => _lib(() => folderMenu(services.library.root))),
  ThetaTab('SEARCH', 'Search', Icons.search, 0, searchStartMenu),
  ThetaTab('LIBRARY', 'Library', Icons.library_music_outlined, 2, libraryMenu),
  ThetaTab('SETUP', 'Settings', Icons.tune, 2, settingsMenu),
];

/// いちばん上の階層：モードの切り替え（アーティストなどの一覧で MENU を押すとここへ戻る）
MenuScreen modeMenu(void Function(int) open) => MenuScreen(
      'Music',
      () => [
        for (var i = 0; i < thetaTabs.length; i++)
          MenuItem(thetaTabs[i].title, chevron: true, starred: i == 0, onSelect: () => open(i)),
        MenuItem('Shuffle Songs', onSelect: () {
          final s = services.library.songs;
          if (s.isNotEmpty) {
            services.player.playList(s, 0, shuffle: true);
            nav.showNowPlaying();
          }
        }),
      ],
    );

/// リストの左に付く縦のタブ（ThetaHomeHatch の端のタブと同じ作り。低いときは印だけ）
/// いちばん上の階層で広げたときは、タブだけで画面の左側いっぱいを使い、モードの一覧の代わりになる
class ThetaTabs extends StatelessWidget {
  final int active;
  final void Function(int) onSelect;

  /// 幅。40 は印だけ、90 以上で印と文字を横に並べる
  final double width;

  /// タブの下に足す行（いちばん上の階層で広げたときの Shuffle Songs など）。番号はタブの続き
  final List<(String, IconData, VoidCallback)> extra;
  const ThetaTabs(
      {super.key, required this.active, required this.onSelect, this.width = 40, this.extra = const []});

  @override
  Widget build(BuildContext context) {
    final p = HudScope.of(context);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      width: width,
      child: Column(
        children: [
          for (var i = 0; i < thetaTabs.length; i++) ...[
            if (i > 0) SizedBox(height: thetaTabs[i].group != thetaTabs[i - 1].group ? 10 : 4),
            Expanded(child: _tab(p, i)),
          ],
          for (var j = 0; j < extra.length; j++) ...[
            const SizedBox(height: 10),
            Expanded(child: _row(p, thetaTabs.length + j, extra[j].$1, extra[j].$2, extra[j].$3, 0)),
          ],
        ],
      ),
    );
  }

  Widget _tab(Palette p, int i) {
    final t = thetaTabs[i];
    return _row(p, i, t.label, t.icon, () => onSelect(i), t.group);
  }

  Widget _row(Palette p, int i, String label, IconData icon, VoidCallback onTap, int group) {
    final t = (label: label, icon: icon, group: group);
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
        onTap: onTap,
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
                  child: c.maxWidth >= 90
                      ? Padding(
                          padding: EdgeInsets.only(left: c.maxWidth >= 200 ? 16 : 8, right: 8),
                          child: Row(children: [
                            Icon(t.icon, size: c.maxWidth >= 200 ? 22 : 18, color: fg),
                            SizedBox(width: c.maxWidth >= 200 ? 12 : 6),
                            Expanded(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: Text(t.label,
                                    maxLines: 1,
                                    style: TextStyle(
                                        fontSize: c.maxWidth >= 200 ? 16 : 12,
                                        letterSpacing: 1.2,
                                        fontFamily: p.mono,
                                        color: fg)),
                              ),
                            ),
                          ]),
                        )
                      : c.maxWidth < 30 || c.maxHeight < 64
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

/// 再生中のパネルのホイールの役目（iPod の Now Playing と同じ）：
/// progress＝ふだん（回すと音量）、volume＝音量を変えている、scrub＝曲の中を移動（中央ボタンで切り替え）
enum NowMode { progress, volume, scrub }

/// 再生中の曲（横向きは右の上、縦向きは下）。ジャケットをパネルいっぱいの背景にして、
/// 曲名・進み具合を重ね、下の方にビジュアライザー。押すとフォーカスがここに来る、長押しでキュー
class ThetaNowPanel extends StatelessWidget {
  final bool large; // 横向き：高さいっぱい
  final bool focused; // ホイールがこのパネルを操作している
  final NowMode mode;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  const ThetaNowPanel({
    super.key,
    required this.large,
    required this.focused,
    required this.mode,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final p = HudScope.of(context);
    final pl = services.player;
    final t = pl.current;
    final fav = t != null && services.favorites.isTrack(t);
    final radius = p.rounded ? BorderRadius.circular(p.radius) : BorderRadius.zero;
    final vis = large ? 56.0 : 26.0; // ビジュアライザーの帯の高さ

    final title = Text(t?.title ?? '再生していません',
        maxLines: large ? 2 : 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
            color: p.fg,
            fontSize: large ? 26 : 18,
            height: 1.15,
            fontFamily: p.display,
            fontWeight: p.pop ? FontWeight.bold : FontWeight.w400,
            shadows: [Shadow(color: p.bg, blurRadius: 6)]));
    final sub = t == null
        ? Text('リストから曲を選んでください', style: TextStyle(color: p.muted, fontSize: 12))
        : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(t.displayArtist,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: p.fg, fontSize: 13, fontFamily: p.mono, shadows: [Shadow(color: p.bg, blurRadius: 4)])),
            Text('${t.displayAlbum}${t.year != 0 ? '  ·  ${t.year}' : ''}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: p.accent, fontSize: 13, fontFamily: p.mono, shadows: [Shadow(color: p.bg, blurRadius: 4)])),
          ]);

    // 下の帯：ふだんは進み具合、回すと音量、中央ボタンでシーク
    final bottom = StreamBuilder<Duration>(
      stream: pl.audio.positionStream,
      builder: (context, snap) {
        final pos = snap.data ?? Duration.zero;
        final dur = pl.audio.duration ?? Duration.zero;
        final v = dur.inMilliseconds == 0 ? 0.0 : pos.inMilliseconds / dur.inMilliseconds;
        final remain = dur - pos;
        final label = TextStyle(color: p.muted, fontSize: 11, fontFamily: p.mono, letterSpacing: 1);
        if (mode == NowMode.volume) {
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Icon(Icons.volume_down, size: 16, color: p.accent),
              const SizedBox(width: 6),
              Expanded(child: HudProgress(pl.volume)),
              const SizedBox(width: 6),
              Icon(Icons.volume_up, size: 16, color: p.accent),
            ]),
            const SizedBox(height: 2),
            Text('VOLUME ${(pl.volume * 100).round()}', style: label),
          ]);
        }
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          HudProgress(v),
          const SizedBox(height: 2),
          Row(children: [
            Text(_fmt(pos), style: label),
            const Spacer(),
            if (mode == NowMode.scrub)
              Text('◀ SEEK ▶', style: label.copyWith(color: p.accent))
            else if (focused && !services.settings.wheelGuide)
              Text('回す 音量 ・ 中央 シーク ・ MENU リスト', style: label.copyWith(letterSpacing: 0, fontSize: 10)),
            const Spacer(),
            Text('-${_fmt(remain.isNegative ? Duration.zero : remain)}', style: label),
          ]),
        ]);
      },
    );

    final head = Row(children: [
      Text('[ NOW ]', style: TextStyle(color: p.accent, fontSize: 11, letterSpacing: 2, fontFamily: p.mono)),
      const SizedBox(width: 8),
      Icon(pl.playing ? Icons.play_arrow : Icons.pause, size: 15, color: p.accent),
      const SizedBox(width: 4),
      Text(t == null ? '--' : '${pl.index + 1} / ${pl.queue.length}',
          style: TextStyle(color: p.fg, fontSize: 11, fontFamily: p.mono, letterSpacing: 1)),
      const Spacer(),
      if (services.settings.shuffle) Icon(Icons.shuffle, size: 15, color: p.fg),
      if (services.settings.repeat.index != 0) ...[
        const SizedBox(width: 4),
        Icon(services.settings.repeat.index == 1 ? Icons.repeat_one : Icons.repeat, size: 15, color: p.fg),
      ],
      if (fav) ...[const SizedBox(width: 4), Icon(Icons.star, size: 15, color: p.accent)],
    ]);

    final panel = ClipRRect(
      borderRadius: radius,
      child: Stack(fit: StackFit.expand, children: [
        // ジャケットを背景いっぱいに
        if (t?.art != null)
          ArtImage(t!.art, key: ValueKey(t.art!.key), fit: BoxFit.cover, placeholder: ColoredBox(color: p.raised))
        else
          ColoredBox(
              color: p.raised,
              child: Align(
                  alignment: const Alignment(0.85, -0.55),
                  child: Icon(Icons.album_outlined, size: large ? 96 : 48, color: p.faint))),
        // 文字が読めるように、上と下をスキンの地の色で暗く（明るく）する
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [p.bg.withValues(alpha: 0.7), p.bg.withValues(alpha: 0.05), p.bg.withValues(alpha: 0.5), p.bg.withValues(alpha: 0.95)],
              stops: const [0, 0.3, 0.6, 1],
            ),
          ),
        ),
        // ビジュアライザーは曲名と進み具合の間の帯に、アクセントとして
        Positioned(
          left: 12,
          right: 12,
          bottom: 44,
          height: vis,
          child: Opacity(opacity: 0.9, child: VisualizerView(color: p.accent, peak: p.fg)),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            head,
            const Spacer(),
            title,
            const SizedBox(height: 2),
            sub,
            SizedBox(height: services.settings.visualizer == 'off' ? 8 : vis + 4),
            bottom,
          ]),
        ),
      ]),
    );

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      onLongPress: t == null ? null : onLongPress,
      child: SizedBox(
        height: large ? null : (services.settings.visualizer == 'off' ? 150 : 176),
        child: CustomPaint(
          foregroundPainter: p.rounded ? null : CornersPainter(focused ? p.accent : p.line),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: radius,
              // フォーカスがあるときは枠をアクセント色で太く
              border: Border.all(color: focused ? p.accent : p.line, width: focused ? 2 : p.lineWidth),
            ),
            padding: EdgeInsets.all(focused ? 0 : 1),
            child: panel,
          ),
        ),
      ),
    );
  }
}
