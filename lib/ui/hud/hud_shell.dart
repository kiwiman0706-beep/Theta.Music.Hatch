import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app.dart';
import '../../core/models.dart';
import '../screens.dart' show ArtImage;
import 'hud_pages.dart';
import 'hud_theme.dart';
import 'hud_widgets.dart';

/// HUD スキンの画面遷移（ページの中から使う）
abstract class HudNav {
  void open(Widget page);
  void back();
  void selectTab(int i);
}

late HudNav hudNav;

class _TabDef {
  final String label;
  final int group;
  const _TabDef(this.label, this.group);
}

const _tabs = [
  _TabDef('NOW', 0),
  _TabDef('FAVS', 0),
  _TabDef('ARTISTS', 1),
  _TabDef('ALBUMS', 1),
  _TabDef('SONGS', 1),
  _TabDef('GENRES', 1),
  _TabDef('FOLDERS', 1),
  _TabDef('LIBRARY', 2),
];
const nowTab = 0, favTab = 1, libraryTab = 7, setupTab = 8;

/// ThetaHomeHatch 風の画面：左に中身、右端に縦書きのタブ（ThetaHomeHatch の閉じた画面と同じ構成）
class HudShell extends StatefulWidget {
  const HudShell({super.key});
  @override
  State<HudShell> createState() => _HudShellState();
}

class _HudShellState extends State<HudShell> implements HudNav {
  int _tab = 0;
  final List<Widget> _stack = [];

  @override
  void initState() {
    super.initState();
    hudNav = this;
    if (!services.settings.configured) _tab = setupTab;
  }

  @override
  void open(Widget page) => setState(() => _stack.add(page));

  @override
  void back() {
    if (_stack.isNotEmpty) setState(() => _stack.removeLast());
  }

  @override
  void selectTab(int i) => setState(() {
        _tab = i;
        _stack.clear();
      });

  Widget _root() => switch (_tab) {
        nowTab => const NowPage(),
        favTab => const FavsPage(),
        2 => const ArtistsPage(),
        3 => AlbumsPage(albums: services.library.albums),
        4 => SongsPage(tracks: services.library.songs),
        5 => const GenresPage(),
        6 => FolderPage(dir: services.library.root),
        libraryTab => const LibraryPage(),
        _ => const SettingsPage(),
      };

