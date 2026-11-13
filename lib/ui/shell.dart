import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app.dart';
import '../core/clicker.dart';
import 'click_wheel.dart';
import 'dialogs.dart';
import 'hud/hud_theme.dart';
import 'hud/hud_widgets.dart';
import 'ipod_theme.dart';
import 'menus.dart';
import 'now_playing.dart';
import 'screens.dart';
import 'theta_layout.dart';

/// 本体: 上に液晶、下にクリックホイール。
/// theta のときは同じ操作（画面の重ね方・ホイール）を、シリーズのスキン（HUD）の見た目と配置で描く
class IPodShell extends StatefulWidget {
  final bool theta;
  const IPodShell({super.key, this.theta = false});
  @override
  State<IPodShell> createState() => _IPodShellState();
}

class _IPodShellState extends State<IPodShell> implements Nav {
  final List<IPodScreen> _stack = [];
  bool _forward = true;
  Timer? _seekTimer;

  @override
  void initState() {
    super.initState();
    nav = this;
    if (widget.theta) {
      _tab = services.settings.configured ? 0 : thetaTabs.length - 1; // 未設定なら SETUP
      _pushInternal(thetaTabs[_tab].root());
    } else {
      _pushInternal(mainMenu());
    }
    services.settings.addListener(_onChange);
    services.player.addListener(_onChange);
    services.favorites.addListener(_onFavorites);
    Clicker.prepare();
    if (!services.settings.configured) {
      WidgetsBinding.instance.addPostFrameCallback((_) => showServerDialog(context));
    }
  }

  void _onChange() => setState(() {});

  /// DS audio の★評価を保存できなかったとき
  void _onFavorites() {
    final e = services.favorites.syncError;
    if (e == null) return;
    services.favorites.syncError = null;
    toast(e);
  }

  IPodScreen get _top => _stack.last;

  void _pushInternal(IPodScreen s) {
    if (_stack.isNotEmpty) {
      _stack.last.removeListener(_onChange);
      _stack.last.detach();
    }
    _stack.add(s);
    s.attach();
    s.addListener(_onChange);
  }

  @override
  void push(IPodScreen s) {
    setState(() {
      _forward = true;
      _pushInternal(s);
    });
  }

  @override
  void pop() {
    if (_stack.length <= 1) return;
    setState(() {
      _forward = false;
      final s = _stack.removeLast();
      s.removeListener(_onChange);
      s.detach();
      // アニメーション終了後に破棄
      Future<void>.delayed(const Duration(milliseconds: 400), s.dispose);
      _top.attach();
      _top.addListener(_onChange);
    });
  }

  @override
  void showNowPlaying() {
    // Theta：iPod が Now Playing に移るのと同じく、ホイールのフォーカスを再生中のパネルへ（リストはそのまま）
    if (widget.theta) {
      _setFocusNow(true);
      return;
    }
    if (_top is NowPlayingScreen) return;
    push(NowPlayingScreen());
  }

  int _tab = 0;

  /// Theta：左のタブ。そのタブの最初の画面からやり直す
  void _selectTab(int i) {
    _focusNow = false;
    setState(() {
      _forward = i >= _tab;
      _tab = i;
      for (final s in _stack) {
        s.removeListener(_onChange);
        s.detach();
        Future<void>.delayed(const Duration(milliseconds: 400), s.dispose);
      }
      _stack.clear();
      _pushInternal(thetaTabs[i].root());
    });
  }

  /// Theta：再生中の曲を押したらキュー（前の曲も含めて全部）
  void _openQueue() {
    _setFocusNow(false);
    if (_top.title == 'Now Playing') return;
    push(queueMenu());
  }

  // ---------------------------------------------------------------- Theta のフォーカス（iPod に忠実に）
  // リストにフォーカス：回す＝選ぶ、中央＝決定、MENU＝戻る（いちばん上の画面なら再生中へ）
  // 再生中にフォーカス：回す＝音量（中央でシークに切り替え）、中央長押し＝お気に入り、MENU＝リストへ

  bool _focusNow = false;
  NowMode _nowMode = NowMode.progress;
  Timer? _modeTimer;

  void _setFocusNow(bool on) {
    if (_focusNow == on && _nowMode == NowMode.progress) return;
    _modeTimer?.cancel();
    setState(() {
      _focusNow = on;
      _nowMode = NowMode.progress;
    });
  }

