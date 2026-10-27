import 'package:flutter/material.dart';

/// ThetaHomeHatch と同じ配色（app/src/main/java/.../ui/Theme.kt を移植）。
/// 計器盤（HUD）風：黒地にオレンジ 1 色、細い線、四角い角。
@immutable
class Palette {
  final Color bg, panel, raised, fg, muted, faint, line, accent, onAccent, widget, launch, zebra;

  /// POP（カラフル）：角を丸め、線を太く、ボタンに影、書体はゴシック
  final bool pop;
  final Color accent2, accent3;

  /// 背景の模様：'' / 'scan'（走査線、ALERT） / 'grid'（方眼、SCI-FI）
  final String backdrop;

  /// 見出しの上の警告の帯の太さ
  final double hazard;

  const Palette({
    required this.bg,
    required this.panel,
    required this.raised,
    required this.fg,
    required this.muted,
    required this.faint,
    required this.line,
    required this.accent,
    required this.onAccent,
    required this.widget,
    required this.launch,
    required this.zebra,
    this.pop = false,
    Color? accent2,
    Color? accent3,
    this.backdrop = '',
    this.hazard = 4,
  })  : accent2 = accent2 ?? accent,
        accent3 = accent3 ?? accent;

  /// タブの群：0 再生（accent）/ 1 ライブラリ（widget）/ 2 管理（launch）
  Color group(int g) => switch (g) { 0 => accent, 1 => widget, _ => launch };

  bool get isDark => bg.computeLuminance() < 0.5;

  /// 見出し・数字は Oswald、ラベルは等幅の Share Tech Mono。POP は端末のゴシック。日本語は端末の書体。
  String? get display => pop ? null : 'Oswald';
  String? get mono => pop ? null : 'ShareTechMono';
  double get lineWidth => pop ? 1.5 : 1;

  /// ボタン・入力欄の形：HUD は左上を落とした角、POP は少し丸めた角
  ShapeBorder shape({Color? side}) {
    final bs = side == null ? BorderSide.none : BorderSide(color: side, width: lineWidth);
    return pop
        ? RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: bs)
        : BeveledRectangleBorder(borderRadius: const BorderRadius.only(topLeft: Radius.circular(8)), side: bs);
  }
}

const darkPalette = Palette(
  bg: Color(0xFF0A0A0B),
  panel: Color(0xFF111113),
  raised: Color(0xFF19191C),
  fg: Color(0xFFEDEDED),
  muted: Color(0xFFA3A3A3),
  faint: Color(0xFF858585),
  line: Color(0xFF333336),
  accent: Color(0xFFFF6B1A),
  onAccent: Color(0xFF0A0A0B),
  widget: Color(0xFFEDEDED),
  launch: Color(0xFF7A7A7E),
  zebra: Color(0x0FFFFFFF),
);

/// 明るい地の計器盤：紙のような地に墨色の文字、オレンジは濃いめ
const lightPalette = Palette(
  bg: Color(0xFFF4F3EE),
  panel: Color(0xFFFFFFFF),
  raised: Color(0xFFE9E8E2),
  fg: Color(0xFF121212),
  muted: Color(0xFF474747),
  faint: Color(0xFF5E5E5E),
  line: Color(0xFFBDBCB4),
  accent: Color(0xFFB8400C),
  onAccent: Color(0xFFFFFFFF),
  widget: Color(0xFF121212),
  launch: Color(0xFF6A6A6A),
  zebra: Color(0x0D000000),
);

/// POP：クリームの地に墨色の太い線、コーラル・イエロー・ミント
const popPalette = Palette(
  bg: Color(0xFFFAF6EC),
  panel: Color(0xFFFFFFFF),
  raised: Color(0xFFF2EDE0),
  fg: Color(0xFF2B2B2B),
  muted: Color(0xFF4F4F4F),
  faint: Color(0xFF6B6B6B),
  line: Color(0xFF2B2B2B),
  accent: Color(0xFFEF6F51),
  onAccent: Color(0xFFFFFFFF),
  widget: Color(0xFF7FCFB5),
  launch: Color(0xFFF2BE2E),
  zebra: Color(0x26F5C842),
  pop: true,
  accent2: Color(0xFFF5C842),
  accent3: Color(0xFFA8E2CF),
);

/// ALERT：警報画面ふう。黒地に橙、警告の赤と正常の緑、太い警告の帯と走査線
const alertPalette = Palette(
  bg: Color(0xFF050404),
  panel: Color(0xFF0D0908),
  raised: Color(0xFF1A110C),
  fg: Color(0xFFFFD9B0),
  muted: Color(0xFFD6955C),
  faint: Color(0xFF9C6A42),
  line: Color(0xFF5C3418),
  accent: Color(0xFFFF7A00),
  onAccent: Color(0xFF050404),
  widget: Color(0xFFFF2A2A),
  launch: Color(0xFF39E07A),
  zebra: Color(0x14FF7A00),
  accent2: Color(0xFFFF2A2A),
  accent3: Color(0xFF39E07A),
  backdrop: 'scan',
  hazard: 10,
);

/// SCI-FI：操作卓ふう。黒に近い青緑の地に方眼、黄・水色・緑
const sciFiPalette = Palette(
  bg: Color(0xFF060C0E),
  panel: Color(0xFF0B1519),
  raised: Color(0xFF112128),
  fg: Color(0xFFDDF6FF),
  muted: Color(0xFF8FB8C4),
  faint: Color(0xFF5F8794),
  line: Color(0xFF1F3C46),
  accent: Color(0xFFF2E21B),
  onAccent: Color(0xFF060C0E),
  widget: Color(0xFF3FD0E8),
  launch: Color(0xFF7BE38B),
  zebra: Color(0x123FD0E8),
  accent2: Color(0xFF3FD0E8),
  accent3: Color(0xFF7BE38B),
  backdrop: 'grid',
  hazard: 6,
);

const hudThemes = ['dark', 'light', 'pop', 'alert', 'scifi', 'system'];

/// テーマ名から配色を決める。'system' は端末のダーク・ライトに合わせる
Palette paletteFor(String mode, Brightness system) => switch (mode) {
      'pop' => popPalette,
      'alert' => alertPalette,
      'scifi' => sciFiPalette,
      'light' => lightPalette,
      'dark' => darkPalette,
      _ => system == Brightness.dark ? darkPalette : lightPalette,
    };

class HudScope extends InheritedWidget {
  final Palette palette;
  const HudScope({super.key, required this.palette, required super.child});

  static Palette of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<HudScope>()?.palette ?? darkPalette;

  @override
  bool updateShouldNotify(HudScope old) => old.palette != palette;
}

/// ダイアログなど Material 部品の配色
ThemeData hudMaterialTheme(Palette p) {
  final scheme = ColorScheme(
    brightness: p.isDark ? Brightness.dark : Brightness.light,
    primary: p.accent,
    onPrimary: p.onAccent,
    secondary: p.widget,
    onSecondary: p.bg,
    error: const Color(0xFFFF4D4D),
    onError: Colors.black,
    surface: p.panel,
    onSurface: p.fg,
    surfaceContainerHighest: p.raised,
    onSurfaceVariant: p.muted,
    outline: p.line,
  );
  final r = p.pop ? 10.0 : 0.0;
  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    scaffoldBackgroundColor: p.bg,
    fontFamily: p.mono,
    dialogTheme: DialogThemeData(
      backgroundColor: p.panel,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(r), side: BorderSide(color: p.line)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(shape: p.shape() as OutlinedBorder),
    ),
  );
}