  @override
  Widget build(BuildContext context) {
    final p = paletteFor(services.settings.hudTheme, MediaQuery.platformBrightnessOf(context));
    return HudScope(
      palette: p,
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: p.isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
        child: PopScope(
          canPop: _stack.isEmpty && _tab == 0,
          onPopInvokedWithResult: (didPop, _) {
            if (didPop) return;
            if (_stack.isNotEmpty) {
              back();
            } else {
              selectTab(0);
            }
          },
          child: Scaffold(
            backgroundColor: p.bg,
            body: CustomPaint(
              painter: BackdropPainter(p),
              child: SafeArea(
                child: ListenableBuilder(
                  listenable: Listenable.merge([services.library, services.player, services.settings, services.favorites]),
                  builder: (context, _) => Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Expanded(
                      child: Column(children: [
                        Expanded(
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 160),
                            child: KeyedSubtree(
                              key: ValueKey('$_tab/${_stack.length}'),
                              child: _stack.isEmpty ? _root() : _stack.last,
                            ),
                          ),
                        ),
                        if (_tab != 0 && services.player.hasQueue) const _MiniPlayer(),
                      ]),
                    ),
                    _Rail(active: _tab, onSelect: selectTab),
                  ]),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Rail extends StatelessWidget {
  final int active;
  final void Function(int) onSelect;
  const _Rail({required this.active, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final p = HudScope.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 10, 0, 10),
      child: SizedBox(
        width: 42,
        child: Column(children: [
          for (var i = 0; i < _tabs.length; i++) ...[
            if (i > 0) SizedBox(height: _tabs[i].group != _tabs[i - 1].group ? 14 : 6),
            Expanded(child: _RailTab(index: i, def: _tabs[i], active: active == i, onTap: () => onSelect(i))),
          ],
          const SizedBox(height: 14),
          // ThetaHomeHatch の「ALL」の位置に設定
          GestureDetector(
            onTap: () => onSelect(setupTab),
            child: Container(
              height: 62,
              decoration: BoxDecoration(
                color: active == setupTab ? p.accent : (p.pop ? p.panel : p.bg),
                border: Border.all(color: p.accent, width: p.pop ? 1.5 : 1.5),
                borderRadius: p.pop ? const BorderRadius.horizontal(left: Radius.circular(8)) : null,
              ),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.tune, size: 20, color: active == setupTab ? p.onAccent : p.accent),
                const SizedBox(height: 4),
                Text('SETUP',
                    style: TextStyle(
                        fontSize: 9,
                        letterSpacing: 1,
                        fontFamily: p.mono,
                        color: active == setupTab ? p.onAccent : p.accent)),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}

class _RailTab extends StatelessWidget {
  final int index;
  final _TabDef def;
  final bool active;
  final VoidCallback onTap;
  const _RailTab({required this.index, required this.def, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = HudScope.of(context);
    final groupColor = p.group(def.group);
    final activeBg = p.pop ? groupColor : p.accent;
    final onActive = p.pop && def.group != 0 ? p.fg : p.onAccent;
    return Semantics(
      selected: active,
      button: true,
      label: def.label,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            color: active ? activeBg : (p.pop ? p.panel : p.bg),
            border: Border.all(color: active && !p.pop ? p.accent : p.line, width: p.lineWidth),
            borderRadius: p.pop ? const BorderRadius.horizontal(left: Radius.circular(8)) : null,
          ),
          child: Stack(children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Container(width: 3, height: 20, color: active ? onActive : groupColor),
            ),
            Column(children: [
              const SizedBox(height: 7),
              Text((index + 1).toString().padLeft(2, '0'),
                  style: TextStyle(fontSize: 10, color: active ? onActive : p.faint, fontFamily: p.mono)),
              Expanded(
                child: Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: RotatedBox(
                      quarterTurns: 1,
                      child: Text(def.label,
                          style: TextStyle(
                              fontSize: 13,
                              letterSpacing: 1.5,
                              fontFamily: p.mono,
                              color: active ? onActive : p.fg)),
                    ),
                  ),
                ),
              ),
            ]),
          ]),
        ),
      ),
    );
  }
}

/// ほかのタブにいるときの下の再生バー
class _MiniPlayer extends StatelessWidget {
  const _MiniPlayer();

  @override
  Widget build(BuildContext context) {
    final p = HudScope.of(context);
    final pl = services.player;
    final t = pl.current;
    if (t == null) return const SizedBox.shrink();
    return Container(
      decoration: BoxDecoration(
        color: p.panel,
        border: Border(top: BorderSide(color: p.line, width: p.lineWidth)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        StreamBuilder<Duration>(
          stream: pl.audio.positionStream,
          builder: (context, snap) {
            final dur = pl.audio.duration?.inMilliseconds ?? 0;
            final v = dur == 0 ? 0.0 : (snap.data?.inMilliseconds ?? 0) / dur;
            return Align(
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: v.clamp(0.0, 1.0),
                child: Container(height: 2, color: p.accent),
              ),
            );
          },
        ),
        InkWell(
          onTap: () => hudNav.selectTab(0),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 6, 4, 6),
            child: Row(children: [
              HudArt(t.art, size: 42),
              const SizedBox(width: 10),
              Expanded(child: TwoLines(t.title, '${t.displayArtist} · ${t.displayAlbum}')),
              IconButton(
                onPressed: pl.toggle,
                icon: Icon(pl.playing ? Icons.pause : Icons.play_arrow, color: p.accent),
              ),
              IconButton(onPressed: pl.next, icon: Icon(Icons.skip_next, color: p.fg)),
            ]),
          ),
        ),
      ]),
    );
  }
}

/// かぎ括弧付きのアルバムアート
class HudArt extends StatelessWidget {
  final ArtRef? art;
  final double? size;
  const HudArt(this.art, {super.key, this.size});

  @override
  Widget build(BuildContext context) {
    final p = HudScope.of(context);
    final ph = Container(
      color: p.raised,
      alignment: Alignment.center,
      child: LayoutBuilder(
        builder: (context, c) => Icon(Icons.album_outlined, color: p.faint, size: (c.maxWidth * 0.4).clamp(14, 64)),
      ),
    );
    Widget img = ArtImage(art, key: ValueKey(art?.key), placeholder: ph);
    img = Container(
      decoration: BoxDecoration(
        border: Border.all(color: p.line, width: p.lineWidth),
        borderRadius: BorderRadius.circular(p.pop ? 8 : 0),
      ),
      clipBehavior: p.pop ? Clip.antiAlias : Clip.none,
      child: img,
    );
    if (!p.pop) {
      img = CustomPaint(foregroundPainter: CornersPainter(p.accent, length: size != null && size! < 60 ? 5 : 9), child: img);
    }
    if (size != null) return SizedBox(width: size, height: size, child: img);
    return AspectRatio(aspectRatio: 1, child: img);
  }
}
