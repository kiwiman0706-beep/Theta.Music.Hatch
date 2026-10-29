import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'note_store.dart';
import 'settings.dart';

class DsException implements Exception {
  final String message;
  final int code;
  DsException(this.message, [this.code = 0]);
  @override
  String toString() => message;
}

/// 2 段階認証のコードが要る（または違う）
class DsOtpException extends DsException {
  DsOtpException(super.message, [super.code]);
}

/// 1 曲分（Audio Station の SYNO.AudioStation.Song から）
class DsSong {
  final String id, path, title, artist, albumArtist, album, genre;
  final int year, track, disc, size;
  final int rating; // Audio Station / DS audio の評価（0〜5）
  DsSong(this.id, this.path, this.title, this.artist, this.albumArtist, this.album, this.genre, this.year,
      this.track, this.disc, this.size, [this.rating = 0]);
}

/// Synology Audio Station（DS audio と同じ Web API）のクライアント。
/// ThetaHomeHatch の Nas と同じ手順: SYNO.API.Info で API の場所を調べる → SYNO.API.Auth でログイン。
/// 2 段階認証は初回だけコードを入れ、以後はデバイストークン（did）で通す。
/// Obsidian の書き出しには File Station（Upload / Download / CreateFolder）を使う。
class DsAudioClient implements NoteStore {
  final AppSettings settings;
  final http.Client _c = http.Client();
  Map<String, dynamic>? _apis;
  String? _sid;
  String? _otp;
  Future<void>? _logging;

  DsAudioClient(this.settings);

  /// 「100.1.2.3」のように方式を省いたときは DSM の既定（http, 5000）を補う
  static String normalize(String url) {
    var u = url.trim();
    while (u.endsWith('/')) {
      u = u.substring(0, u.length - 1);
    }
    if (u.isEmpty) return u;
    if (!u.startsWith('http://') && !u.startsWith('https://')) {
      final slash = u.indexOf('/');
      final host = slash < 0 ? u : u.substring(0, slash);
      final rest = slash < 0 ? '' : u.substring(slash);
      u = 'http://$host${host.contains(':') ? '' : ':5000'}$rest';
    }
    return u;
  }

  String get base => normalize(settings.dsUrl);

  /// 次のログインで 1 回だけ使う 2 段階認証コード
  void setOtp(String? code) {
    _otp = (code == null || code.trim().isEmpty) ? null : code.trim();
    if (_otp != null) _sid = null;
  }

  /// 接続先やアカウントを変えたときに呼ぶ
  void reset() {
    _sid = null;
    _apis = null;
  }

  Future<Map<String, dynamic>> _postJson(String url, Map<String, String> form, {Duration? timeout}) async {
    final res = await _c.post(Uri.parse(url), body: form).timeout(timeout ?? const Duration(seconds: 20));
    if (res.statusCode != 200) throw DsException('DSM HTTP ${res.statusCode}');
    try {
      return jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    } catch (_) {
      throw DsException('DSM の応答ではありません');
    }
  }

  Map<String, dynamic> _api(String name) {
    final a = _apis?[name];
    if (a is! Map<String, dynamic>) throw DsException('$name が使えません（Audio Station は入っていますか？）');
    return a;
  }

  int _ver(String name, int want) {
    final a = _api(name);
    final max = a['maxVersion'] as int? ?? want;
    final min = a['minVersion'] as int? ?? 1;
    return want.clamp(min, max);
  }

  String _url(String name) => '$base/webapi/${_api(name)['path'] ?? 'entry.cgi'}';

  Future<void> ensureLogin() {
    if (_sid != null) return Future.value();
    return _logging ??= _login().whenComplete(() => _logging = null);
  }

