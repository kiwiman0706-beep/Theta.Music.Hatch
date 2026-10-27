import 'package:flutter/material.dart';

/// iPod classic 風の配色
class IPodColors {
  final Color bodyTop, bodyBottom, wheel, wheelEdge, wheelLabel, center, centerEdge;
  const IPodColors({
    required this.bodyTop,
    required this.bodyBottom,
    required this.wheel,
    required this.wheelEdge,
    required this.wheelLabel,
    required this.center,
    required this.centerEdge,
  });

  static const silver = IPodColors(
    bodyTop: Color(0xFFF1F1F2),
    bodyBottom: Color(0xFFC9CACD),
    wheel: Color(0xFFF7F7F7),
    wheelEdge: Color(0xFFB9BABD),
    wheelLabel: Color(0xFFA4A6AA),
    center: Color(0xFFE6E7E9),
    centerEdge: Color(0xFFB0B1B4),
  );

  static const black = IPodColors(
    bodyTop: Color(0xFF2B2B2E),
    bodyBottom: Color(0xFF111113),
    wheel: Color(0xFF232325),
    wheelEdge: Color(0xFF0A0A0B),
    wheelLabel: Color(0xFFBDBDC2),
    center: Color(0xFF19191B),
    centerEdge: Color(0xFF050506),
  );
}

class LcdColors {
  static const bg = Colors.white;
  static const text = Color(0xFF111111);
  static const sub = Color(0xFF6B6B6B);
  static const headerTop = Color(0xFFF6F7F8);
  static const headerBottom = Color(0xFFCDD1D6);
  static const selTop = Color(0xFF6AAEF4);
  static const selBottom = Color(0xFF1C66D0);
  static const barTrack = Color(0xFFE2E4E7);
  static const selection = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [selTop, Color(0xFF3D8BE6), selBottom],
    stops: [0, 0.5, 1],
  );
}
