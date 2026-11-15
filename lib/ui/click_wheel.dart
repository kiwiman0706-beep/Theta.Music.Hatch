import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import 'ipod_theme.dart';

enum WheelButton { menu, next, previous, playPause, select }

/// ホイールに出す案内（その時に押すと何が起きるか）。液晶なので状況に合わせて書き換える
class WheelGuide {
  final String? menu; // MENU の下：上の階層へ・再生中へ・リストへ
  final String? menuHold; // MENU の長押し
  final String? center; // 中央：SELECT・SEEK・VOLUME
  final String? centerHold; // 中央の長押し
  final String? ring; // リング：← VOLUME → など（8 時から 4 時に沿って）
  const WheelGuide({this.menu, this.menuHold, this.center, this.centerHold, this.ring});
}

/// iPod のクリックホイール。リングをなぞると回転イベント、
/// 上下左右/中央のタップでボタンイベント、◀◀/▶▶ 長押しで早送り/巻き戻し、
/// 中央・MENU の長押しは onHoldStart で受ける（お気に入り・音声検索）。
class ClickWheel extends StatefulWidget {
  final double size;
  final IPodColors colors;
  final void Function(int dir) onTick; // +1: 時計回り（下へ） -1: 反時計回り
  final void Function(WheelButton b) onButton;
  final void Function(WheelButton b)? onHoldStart;
  final void Function(WheelButton b)? onHoldEnd;
  final WheelGuide? guide;

  const ClickWheel({
    super.key,
    required this.size,
    required this.colors,
    required this.onTick,
    required this.onButton,
    this.onHoldStart,
    this.onHoldEnd,
    this.guide,
  });

  @override
  State<ClickWheel> createState() => _ClickWheelState();
}

class _ClickWheelState extends State<ClickWheel> {
  static const _step = pi / 10; // 18° で 1 クリック
  double? _lastAngle;
  double _acc = 0;
  double _total = 0;
  bool _dragging = false;
  bool _holding = false;
  WheelButton? _downButton;
  WheelButton? _pressed;
  Timer? _holdTimer;

  double get _r => widget.size / 2;
  double get _centerR => widget.size * 0.19;

  Offset _rel(Offset local) => local - Offset(_r, _r);

  WheelButton? _buttonAt(Offset local) {
    final p = _rel(local);
    final d = p.distance;
    if (d > _r) return null;
    if (d < _centerR) return WheelButton.select;
    final a = atan2(p.dy, p.dx); // 右=0, 下=+π/2
    if (a > -3 * pi / 4 && a <= -pi / 4) return WheelButton.menu;
    if (a > -pi / 4 && a <= pi / 4) return WheelButton.next;
    if (a > pi / 4 && a <= 3 * pi / 4) return WheelButton.playPause;
    return WheelButton.previous;
  }

  void _down(PointerDownEvent e) {
    final b = _buttonAt(e.localPosition);
    if (b == null) return;
    _downButton = b;
    _dragging = false;
    _holding = false;
    _acc = 0;
    _total = 0;
    final p = _rel(e.localPosition);
    _lastAngle = p.distance > _centerR * 0.6 ? atan2(p.dy, p.dx) : null;
    setState(() => _pressed = b);
    _holdTimer?.cancel();
    if (b != WheelButton.playPause) {
      _holdTimer = Timer(const Duration(milliseconds: 550), () {
        if (!_dragging) {
          _holding = true;
          widget.onHoldStart?.call(b);
        }
      });
    }
  }

  void _move(PointerMoveEvent e) {
    if (_downButton == null || _holding) return;
    final p = _rel(e.localPosition);
    if (p.distance < _centerR * 0.6) {
      _lastAngle = null;
      return;
    }
    final a = atan2(p.dy, p.dx);
    if (_lastAngle == null) {
      _lastAngle = a;
      return;
    }
    var d = a - _lastAngle!;
    if (d > pi) d -= 2 * pi;
    if (d < -pi) d += 2 * pi;
    _lastAngle = a;
    _acc += d;
    _total += d.abs();
    if (!_dragging && _total > _step * 0.6) {
      _dragging = true;
      _holdTimer?.cancel();
      setState(() => _pressed = null);
    }
    while (_acc >= _step) {
      _acc -= _step;
      widget.onTick(1);
    }
    while (_acc <= -_step) {
      _acc += _step;
      widget.onTick(-1);
    }
  }

  void _up(PointerUpEvent e) {
    _holdTimer?.cancel();
    final b = _downButton;
    if (b != null) {
      if (_holding) {
        widget.onHoldEnd?.call(b);
      } else if (!_dragging) {
        widget.onButton(b);
      }
    }
    _reset();
  }

