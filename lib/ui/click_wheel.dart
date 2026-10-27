import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import 'ipod_theme.dart';

enum WheelButton { menu, next, previous, playPause, select }

/// iPod のクリックホイール。リングをなぞると回転イベント、
/// 上下左右/中央のタップでボタンイベント、◀◀/▶▶ 長押しで早送り/巻き戻し。
class ClickWheel extends StatefulWidget {
  final double size;
  final IPodColors colors;
  final void Function(int dir) onTick; // +1: 時計回り（下へ） -1: 反時計回り
  final void Function(WheelButton b) onButton;
  final void Function(WheelButton b)? onHoldStart;
  final void Function(WheelButton b)? onHoldEnd;

  const ClickWheel({
    super.key,
    required this.size,
    required this.colors,
    required this.onTick,
    required this.onButton,
    this.onHoldStart,
    this.onHoldEnd,
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
    if (b == WheelButton.next || b == WheelButton.previous) {
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
            Positioned(
              top: s * 0.075,
              child: pressable(
                WheelButton.menu,
                Text('MENU',
                    style: TextStyle(
                      color: label,
                      fontSize: s * 0.062,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                    )),
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
            ),
          ],
        ),
      ),
    );
  }
}
