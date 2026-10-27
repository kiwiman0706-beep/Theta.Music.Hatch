import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

import 'models.dart';
import 'settings.dart';

/// アルバムアートを NAS から取得し、端末内にキャッシュする
class ArtCache {
  final AppSettings settings;
  ArtCache(this.settings);

  final Map<String, Uint8List?> _mem = {};
  final Map<String, Future<Uint8List?>> _inflight = {};
  Directory? _dir;

  Future<Directory> _cacheDir() async {
    if (_dir != null) return _dir!;
    final d = Directory('${(await getApplicationCacheDirectory()).path}/art');
    await d.create(recursive: true);
    return _dir = d;
  }

  Future<File> fileFor(ArtRef ref) async =>
      File('${(await _cacheDir()).path}/${md5.convert(utf8.encode(ref.key))}.img');

  Uint8List? peek(ArtRef ref) => _mem[ref.key];

  Future<Uint8List?> load(ArtRef ref) {
    if (_mem.containsKey(ref.key)) return Future.value(_mem[ref.key]);
    return _inflight[ref.key] ??= _load(ref).whenComplete(() => _inflight.remove(ref.key));
  }

  Future<Uint8List?> _load(ArtRef ref) async {
    Uint8List? data;
    try {
      final f = await fileFor(ref);
      if (await f.exists()) {
        data = await f.readAsBytes();
      } else {
        final dav = settings.client();
        try {
          if (ref.embedded) {
            if (ref.length > 8 * 1024 * 1024) return null;
            data = await dav.readRange(ref.path, ref.offset, ref.length);
          } else {
            data = await dav.getBytes(ref.path);
          }
        } finally {
          dav.close();
        }
        await f.writeAsBytes(data);
      }
    } catch (_) {
      data = null;
    }
    if (_mem.length > 200) _mem.remove(_mem.keys.first);
    _mem[ref.key] = data;
    return data;
  }

  /// 通知領域用にファイルとして用意（キャッシュ済みのときだけ）
  Future<Uri?> fileUriIfCached(ArtRef? ref) async {
    if (ref == null) return null;
    final f = await fileFor(ref);
    return await f.exists() ? f.uri : null;
  }
}