  void _cancel(PointerCancelEvent e) {
    _holdTimer?.cancel();
    if (_holding && _downButton != null) widget.onHoldEnd?.call(_downButton!);
    _reset();
  }

  void _reset() {
    _downButton = null;
    _dragging = false;
    _holding = false;
    _lastAngle = null;
    setState(() => _pressed = null);
  }

  @override
  void dispose() {
    _holdTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.colors;
    final s = widget.size;
    final label = c.wheelLabel;
    final iconSize = s * 0.085;
    final g = widget.guide;
    final small = TextStyle(color: label, fontSize: max(9.0, s * 0.03), height: 1.25);
    Widget pressable(WheelButton b, Widget child) => AnimatedOpacity(
          duration: const Duration(milliseconds: 80),
          opacity: _pressed == b ? 0.45 : 1,
          child: child,
        );
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: _down,
      onPointerMove: _move,
      onPointerUp: _up,
      onPointerCancel: _cancel,
      child: SizedBox(
        width: s,
        height: s,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: c.wheel,
                border: Border.all(color: c.wheelEdge, width: 1),
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.18), blurRadius: 6, offset: const Offset(0, 2)),
                ],
              ),
            ),
            // リングの案内（← VOLUME → など）。8 時から 4 時まで、下側の縁に沿って
            if (g?.ring != null)
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _ArcTextPainter(g!.ring!, TextStyle(
                      color: label.withValues(alpha: 0.85),
                      fontSize: max(10.0, s * 0.04),
                      fontWeight: FontWeight.w700,
                      letterSpacing: s * 0.004,
                    )),
                  ),
                ),
              ),
            Positioned(
              top: s * 0.065,
              child: pressable(
                WheelButton.menu,
                Column(mainAxisSize: MainAxisSize.min, children: [
                  Text('MENU',
                      style: TextStyle(
                        color: label,
                        fontSize: s * 0.062,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2,
                      )),
                  if (g?.menu != null) Text(g!.menu!, style: small),
                  if (g?.menuHold != null) Text(g!.menuHold!, style: small.copyWith(color: label.withValues(alpha: 0.6))),
                ]),
              ),
            ),
            Positioned(
              right: s * 0.06,
              child: pressable(WheelButton.next, Icon(Icons.fast_forward_rounded, color: label, size: iconSize * 1.25)),
            ),
            Positioned(
              left: s * 0.06,
              child: pressable(WheelButton.previous, Icon(Icons.fast_rewind_rounded, color: label, size: iconSize * 1.25)),
            ),
            Positioned(
              bottom: s * 0.07,
              child: pressable(
                WheelButton.playPause,
                Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.play_arrow_rounded, color: label, size: iconSize),
                  Icon(Icons.pause_rounded, color: label, size: iconSize),
                ]),
              ),
            ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 80),
              width: _centerR * 2,
              height: _centerR * 2,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: _pressed == WheelButton.select
                      ? [c.centerEdge, c.center]
                      : [Color.lerp(c.center, Colors.white, 0.25)!, c.center],
                ),
                border: Border.all(color: c.centerEdge, width: 1),
              ),
              alignment: Alignment.center,
              // 中央ボタンの案内（SELECT・SEEK など）
              child: g?.center == null
                  ? null
                  : Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(g!.center!,
                          style: TextStyle(
                              color: label, fontSize: s * 0.042, fontWeight: FontWeight.w700, letterSpacing: s * 0.003)),
                      if (g.centerHold != null)
                        Text(g.centerHold!, style: small.copyWith(color: label.withValues(alpha: 0.6))),
                    ]),
            ),
          ],
        ),
      ),
    );
  }
}

/// 文字を円弧に沿って並べる（下側の縁。文字の上は中心を向く）
class _ArcTextPainter extends CustomPainter {
  final String text;
  final TextStyle style;
  _ArcTextPainter(this.text, this.style);

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2 * 0.895;
    final glyphs = [
      for (final ch in text.characters)
        TextPainter(text: TextSpan(text: ch, style: style), textDirection: TextDirection.ltr)..layout(),
    ];
    final total = glyphs.fold<double>(0, (a, g) => a + g.width);
    // 6 時（真下＝π/2）を中心に、左（8 時側）から右（4 時側）へ
    var a = pi / 2 + total / r / 2;
    for (final g in glyphs) {
      final mid = a - g.width / r / 2;
      canvas.save();
      canvas.translate(c.dx + r * cos(mid), c.dy + r * sin(mid));
      canvas.rotate(mid - pi / 2);
      g.paint(canvas, Offset(-g.width / 2, -g.height / 2));
      canvas.restore();
      a -= g.width / r;
    }
  }

  @override
  bool shouldRepaint(_ArcTextPainter old) => old.text != text || old.style != style;
}
