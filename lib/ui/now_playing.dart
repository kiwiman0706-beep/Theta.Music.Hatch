import 'dart:async';

import 'package:flutter/material.dart';

import '../app.dart';
import 'ipod_theme.dart';
import 'screens.dart';

enum _Mode { progress, volume, scrub }

/// Now Playing 画面。ホイール回転=音量、中央ボタン=シーク（スクラブ）モード切替
class NowPlayingScreen extends IPodScreen {
  @override
  String get title => 'Now Playing';

  _Mode _mode = _Mode.progress;
  Timer? _modeTimer;

  @override
  void attach() => services.player.addListener(notifyListeners);
  @override
  void detach() => services.player.removeListener(notifyListeners);

  void _setMode(_Mode m) {
    _mode = m;
    _modeTimer?.cancel();
    if (m != _Mode.progress) {
      _modeTimer = Timer(const Duration(seconds: 3), () {
        _mode = _Mode.progress;
        notifyListeners();
      });
    }
    notifyListeners();
  }

  @override
  void onScroll(int delta) {
    if (_mode == _Mode.scrub) {
      services.player.seekBy(Duration(seconds: 4 * delta));
      _setMode(_Mode.scrub);
    } else {
      services.player.changeVolume(delta * 0.04);
      _setMode(_Mode.volume);
    }
  }

  @override
  void onSelect() => _setMode(_mode == _Mode.scrub ? _Mode.progress : _Mode.scrub);

  @override
  void dispose() {
    _modeTimer?.cancel();
    super.dispose();
  }

  static String _fmt(Duration d) {
    final s = d.inSeconds;
    final h = s ~/ 3600;
    final m = (s % 3600) ~/ 60;
    final ss = (s % 60).toString().padLeft(2, '0');
    return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$ss' : '$m:$ss';
  }

  @override
  Widget build(BuildContext context) {
    final p = services.player;
    final t = p.current;
    if (t == null) {
      return const Center(child: Text('Nothing playing', style: TextStyle(color: LcdColors.sub)));
    }
    return LayoutBuilder(builder: (context, c) {
      final artSize = (c.maxWidth * 0.42).clamp(60.0, c.maxHeight * 0.62);
      return Padding(
        padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
        child: Column(children: [
          Text('${p.index + 1} of ${p.queue.length}',
              style: const TextStyle(fontSize: 12, color: LcdColors.text, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Expanded(
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _ReflectedArt(size: artSize, child: ArtImage(t.art, key: ValueKey(t.art?.key))),
              const SizedBox(width: 10),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(top: artSize * 0.18),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(t.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: LcdColors.text)),
                    const SizedBox(height: 4),
                    Text(t.displayArtist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 14, color: LcdColors.text)),
                    const SizedBox(height: 2),
                    Text(t.displayAlbum,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 14, color: LcdColors.text)),
                    if (p.lastError != null) ...[
                      const SizedBox(height: 6),
                      Text(p.lastError!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 11, color: Colors.red)),
                    ],
                  ]),
                ),
              ),
            ]),
          ),
          SizedBox(height: 34, child: _bottom()),
        ]),
      );
    });
  }

  Widget _bottom() {
    final p = services.player;
    if (_mode == _Mode.volume) {
      return Row(children: [
        const Icon(Icons.volume_mute_rounded, size: 18, color: LcdColors.text),
        const SizedBox(width: 4),
        Expanded(child: IPodBar(p.volume)),
        const SizedBox(width: 4),
        const Icon(Icons.volume_up_rounded, size: 18, color: LcdColors.text),
      ]);
    }
    return StreamBuilder<Duration>(
      stream: p.audio.positionStream,
      builder: (context, snap) {
        final pos = snap.data ?? Duration.zero;
        final dur = p.audio.duration ?? Duration.zero;
        final v = dur.inMilliseconds == 0 ? 0.0 : pos.inMilliseconds / dur.inMilliseconds;
        final remain = dur - pos;
        return Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          IPodBar(v, diamond: _mode == _Mode.scrub),
          const SizedBox(height: 3),
          Row(children: [
            Text(_fmt(pos), style: const TextStyle(fontSize: 11, color: LcdColors.text)),
            const Spacer(),
            Text('-${_fmt(remain.isNegative ? Duration.zero : remain)}',
                style: const TextStyle(fontSize: 11, color: LcdColors.text)),
          ]),
        ]);
      },
    );
  }
}

/// iPod classic の Now Playing のような反射付きアートワーク
class _ReflectedArt extends StatelessWidget {
  final double size;
  final Widget child;
  const _ReflectedArt({required this.size, required this.child});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      child: Column(children: [
        SizedBox(width: size, height: size, child: child),
        Flexible(
          child: ClipRect(
            child: SizedBox(
              height: size * 0.35,
              child: ShaderMask(
                shaderCallback: (r) => const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x55FFFFFF), Color(0x00FFFFFF)],
                ).createShader(r),
                blendMode: BlendMode.dstIn,
                child: OverflowBox(
                  alignment: Alignment.topCenter,
                  maxHeight: size,
                  child: Transform.flip(flipY: true, child: SizedBox(width: size, height: size, child: child)),
                ),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}