  /// 音量・シークの表示は、しばらく触らなければふだんの表示に戻す（iPod と同じ）
  void _setNowMode(NowMode m) {
    _modeTimer?.cancel();
    setState(() => _nowMode = m);
    if (m != NowMode.progress) {
      _modeTimer = Timer(Duration(seconds: m == NowMode.scrub ? 5 : 2), () {
        if (mounted) setState(() => _nowMode = NowMode.progress);
      });
    }
  }

  bool get _nowFocused => widget.theta && _focusNow && services.player.hasQueue;

  String? _toast;
  Timer? _toastTimer;

  @override
  void toast(String message) {
    _toastTimer?.cancel();
    setState(() => _toast = message);
    _toastTimer = Timer(const Duration(milliseconds: 1600), () {
      if (mounted) setState(() => _toast = null);
    });
  }

  /// ホイールを回したとき：カリカリ音と振動（それぞれ設定でオン・オフ）
  void _click() {
    if (services.settings.haptics) HapticFeedback.selectionClick();
    if (services.settings.clicker) Clicker.click();
  }

  void _onTick(int dir) {
    _click();
    if (_nowFocused) {
      if (_nowMode == NowMode.scrub) {
        services.player.seekBy(Duration(seconds: 4 * dir));
        _setNowMode(NowMode.scrub);
      } else {
        services.player.changeVolume(dir * 0.04);
        _setNowMode(NowMode.volume);
      }
      return;
    }
    _top.onScroll(dir);
  }

  void _onButton(WheelButton b) {
    if (services.settings.haptics) HapticFeedback.lightImpact();
    if (services.settings.clicker) Clicker.click(volume: 0.8);
    switch (b) {
      case WheelButton.menu:
        if (_nowFocused) {
          _setFocusNow(false); // 再生中 → リストへ
        } else if (_stack.length > 1) {
          pop();
        } else if (widget.theta && services.player.hasQueue) {
          _setFocusNow(true); // リストのいちばん上 → 再生中へ（iPod の Now Playing と同じ）
        }
      case WheelButton.select:
        if (_nowFocused) {
          _setNowMode(_nowMode == NowMode.scrub ? NowMode.progress : NowMode.scrub);
        } else {
          _top.onSelect();
        }
      case WheelButton.playPause:
        services.player.toggle();
      case WheelButton.next:
        services.player.next();
      case WheelButton.previous:
        services.player.previous();
    }
  }

