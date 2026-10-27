import 'package:flutter/material.dart';

import 'hud_theme.dart';

/// ThetaHomeHatch の部品（ui/Bits.kt・Dashboard.kt）を Flutter に移したもの

/// 四隅のかぎ括弧（⌜ ⌝ ⌞ ⌟）
class CornersPainter extends CustomPainter {
  final Color color;
  final double length, width;
  const CornersPainter(this.color, {this.length = 8, this.width = 1.5});

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = width;
    final l = length, r = size.width, b = size.height;
    for (final (a, c) in [
      (const Offset(0, 0), Offset(l, 0)),
      (const Offset(0, 0), Offset(0, l)),
      (Offset(r, 0), Offset(r - l, 0)),
      (Offset(r, 0), Offset(r, l)),
      (Offset(0, b), Offset(l, b)),
      (Offset(0, b), Offset(0, b - l)),
      (Offset(r, b), Offset(r - l, b)),
      (Offset(r, b), Offset(r, b - l)),
    ]) {
      canvas.drawLine(a, c, p);
    }
  }

  @override
  bool shouldRepaint(CornersPainter old) => old.color != color;
}

/// 斜線の帯（警告テープ風）
class Stripes extends StatelessWidget {
  final Color color;
  final double height, gap;
  const Stripes({super.key, required this.color, this.height = 5, this.gap = 7});

  @override
  Widget build(BuildContext context) => SizedBox(
        height: height,
        child: ClipRect(child: CustomPaint(painter: _StripesPainter(color, gap), size: Size.infinite)),
      );
}

class _StripesPainter extends CustomPainter {
  final Color color;
  final double gap;
  _StripesPainter(this.color, this.gap);

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = gap * 0.45;
    for (var x = -size.height; x < size.width; x += gap) {
      canvas.drawLine(Offset(x, size.height), Offset(x + size.height, 0), p);
    }
  }

  @override
  bool shouldRepaint(_StripesPainter old) => old.color != color;
}

/// 目盛り：細い縦線を等間隔に（5 本ごとに長く）
class Ticks extends StatelessWidget {
  final Color? color;
  final double height;
  const Ticks({super.key, this.color, this.height = 8});

  @override
  Widget build(BuildContext context) {
    final c = color ?? HudScope.of(context).line;
    return SizedBox(height: height, child: CustomPaint(painter: _TicksPainter(c), size: Size.infinite));
  }
}

class _TicksPainter extends CustomPainter {
  final Color color;
  _TicksPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 1;
    var i = 0;
    for (var x = 0.0; x <= size.width; x += 6, i++) {
      final h = i % 5 == 0 ? size.height : size.height * 0.5;
      canvas.drawLine(Offset(x, size.height), Offset(x, size.height - h), p);
    }
  }

  @override
  bool shouldRepaint(_TicksPainter old) => old.color != color;
}

/// 背景の模様（ALERT の走査線・SCI-FI の方眼）
class BackdropPainter extends CustomPainter {
  final Palette p;
  BackdropPainter(this.p);

  @override
  void paint(Canvas canvas, Size size) {
    if (p.backdrop == 'scan') {
      final paint = Paint()
        ..color = p.accent.withValues(alpha: 0.05)
        ..strokeWidth = 1;
      for (var y = 0.0; y < size.height; y += 4) {
        canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
      }
    } else if (p.backdrop == 'grid') {
      final paint = Paint()
        ..color = p.widget.withValues(alpha: 0.07)
        ..strokeWidth = 1;
      for (var x = 0.0; x < size.width; x += 28) {
        canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
      }
      for (var y = 0.0; y < size.height; y += 28) {
        canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
      }
    }
  }

  @override
  bool shouldRepaint(BackdropPainter old) => old.p != p;
}

/// 見出し：オレンジの小さな四角＋等幅の文字（「■ SYS.TIME」）
class SectionLabel extends StatelessWidget {
  final String text;
  const SectionLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    final p = HudScope.of(context);
    return Row(children: [
      Container(width: 6, height: 6, color: p.accent),
      const SizedBox(width: 8),
      Text(text, style: TextStyle(color: p.faint, fontSize: 11, letterSpacing: 2, fontFamily: p.mono)),
    ]);
  }
}