  Future<void> _login() async {
    if (base.isEmpty) throw DsException('DS audio の URL が未設定です');
    const q = {'api': 'SYNO.API.Info', 'version': '1', 'method': 'query', 'query': 'all'};
    Map<String, dynamic> info;
    try {
      info = await _postJson('$base/webapi/query.cgi', q, timeout: const Duration(seconds: 8));
    } on DsException {
      info = await _postJson('$base/webapi/entry.cgi', q, timeout: const Duration(seconds: 8));
    }
    _apis = info['data'] as Map<String, dynamic>?;
    if (_apis == null || !_apis!.containsKey('SYNO.API.Auth')) throw DsException('DSM の応答ではありません');
    if (settings.password.isEmpty) throw DsException('パスワード未設定');
    final did = settings.dsDid;
    final twoStep = _otp != null || did.isNotEmpty;
    final p = <String, String>{
      'api': 'SYNO.API.Auth',
      'version': '${_ver('SYNO.API.Auth', twoStep ? 6 : 3)}',
      'method': 'login',
      'account': settings.user,
      'passwd': settings.password,
      'session': 'AudioStation',
      'format': 'sid',
    };
    if (_otp != null) {
      p['otp_code'] = _otp!;
      p['enable_device_token'] = 'yes';
      p['device_name'] = 'ThetaMusicHatch';
    } else if (did.isNotEmpty) {
      p['device_id'] = did;
      p['device_name'] = 'ThetaMusicHatch';
    }
    _otp = null;
    final r = await _postJson(_url('SYNO.API.Auth'), p);
    if (r['success'] != true) {
      final code = (r['error'] as Map?)?['code'] as int? ?? 0;
      if (code == 403 || code == 406) {
        settings.dsDid = '';
        await settings.save();
        throw DsOtpException('2 段階認証のコードを入れてください（1 回入れれば、この端末は次から要りません）', code);
      }
      if (code == 404) throw DsOtpException('2 段階認証のコードが違います', code);
      throw DsException(
          switch (code) {
            400 => 'アカウントかパスワードが違います',
            401 => 'アカウントが無効です',
            402 => 'Audio Station を使う権限がありません',
            407 => 'ログインの失敗が続いたため、NAS が一時的に拒否しています',
            _ => 'ログインエラー $code',
          },
          code);
    }
    final data = r['data'] as Map<String, dynamic>;
    _sid = data['sid'] as String;
    final newDid = (data['did'] ?? data['device_id'] ?? '') as String;
    if (newDid.isNotEmpty && newDid != settings.dsDid) {
      settings.dsDid = newDid;
      await settings.save();
    }
  }

  /// API を呼ぶ。セッション切れ（105〜107・119）なら 1 回だけログインし直す
  Future<Map<String, dynamic>> call(String api, String method, Map<String, String> params, {int version = 2}) async {
    for (var attempt = 0;; attempt++) {
      await ensureLogin();
      final p = {
        ...params,
        'api': api,
        'version': '${_ver(api, version)}',
        'method': method,
        '_sid': _sid!,
      };
      final r = await _postJson(_url(api), p, timeout: const Duration(seconds: 60));
      if (r['success'] == true) return (r['data'] as Map<String, dynamic>?) ?? {};
      final code = (r['error'] as Map?)?['code'] as int? ?? 0;
      if (attempt == 0 && (code == 105 || code == 106 || code == 107 || code == 119)) {
        _sid = null;
        continue;
      }
      throw DsException('DSM エラー $code ($api.$method)', code);
    }
  }

  /// 全曲（タグ付き）を取得
  Future<List<DsSong>> listSongs({void Function(int done, int total)? progress, bool Function()? cancelled}) async {
    const page = 1000;
    final out = <DsSong>[];
    var total = -1;
    for (var offset = 0; total < 0 || offset < total; offset += page) {
      if (cancelled?.call() ?? false) break;
      final d = await call('SYNO.AudioStation.Song', 'list', {
        'library': 'all',
        'offset': '$offset',
        'limit': '$page',
        'additional': 'song_tag,song_audio,song_rating',
        'sort_by': 'title',
        'sort_direction': 'ASC',
      }, version: 3);
      total = d['total'] as int? ?? 0;
      final songs = (d['songs'] as List?) ?? const [];
      for (final s in songs.cast<Map<String, dynamic>>()) {
        final add = (s['additional'] as Map<String, dynamic>?) ?? const {};
        final tag = (add['song_tag'] as Map<String, dynamic>?) ?? const {};
        final audio = (add['song_audio'] as Map<String, dynamic>?) ?? const {};
        final rating = (add['song_rating'] as Map<String, dynamic>?) ?? const {};
        int n(Object? v) => v is int ? v : int.tryParse('${v ?? ''}') ?? 0;
        String t(Object? v) => (v ?? '').toString().trim();
        out.add(DsSong(
          t(s['id']),
          t(s['path']),
          t(s['title']),
          t(tag['artist']),
          t(tag['album_artist']),
          t(tag['album']),
          t(tag['genre']),
          n(tag['year']),
          n(tag['track']),
          n(tag['disc']),
          n(audio['filesize']),
          n(rating['rating']),
        ));
      }
      progress?.call(out.length, total);
      if (songs.isEmpty) break;
    }
    return out;
  }

