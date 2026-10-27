import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app.dart';
import 'click_wheel.dart';
import 'dialogs.dart';
import 'ipod_theme.dart';
import 'menus.dart';
import 'now_playing.dart';
import 'screens.dart';

/// 本体: 上に液晶、下にクリックホイール
class IPodShell extends StatefulWidget {
  const IPodShell({super.key});
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
    _pushInternal(mainMenu());
    services.settings.addListener(_onChange);
    services.player.addListener(_onChange);
    if (!services.settings.configured) {
      WidgetsBinding.instance.addPostFrameCallback((_) => showServerDialog(context));
    }
  }

  void _onChange() => setState(() {});

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
    if (_top is NowPlayingScreen) return;
    push(NowPlayingScreen());
  }

  void _click() {
    if (!services.settings.clicker) return;
    HapticFeedback.selectionClick();
    SystemSound.play(SystemSoundType.click);
  }

  void _onTick(int dir) {
    _click();
    _top.onScroll(dir);
  }

  void _onButton(WheelButton b) {
    HapticFeedback.lightImpact();
    switch (b) {
      case WheelButton.menu:
        pop();
      case WheelButton.select:
        _top.onSelect();
      case WheelButton.playPause:
        services.player.toggle();
      case WheelButton.next:
        services.player.next();
      case WheelButton.previous:
        services.player.previous();
    }
  }

  void _holdStart(WheelButton b) {
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
    services.settings.removeListener(_onChange);
    services.player.removeListener(_onChange);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
                  child: SizedBox(height: screenH, child: _lcd(colors)),
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