/// 計器の区画：見出し（[ CODE ] 日本語 ////）と四隅のかぎ括弧。POP は角丸の枠に色の帯。
class HudPanel extends StatelessWidget {
  final String code;
  final String title;
  final Widget child;
  final bool expand; // 子を残りの高さいっぱいに（リスト用）
  final Widget? trailing;
  final EdgeInsets padding;
  const HudPanel({
    super.key,
    required this.code,
    required this.title,
    required this.child,
    this.expand = false,
    this.trailing,
    this.padding = const EdgeInsets.all(12),
  });

  @override
  Widget build(BuildContext context) {
    final p = HudScope.of(context);
    final body = expand ? Expanded(child: child) : child;
    if (p.pop) {
      final band = switch (code.hashCode % 3) { 0 => p.accent, 1 => p.accent3, _ => p.accent2 };
      final onBand = band == p.accent ? p.onAccent : p.fg;
      return PopShadow(
        radius: 10,
        child: Container(
          decoration: BoxDecoration(
            color: p.panel,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: p.line, width: p.lineWidth),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min, children: [
            Container(
              color: band,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(children: [
                Text(code, style: TextStyle(color: onBand, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1)),
                const SizedBox(width: 8),
                Expanded(child: Text(title, style: TextStyle(color: onBand, fontSize: 12))),
                ?trailing,
              ]),
            ),
            Container(height: p.lineWidth, color: p.line),
            if (expand) Expanded(child: Padding(padding: padding, child: child)) else Padding(padding: padding, child: child),
          ]),
        ),
      );
    }
    return CustomPaint(
      foregroundPainter: CornersPainter(p.accent),
      child: Container(
        decoration: BoxDecoration(border: Border.all(color: p.line)),
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
          children: [
            Row(children: [
              Text('[ $code ]', style: TextStyle(color: p.accent, fontSize: 11, letterSpacing: 2, fontFamily: p.mono)),
              const SizedBox(width: 8),
              Text(title, style: TextStyle(color: p.muted, fontSize: 11)),
              const SizedBox(width: 8),
              Expanded(child: Stripes(color: p.line)),
              if (trailing != null) ...[const SizedBox(width: 8), trailing!],
            ]),
            const SizedBox(height: 8),
            body,
          ],
        ),
      ),
    );
  }
}

/// POP のボタンの右下にずらした影
class PopShadow extends StatelessWidget {
  final Widget child;
  final double radius;
  const PopShadow({super.key, required this.child, this.radius = 8});

  @override
  Widget build(BuildContext context) {
    final p = HudScope.of(context);
    if (!p.pop) return child;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [BoxShadow(color: p.fg, offset: const Offset(3, 3))],
      ),
      child: child,
    );
  }
}

/// 角を 1 つ落とした矩形のボタン。primary はアクセント色で塗る
class PillButton extends StatelessWidget {
  final String? text;
  final IconData? icon;
  final VoidCallback? onTap;
  final bool primary;
  final double minHeight;
  final double iconSize;
  const PillButton({
    super.key,
    this.text,
    this.icon,
    this.onTap,
    this.primary = false,
    this.minHeight = 40,
    this.iconSize = 20,
  });

  @override
  Widget build(BuildContext context) {
    final p = HudScope.of(context);
    final enabled = onTap != null;
    final fg = !enabled ? p.faint : (primary ? p.onAccent : p.fg);
    final bg = primary ? p.accent : (p.pop ? p.panel : Colors.transparent);
    return PopShadow(
      child: Material(
        color: bg,
        shape: p.shape(side: primary && !p.pop ? p.accent : p.line),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: minHeight),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
                if (icon != null) Icon(icon, color: fg, size: iconSize),
                if (icon != null && text != null) const SizedBox(width: 6),
                if (text != null)
                  Text(text!, style: TextStyle(color: fg, fontSize: 13, letterSpacing: 0.5, fontFamily: p.mono)),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// 種類などを示す小さな札（DIR・FLAC など）。highlight で塗る
class HudBadge extends StatelessWidget {
  final String text;
  final bool highlight;
  final VoidCallback? onTap;
  final double width;
  const HudBadge(this.text, {super.key, this.highlight = false, this.onTap, this.width = 46});

  @override
  Widget build(BuildContext context) {
    final p = HudScope.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: width,
        padding: const EdgeInsets.symmetric(vertical: 4),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: highlight ? p.accent : Colors.transparent,
          border: Border.all(color: highlight ? p.accent : p.line),
          borderRadius: BorderRadius.circular(p.pop ? 6 : 0),
        ),
        child: Text(text,
            maxLines: 1,
            style: TextStyle(color: highlight ? p.onAccent : p.muted, fontSize: 11, fontFamily: p.mono)),
      ),
    );
  }
}

