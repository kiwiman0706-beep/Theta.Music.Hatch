import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../app.dart';

/// ジャケットに重ねるオーディオビジュアライザー（昔のプレーヤーの、頂点の印が落ちてくるスペクトラムと波形）。
/// 設定（Visualizer）が off のときは何も描かない。
class VisualizerView extends StatefulWidget {
  final Color color; // バー・波形の色
  final Color peak; // 頂点の印の色
  const VisualizerView({super.key, required this.color, required this.peak});

  @override
  State<VisualizerView> createState() => _VisualizerViewState();
}

class _VisualizerViewState extends State<VisualizerView> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final _level = Float32List(24); // 表示中の高さ（上がるのは速く、下がるのはゆっくり）
  final _peak = Float32List(24); // 頂点の印
  final _peakHold = Int32List(24);
  Duration _last = Duration.zero;

  @override
  void initState() {
    super.initState();
    services.visualizer.attach();
    _ticker = createTicker(_tick)..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    services.visualizer.detach();
    super.dispose();
  }

  void _tick(Duration now) {
    final dt = ((now - _last).inMicroseconds / 1e6).clamp(0.0, 0.1);
    _last = now;
    final target = services.visualizer.bands;
    var moving = false;
    for (var i = 0; i < _level.length; i++) {
      final t = i < target.length ? target[i] : 0.0;
      _level[i] = t > _level[i] ? t : max(t, _level[i] - dt * 1.6);
      if (_level[i] >= _peak[i]) {
        _peak[i] = _level[i];
        _peakHold[i] = 18; // 少し止まってから落ちる
      } else if (_peakHold[i] > 0) {
        _peakHold[i]--;
      } else {
        _peak[i] = max(0, _peak[i] - dt * 0.6);
      }
      if (_level[i] > 0.001 || _peak[i] > 0.001) moving = true;
    }
    if (moving || services.visualizer.enabled) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final style = services.settings.visualizer;
    if (style == 'off') return const SizedBox.shrink();
    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          painter: _VisPainter(style, _level, _peak, services.visualizer.wave, widget.color, widget.peak),
          size: Size.infinite,
        ),
      ),
    );
  }
}

class _VisPainter extends CustomPainter {
  final String style;
  final Float32List level, peak, wave;
  final Color color, peakColor;
  _VisPainter(this.style, this.level, this.peak, this.wave, this.color, this.peakColor);

  @override
  void paint(Canvas canvas, Size size) {
    // 下の方を少し暗くして、ジャケットの上でも見えるように
    final shade = Rect.fromLTWH(0, size.height * 0.4, size.width, size.height * 0.6);
    canvas.drawRect(
      shade,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x00000000), Color(0x99000000)],
        ).createShader(shade),
    );
    if (style == 'wave') {
      _wave(canvas, size);
    } else {
      _bars(canvas, size);
    }
  }

  /// LED のように区切ったバーと、落ちてくる頂点の印
  void _bars(Canvas canvas, Size size) {
    final n = level.length;
    final gap = size.width * 0.012;
    final w = (size.width - gap * (n + 1)) / n;
    final maxH = size.height * 0.62;
    final seg = max(3.0, size.height / 70);
    final p = Paint()..color = color;
    final pk = Paint()..color = peakColor;
    for (var i = 0; i < n; i++) {
      final x = gap + i * (w + gap);
      final h = level[i] * maxH;
      for (var y = 0.0; y < h; y += seg) {
        canvas.drawRect(Rect.fromLTWH(x, size.height - y - seg * 0.75, w, seg * 0.75), p);
      }
      if (peak[i] > 0.02) {
        canvas.drawRect(Rect.fromLTWH(x, size.height - peak[i] * maxH - seg * 0.9, w, seg * 0.6), pk);
      }
    }
  }

  /// オシロスコープのような波形
  void _wave(Canvas canvas, Size size) {
    if (wave.isEmpty) return;
    final mid = size.height * 0.72;
    final amp = size.height * 0.22;
    final path = Path();
    for (var i = 0; i < wave.length; i++) {
      final x = size.width * i / (wave.length - 1);
      final y = mid - wave[i] * amp;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(
        path,
        Paint()
          ..color = color.withValues(alpha: 0.35)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 6
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4));
    canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2);
  }

  @override
  bool shouldRepaint(_VisPainter old) => true;
}