  /// 曲の評価（0〜5）を設定。DS audio・Audio Station の★評価と同じもの
  Future<void> setRating(String id, int rating) async {
    await call('SYNO.AudioStation.Song', 'setrating', {'id': id, 'rating': '${rating.clamp(0, 5)}'}, version: 3);
  }

  /// 再生用の URL（セッション ID を含む）
  Future<Uri> streamUri(String id, String ext) async {
    await ensureLogin();
    const api = 'SYNO.AudioStation.Stream';
    final transcode = settings.dsTranscode;
    final e = transcode ? 'mp3' : (ext.isEmpty ? 'mp3' : ext);
    return Uri.parse('${_url(api)}/0.$e').replace(queryParameters: {
      'api': api,
      'version': '${_ver(api, 2)}',
      'method': transcode ? 'transcode' : 'stream',
      if (transcode) 'format': 'mp3',
      'id': id,
      '_sid': _sid!,
    });
  }

  /// 曲のカバー画像（無ければ null）
  Future<Uint8List?> cover(String id) async {
    await ensureLogin();
    const api = 'SYNO.AudioStation.Cover';
    final uri = Uri.parse(_url(api)).replace(queryParameters: {
      'api': api,
      'version': '${_ver(api, 3)}',
      'method': 'getsongcover',
      'id': id,
      '_sid': _sid!,
    });
    final res = await _c.get(uri).timeout(const Duration(seconds: 30));
    final type = res.headers['content-type'] ?? '';
    if (res.statusCode != 200 || !type.startsWith('image/')) return null;
    return res.bodyBytes;
  }

  // ------------------------------------------------ File Station（Obsidian 書き出し用）

  @override
  Future<String?> getText(String path) async {
    await ensureLogin();
    const api = 'SYNO.FileStation.Download';
    final res = await _c.post(Uri.parse(_url(api)), body: {
      'api': api,
      'version': '${_ver(api, 2)}',
      'method': 'download',
      'path': jsonEncode([path]),
      'mode': 'download',
      '_sid': _sid!,
    }).timeout(const Duration(seconds: 30));
    final type = res.headers['content-type'] ?? '';
    if (type.startsWith('application/json')) {
      final r = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      final code = (r['error'] as Map?)?['code'] as int? ?? 0;
      if (code == 408) return null; // そのファイルは無い
      throw DsException('ダウンロードエラー $code: $path', code);
    }
    if (res.statusCode == 404) return null;
    if (res.statusCode != 200) throw DsException('ダウンロード HTTP ${res.statusCode}: $path');
    return utf8.decode(res.bodyBytes, allowMalformed: true);
  }

  @override
  Future<void> putText(String path, String text) async {
    await ensureLogin();
    const api = 'SYNO.FileStation.Upload';
    final slash = path.lastIndexOf('/');
    final dir = path.substring(0, slash);
    final name = path.substring(slash + 1);
    final uri = Uri.parse(_url(api)).replace(queryParameters: {'_sid': _sid!});
    final req = http.MultipartRequest('POST', uri)
      ..fields.addAll({
        'api': api,
        'version': '2',
        'method': 'upload',
        'path': dir,
        'create_parents': 'true',
        'overwrite': 'true',
      })
      ..files.add(http.MultipartFile.fromBytes('file', utf8.encode(text), filename: name));
    final res = await http.Response.fromStream(await _c.send(req).timeout(const Duration(seconds: 60)));
    Map<String, dynamic>? r;
    try {
      r = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    } catch (_) {}
    if (r?['success'] != true) {
      throw DsException('アップロードエラー ${(r?['error'] as Map?)?['code'] ?? res.statusCode}: $path');
    }
  }

  @override
  Future<void> mkdirs(String path) async {
    final p = path.replaceAll(RegExp(r'/+$'), '');
    final slash = p.lastIndexOf('/');
    if (slash <= 0) return; // 共有フォルダそのもの
    await call('SYNO.FileStation.CreateFolder', 'create', {
      'folder_path': jsonEncode([p.substring(0, slash)]),
      'name': jsonEncode([p.substring(slash + 1)]),
      'force_parent': 'true',
    });
  }

  /// 共有のクライアントなので閉じない
  @override
  void close() {}
}