/// 計器の読み（NET / OFFLINE のような箱）。左に太い線
class ReadoutBox extends StatelessWidget {
  final String label;
  final String value;
  final bool accent;
  const ReadoutBox(this.label, this.value, {super.key, this.accent = false});

  @override
  Widget build(BuildContext context) {
    final p = HudScope.of(context);
    final c = accent ? p.accent : p.faint;
    return Container(
      decoration: BoxDecoration(
        color: p.pop ? p.panel : null,
        border: Border.all(color: accent ? p.accent : p.line, width: p.lineWidth),
        borderRadius: BorderRadius.circular(p.pop ? 8 : 0),
      ),
      child: IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(width: 3, color: c),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(label,
                    maxLines: 1,
                    style: TextStyle(color: p.faint, fontSize: 10, letterSpacing: 1.5, fontFamily: p.mono)),
                const SizedBox(height: 4),
                Text(value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: accent ? p.accent : p.fg, fontSize: 14, fontFamily: p.mono)),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}

/// 押せる行。zebra に並び順を渡すと奇数行に薄い地を敷く
class HudRow extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final int zebra;
  final bool active;
  const HudRow({super.key, required this.child, this.onTap, this.zebra = -1, this.active = false});

  @override
  Widget build(BuildContext context) {
    final p = HudScope.of(context);
    return Material(
      color: active ? p.accent.withValues(alpha: 0.18) : (zebra % 2 == 1 ? p.zebra : Colors.transparent),
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), child: child),
        ),
      ),
    );
  }
}

/// 2 行（タイトルと補足）
class TwoLines extends StatelessWidget {
  final String title;
  final String? sub;
  final bool bold;
  final Color? color;
  const TwoLines(this.title, this.sub, {super.key, this.bold = false, this.color});

  @override
  Widget build(BuildContext context) {
    final p = HudScope.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Text(title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
              color: color ?? p.fg, fontSize: 15, fontWeight: bold ? FontWeight.bold : FontWeight.normal)),
      if (sub != null && sub!.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text(sub!, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.muted, fontSize: 12)),
        ),
    ]);
  }
}

/// 頭文字の箱（かぎ括弧付き）
class Initial extends StatelessWidget {
  final String text;
  final double size;
  const Initial(this.text, {super.key, this.size = 40});

  @override
  Widget build(BuildContext context) {
    final p = HudScope.of(context);
    final ch = text.isEmpty ? '?' : text.characters.first.toUpperCase();
    return CustomPaint(
      foregroundPainter: CornersPainter(p.accent, length: 6),
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: p.raised, border: Border.all(color: p.line)),
        child: Text(ch, style: TextStyle(color: p.fg, fontSize: size * 0.38)),
      ),
    );
  }
}

class Note extends StatelessWidget {
  final String text;
  const Note(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    final p = HudScope.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      child: Text(text, style: TextStyle(color: p.faint, fontSize: 12, height: 1.6)),
    );
  }
}

/// 細い線の進捗バー（目盛り付き）
class HudProgress extends StatelessWidget {
  final double value;
  const HudProgress(this.value, {super.key});

  @override
  Widget build(BuildContext context) {
    final p = HudScope.of(context);
    final v = value.isNaN ? 0.0 : value.clamp(0.0, 1.0);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SizedBox(
        height: 6,
        child: Stack(children: [
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: p.line, width: p.lineWidth),
                borderRadius: BorderRadius.circular(p.pop ? 3 : 0),
              ),
            ),
          ),
          FractionallySizedBox(
            widthFactor: v,
            child: Container(
              decoration: BoxDecoration(color: p.accent, borderRadius: BorderRadius.circular(p.pop ? 3 : 0)),
            ),
          ),
        ]),
      ),
      const SizedBox(height: 3),
      const Ticks(height: 5),
    ]);
  }
}