  void _holdStart(WheelButton b) {
    if (b == WheelButton.select || b == WheelButton.menu) {
      if (services.settings.haptics) HapticFeedback.heavyImpact();
      if (b == WheelButton.select) {
        final t = services.player.current;
        if (_nowFocused && t != null) {
          toast(services.favorites.toggleTrack(t) ? '★ お気に入りに追加' : 'お気に入りから外しました');
        } else {
          _top.onLongSelect();
        }
      } else {
        voiceSearch(); // MENU 長押しで音声検索
      }
      return;
    }
    final d = b == WheelButton.next ? 1 : -1;
    _seekTimer?.cancel();
    var n = 0;
    _seekTimer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      n++;
      services.player.seekBy(Duration(seconds: d * (n > 12 ? 15 : 5)));
    });
  }

  void _holdEnd(WheelButton b) => _seekTimer?.cancel();

  @override
  void dispose() {
    _seekTimer?.cancel();
    _toastTimer?.cancel();
    _modeTimer?.cancel();
    services.favorites.removeListener(_onFavorites);
    services.settings.removeListener(_onChange);
    services.player.removeListener(_onChange);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.theta) return _thetaBuild(context);
    final colors = services.settings.blackBody ? IPodColors.black : IPodColors.silver;
    return PopScope(
      canPop: _stack.length <= 1,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) pop();
      },
      child: Scaffold(
        body: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [colors.bodyTop, colors.bodyBottom],
            ),
          ),
          child: SafeArea(
            child: LayoutBuilder(builder: (context, c) {
              final screenH = min(c.maxWidth * 0.82, c.maxHeight * 0.48);
              final wheel = min(c.maxWidth * 0.80, (c.maxHeight - screenH - 32) * 0.92);
              return Column(children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 18, 18, 0),
                  child: SizedBox(height: screenH, child: _withToast(_lcd(colors))),
                ),
                Expanded(
                  child: Center(
                    child: ClickWheel(
                      size: wheel,
                      colors: colors,
                      onTick: _onTick,
                      onButton: _onButton,
                      onHoldStart: _holdStart,
                      onHoldEnd: _holdEnd,
                    ),
                  ),
                ),
              ]);
            }),
          ),
        ),
      ),
    );
  }

  Widget _lcd(IPodColors colors) {
    final top = _top;
    return Container(
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 3, offset: const Offset(0, 1))],
      ),
      padding: const EdgeInsets.all(3),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(7),
        child: ColoredBox(
          color: LcdColors.bg,
          child: Column(children: [
            _header(top.title),
            Expanded(
              child: ClipRect(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  switchInCurve: Curves.easeOut,
                  switchOutCurve: Curves.easeIn,
                  layoutBuilder: (cur, prev) => Stack(children: [...prev, ?cur]),
                  transitionBuilder: (child, anim) {
                    final incoming = child.key == top.key;
                    final begin = incoming ? Offset(_forward ? 1 : -1, 0) : Offset(_forward ? -1 : 1, 0);
                    return SlideTransition(
                      position: Tween(begin: begin, end: Offset.zero).animate(anim),
                      child: child,
                    );
                  },
                  child: KeyedSubtree(
                    key: top.key,
                    child: ListenableBuilder(listenable: top, builder: (context, _) => top.build(context)),
                  ),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- Theta

  Widget _thetaBuild(BuildContext context) {
    final p = paletteFor(services.settings.hudTheme, MediaQuery.platformBrightnessOf(context));
    // ホイールもスキンの色で
    final wheelColors = IPodColors(
      bodyTop: p.bg,
      bodyBottom: p.bg,
      wheel: p.raised,
      wheelEdge: p.line,
      wheelLabel: p.muted,
      center: p.panel,
      centerEdge: p.accent,
    );
    Widget wheel(double size) => ClickWheel(
          size: size,
          colors: wheelColors,
          onTick: _onTick,
          onButton: _onButton,
          onHoldStart: _holdStart,
          onHoldEnd: _holdEnd,
        );
    return HudScope(
      palette: p,
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: p.isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
        child: PopScope(
          canPop: _stack.length <= 1,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) pop();
          },
          child: Scaffold(
            backgroundColor: p.bg,
            body: CustomPaint(
              painter: BackdropPainter(p),
              child: SafeArea(
                child: LayoutBuilder(builder: (context, c) {
                  final list = _thetaList(p);
                  Widget nowPanel(bool large) => ThetaNowPanel(
                        large: large,
                        focused: _nowFocused,
                        mode: _nowMode,
                        onTap: () => _setFocusNow(true),
                        onLongPress: _openQueue,
                      );
                  final now = nowPanel(false);
                  if (c.maxWidth > c.maxHeight && c.maxWidth >= 600) {
                    // 横向き：左にリスト、右に再生中の曲とホイール
                    // 低い画面（横向きのスマホ）は曲の情報を小さい形に
                    final tall = c.maxHeight >= 520;
                    final right = min(c.maxWidth * 0.4, 440.0);
                    final w = min(right - 40, c.maxHeight * (tall ? 0.46 : 0.5));
                    return Row(children: [
                      Expanded(child: list),
                      SizedBox(
                        width: right,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(4, 10, 12, 10),
                          child: Column(children: [
                            if (tall)
                              Expanded(child: nowPanel(true))
                            else ...[
                              nowPanel(false),
                              const Spacer(),
                            ],
                            const SizedBox(height: 8),
                            wheel(w),
                          ]),
                        ),
                      ),
                    ]);
                  }
                  // 縦向き：上にリスト、下に再生中の曲とホイール（iPod の縦と同じ並び）
                  final w = min(c.maxWidth * 0.62, c.maxHeight * 0.28);
                  return Column(children: [
                    Expanded(child: list),
                    Padding(padding: const EdgeInsets.fromLTRB(12, 4, 12, 6), child: now),
                    Padding(padding: const EdgeInsets.only(bottom: 10), child: wheel(w)),
                  ]);
                }),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 左のタブとリスト（今の画面）。見出しは「■ LIB.ARTISTS」とタイトル
  Widget _thetaList(Palette p) {
    final top = _top;
    // ホイールがリストを操作していないときは、選んでいる行を控えめに
    top.active = !_nowFocused;
    final depth = _stack.length;
    final code = thetaTabs[_tab].label;
    final panel = Container(
      decoration: BoxDecoration(
        color: p.pop ? p.panel : null,
        border: Border.all(color: p.line, width: p.lineWidth),
        borderRadius: p.rounded ? BorderRadius.circular(p.radius) : null,
      ),
      clipBehavior: p.rounded ? Clip.antiAlias : Clip.none,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 6, 12, 6),
          child: Row(children: [
            SizedBox(
              width: 40,
              height: 36,
              child: depth > 1
                  ? IconButton(
                      padding: EdgeInsets.zero,
                      tooltip: '戻る（MENU）',
                      onPressed: pop,
                      icon: Icon(Icons.chevron_left, color: p.accent),
                    )
                  : Center(child: Container(width: 6, height: 6, color: p.accent)),
            ),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(depth > 1 ? 'LIB.$code / ${depth - 1}' : 'LIB.$code',
                    style: TextStyle(color: p.faint, fontSize: 10, letterSpacing: 2, fontFamily: p.mono)),
                Text(top.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: p.fg,
                        fontSize: 20,
                        height: 1.2,
                        fontFamily: p.display,
                        fontWeight: p.pop ? FontWeight.bold : FontWeight.w400)),
              ]),
            ),
          ]),
        ),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Stripes(color: p.line)),
        const SizedBox(height: 4),
        Expanded(
          child: ClipRect(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              switchInCurve: Curves.easeOut,
              switchOutCurve: Curves.easeIn,
              layoutBuilder: (cur, prev) => Stack(children: [...prev, ?cur]),
              transitionBuilder: (child, anim) {
                final incoming = child.key == top.key;
                final begin = incoming ? Offset(_forward ? 1 : -1, 0) : Offset(_forward ? -1 : 1, 0);
                return SlideTransition(position: Tween(begin: begin, end: Offset.zero).animate(anim), child: child);
              },
              child: KeyedSubtree(
                key: top.key,
                child: ListenableBuilder(listenable: top, builder: (context, _) => top.build(context)),
              ),
            ),
          ),
        ),
      ]),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 10, 8, 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        ThetaTabs(active: _tab, onSelect: _selectTab),
        Expanded(
          // リストを触ったら、ホイールのフォーカスもリストへ
          child: Listener(
            onPointerDown: (_) => _setFocusNow(false),
            child: CustomPaint(
              foregroundPainter: p.rounded ? null : CornersPainter(_nowFocused ? p.line : p.accent),
              child: _withToast(panel, p),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _withToast(Widget lcd, [Palette? p]) {
    return Stack(children: [
      Positioned.fill(child: lcd),
      if (_toast != null)
        Positioned(
          left: 16,
          right: 16,
          bottom: 14,
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: p?.raised ?? Colors.black.withValues(alpha: 0.72),
                border: p == null ? null : Border.all(color: p.accent),
                borderRadius: BorderRadius.circular(p == null || p.rounded ? 8 : 0),
              ),
              child: Text(_toast!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: p?.fg ?? Colors.white, fontSize: 13, fontWeight: FontWeight.w600, fontFamily: p?.mono)),
            ),
          ),
        ),
    ]);
  }

  Widget _header(String title) {
    final p = services.player;
    return Container(
      height: 24,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [LcdColors.headerTop, LcdColors.headerBottom],
        ),
        border: Border(bottom: BorderSide(color: Color(0xFF8E9399), width: 0.8)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Row(children: [
        SizedBox(
          width: 28,
          child: p.hasQueue
              ? Icon(p.playing ? Icons.play_arrow_rounded : Icons.pause_rounded, size: 16, color: const Color(0xFF2F72D8))
              : null,
        ),
        Expanded(
          child: Text(title,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: LcdColors.text)),
        ),
        const SizedBox(width: 28, child: _Battery()),
      ]),
    );
  }
}

class _Battery extends StatelessWidget {
  const _Battery();
  @override
  Widget build(BuildContext context) {
    return Row(mainAxisAlignment: MainAxisAlignment.end, children: [
      Container(
        width: 20,
        height: 10,
        padding: const EdgeInsets.all(1),
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFF555555), width: 1),
          borderRadius: BorderRadius.circular(2),
        ),
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF9BE36A), Color(0xFF3E9E1E)],
            ),
          ),
        ),
      ),
      Container(width: 2, height: 4, color: const Color(0xFF555555)),
    ]);
  }
}
