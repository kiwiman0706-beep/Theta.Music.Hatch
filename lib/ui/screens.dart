import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../app.dart';
import '../core/models.dart';
import 'ipod_theme.dart';

/// 画面スタックの操作（Shell が実装）
abstract class Nav {
  BuildContext get context;
  void push(IPodScreen s);
  void pop();
  void showNowPlaying();
  /// 液晶の下の方に短いお知らせを出す
  void toast(String message);
}

late Nav nav;

/// iPod の液晶に表示される 1 画面
abstract class IPodScreen extends ChangeNotifier {
  String get title;
  final Key key = UniqueKey();
  void onScroll(int delta) {}
  void onSelect() {}
  /// 中央ボタンの長押し（お気に入りの登録など）
  void onLongSelect() {}
  Widget build(BuildContext context);
  void attach() {}
  void detach() {}
}

class MenuItem {
  final String label;
  final String? detail;
  final bool chevron;
  final VoidCallback? onSelect;
  final VoidCallback? onLong; // 中央ボタン長押し・行の長押し
  final bool starred;
  const MenuItem(this.label, {this.detail, this.chevron = false, this.onSelect, this.onLong, this.starred = false});
}

/// リスト形式のメニュー画面
class MenuScreen extends IPodScreen {
  @override
  final String title;
  final List<MenuItem> Function() builder;
  final List<Listenable> deps;
  final bool letterIndex; // 高速スクロール時に頭文字を表示
  final bool splitArt; // 右半分にアートワーク（iPod classic のメインメニュー風）

  List<MenuItem> items = [];
  int selected = 0;
  final ScrollController scroll = ScrollController();
  double _viewport = 0;
  double _rowH = 32;
  DateTime _lastTick = DateTime.fromMillisecondsSinceEpoch(0);
  int _streak = 0;
  String? letter;
  Timer? _letterTimer;

  MenuScreen(this.title, this.builder, {this.deps = const [], this.letterIndex = false, this.splitArt = false}) {
    items = builder();
  }

  void _rebuild() {
    items = builder();
    if (selected >= items.length) selected = items.isEmpty ? 0 : items.length - 1;
    notifyListeners();
  }

  @override
  void attach() {
    for (final d in deps) {
      d.addListener(_rebuild);
    }
    _rebuild();
  }

  @override
  void detach() {
    for (final d in deps) {
      d.removeListener(_rebuild);
    }
  }

  @override
  void onScroll(int delta) {
    if (items.isEmpty) return;
    final now = DateTime.now();
    _streak = now.difference(_lastTick).inMilliseconds < 70 ? _streak + 1 : 0;
    _lastTick = now;
    var step = 1;
    if (items.length > 60) step = _streak > 24 ? 8 : (_streak > 10 ? 3 : 1);
    final next = (selected + delta * step).clamp(0, items.length - 1);
    if (next == selected) return;
    selected = next;
    _ensureVisible();
    if (letterIndex && _streak > 10) {
      final l = items[selected].label;
      letter = l.isEmpty ? '' : l.characters.first.toUpperCase();
      _letterTimer?.cancel();
      _letterTimer = Timer(const Duration(milliseconds: 700), () {
        letter = null;
        notifyListeners();
      });
    }
    notifyListeners();
  }

  void _ensureVisible() {
    if (!scroll.hasClients || _viewport <= 0) return;
    final top = selected * _rowH;
    final bottom = top + _rowH;
    final off = scroll.offset;
    if (top < off) {
      scroll.jumpTo(top);
    } else if (bottom > off + _viewport) {
      scroll.jumpTo(bottom - _viewport);
    }
  }

  @override
  void onSelect() {
    if (items.isEmpty) return;
    items[selected].onSelect?.call();
  }

  @override
  void onLongSelect() {
    if (items.isEmpty) return;
    items[selected].onLong?.call();
  }

  @override
  void dispose() {
    _letterTimer?.cancel();
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final list = LayoutBuilder(builder: (context, c) {
      _viewport = c.maxHeight;
      final rows = (c.maxHeight / 34).floor().clamp(5, 12);
      _rowH = c.maxHeight / rows;
      WidgetsBinding.instance.addPostFrameCallback((_) => _ensureVisible());
      if (items.isEmpty) {
        return const Center(child: Text('No items', style: TextStyle(color: LcdColors.sub)));
      }
      return ListView.builder(
        controller: scroll,
        physics: const ClampingScrollPhysics(),
        itemExtent: _rowH,
        itemCount: items.length,
        itemBuilder: (context, i) => _row(items[i], i == selected, i),
      );
    });
    final body = splitArt
        ? Row(children: [Expanded(child: list), const Expanded(child: _ArtPanel())])
        : list;
    return Stack(children: [
      Positioned.fill(child: body),
      if (letter != null)
        Center(
          child: Container(
            width: 64,
            height: 64,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(letter!, style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.bold)),
          ),
        ),
    ]);
  }

  Widget _row(MenuItem it, bool sel, int i) {
    final color = sel ? Colors.white : LcdColors.text;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        selected = i;
        notifyListeners();
        it.onSelect?.call();
      },
      onLongPress: it.onLong == null
          ? null
          : () {
              selected = i;
              notifyListeners();
              it.onLong!.call();
            },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: sel ? const BoxDecoration(gradient: LcdColors.selection) : null,
        child: Row(children: [
          if (it.starred)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Icon(Icons.star_rounded, size: _rowH * 0.5, color: sel ? Colors.white : const Color(0xFF2F72D8)),
            ),
          Expanded(
            child: Text(it.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: color, fontSize: _rowH * 0.5, fontWeight: FontWeight.w600)),
          ),
          if (it.detail != null)
            Padding(
              padding: const EdgeInsets.only(left: 6),
              child: Text(it.detail!,
                  style: TextStyle(color: sel ? Colors.white70 : LcdColors.sub, fontSize: _rowH * 0.42)),
            ),
          if (it.chevron) Icon(Icons.chevron_right, color: color, size: _rowH * 0.62),
        ]),
      ),
    );
  }
}

/// メインメニュー右側のアートワーク（再生中の曲、なければランダムなアルバムを切り替え表示）
class _ArtPanel extends StatefulWidget {
  const _ArtPanel();
  @override
  State<_ArtPanel> createState() => _ArtPanelState();
}

class _ArtPanelState extends State<_ArtPanel> {
  Timer? _t;
  int _n = 0;

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(seconds: 7), (_) => setState(() => _n++));
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cur = services.player.current?.art;
    ArtRef? ref = cur;
    if (ref == null) {
      final withArt = services.library.albums.where((a) => a.art != null).toList();
      if (withArt.isNotEmpty) ref = withArt[(_n * 7919) % withArt.length].art;
    }
    return Container(
      decoration: const BoxDecoration(
        border: Border(left: BorderSide(color: Color(0xFFBBBBBB), width: 0.5)),
      ),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 600),
        child: ArtImage(ref, key: ValueKey(ref?.key), fit: BoxFit.cover),
      ),
    );
  }
}

/// アルバムアート表示（NAS から取得・キャッシュ）
class ArtImage extends StatefulWidget {
  final ArtRef? ref;
  final BoxFit fit;
  final Widget? placeholder; // 画像が無いとき（スキンごとに変える）
  const ArtImage(this.ref, {super.key, this.fit = BoxFit.cover, this.placeholder});
  @override
  State<ArtImage> createState() => _ArtImageState();
}

class _ArtImageState extends State<ArtImage> {
  Uint8List? _data;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(ArtImage old) {
    super.didUpdateWidget(old);
    if (old.ref?.key != widget.ref?.key) _load();
  }

  void _load() {
    final ref = widget.ref;
    if (ref == null) {
      _data = null;
      return;
    }
    _data = services.art.peek(ref);
    if (_data == null) {
      services.art.load(ref).then((d) {
        if (mounted && widget.ref?.key == ref.key) setState(() => _data = d);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_data == null) {
      if (widget.placeholder != null) return widget.placeholder!;
      return Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFE9EBEE), Color(0xFFB8BDC4)],
          ),
        ),
        child: const Center(child: Icon(Icons.music_note_rounded, color: Colors.white, size: 48)),
      );
    }
    return Image.memory(_data!,
        fit: widget.fit,
        width: double.infinity,
        height: double.infinity,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => const ColoredBox(color: Color(0xFFDDDDDD)));
  }
}

/// テキスト表示だけの画面（About / スキャン進捗など）
class InfoScreen extends IPodScreen {
  @override
  final String title;
  final Listenable? source;
  final Widget Function(BuildContext) content;
  final VoidCallback? select;
  InfoScreen(this.title, this.content, {this.source, this.select});

  @override
  void attach() => source?.addListener(notifyListeners);
  @override
  void detach() => source?.removeListener(notifyListeners);
  @override
  void onSelect() => select?.call();

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(12),
        child: DefaultTextStyle(
          style: const TextStyle(color: LcdColors.text, fontSize: 15, height: 1.35),
          child: content(context),
        ),
      );
}

/// iPod 風プログレスバー
class IPodBar extends StatelessWidget {
  final double value;
  final bool diamond;
  const IPodBar(this.value, {super.key, this.diamond = false});

  @override
  Widget build(BuildContext context) {
    final v = value.isNaN ? 0.0 : value.clamp(0.0, 1.0);
    return LayoutBuilder(builder: (context, c) {
      return SizedBox(
        height: 14,
        child: Stack(clipBehavior: Clip.none, alignment: Alignment.centerLeft, children: [
          Container(
            height: 10,
            decoration: BoxDecoration(
              color: LcdColors.barTrack,
              borderRadius: BorderRadius.circular(2),
              border: Border.all(color: const Color(0xFF9EA3A9), width: 0.6),
            ),
          ),
          if (!diamond)
            Container(
              width: c.maxWidth * v,
              height: 10,
              decoration: BoxDecoration(gradient: LcdColors.selection, borderRadius: BorderRadius.circular(2)),
            ),
          if (diamond)
            Positioned(
              left: (c.maxWidth * v - 7).clamp(0, c.maxWidth - 14),
              child: Transform.rotate(
                angle: 0.785,
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: const BoxDecoration(gradient: LcdColors.selection),
                ),
              ),
            ),
        ]),
      );
    });
  }
}
