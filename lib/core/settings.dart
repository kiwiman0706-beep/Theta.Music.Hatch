import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'webdav.dart';

enum RepeatSetting { off, one, all }

/// 曲の取得元。webdav: NAS のフォルダを直接スキャン / dsaudio: Synology Audio Station の API
enum MusicSource { webdav, dsaudio }

class AppSettings extends ChangeNotifier {
  late SharedPreferences _p;

  String serverUrl = '';
  String user = '';
  String password = '';
  String musicPath = '/music';
  String obsidianPath = '';
  bool readTags = true;
  bool clicker = true; // iPod のカリカリ音
  bool haptics = true; // ホイールの振動
  bool blackBody = false;
  bool shuffle = false;
  RepeatSetting repeat = RepeatSetting.off;

  MusicSource source = MusicSource.webdav;
  String dsUrl = ''; // 例: http://nas.tailXXXX.ts.net:5000
  String dsDid = ''; // 2 段階認証のデバイストークン
  bool dsTranscode = false; // Audio Station で MP3 に変換して受け取る（回線が細いとき・非対応形式）
  /// DS audio のとき、曲のお気に入りを Audio Station の★評価と同期する。
  /// この★数以上をお気に入りとみなす（0 なら同期しない）。登録すると★5、外すと★0 にする
  int dsFavRating = 4;

  /// Theta Home の「棚」に出すもの（お気に入り・最近再生したアルバム）
  bool shelfFavorites = true;
  bool shelfRecent = true;

  /// 見た目: ipod（クリックホイール） / theta（ThetaHomeHatch の HUD）
  String skin = 'ipod';

  /// theta スキンのテーマ: dark / light / pop / alert / scifi / system
  String hudTheme = 'dark';

  Future<void> load() async {
    _p = await SharedPreferences.getInstance();
    serverUrl = _p.getString('serverUrl') ?? '';
    user = _p.getString('user') ?? '';
    password = _p.getString('password') ?? '';
    musicPath = _p.getString('musicPath') ?? '/music';
    obsidianPath = _p.getString('obsidianPath') ?? '';
    readTags = _p.getBool('readTags') ?? true;
    clicker = _p.getBool('clicker') ?? true;
    haptics = _p.getBool('haptics') ?? true;
    dsFavRating = _p.getInt('dsFavRating') ?? 4;
    shelfFavorites = _p.getBool('shelfFavorites') ?? true;
    shelfRecent = _p.getBool('shelfRecent') ?? true;
    blackBody = _p.getBool('blackBody') ?? false;
    shuffle = _p.getBool('shuffle') ?? false;
    repeat = RepeatSetting.values[(_p.getInt('repeat') ?? 0).clamp(0, 2)];
    source = MusicSource.values[(_p.getInt('source') ?? 0).clamp(0, 1)];
    dsUrl = _p.getString('dsUrl') ?? '';
    dsDid = _p.getString('dsDid') ?? '';
    dsTranscode = _p.getBool('dsTranscode') ?? false;
    skin = _p.getString('skin') ?? 'ipod';
    hudTheme = _p.getString('hudTheme') ?? 'dark';
  }

  bool get configured => source == MusicSource.dsaudio ? dsUrl.isNotEmpty : serverUrl.isNotEmpty;

  WebDavClient client() => WebDavClient(serverUrl, user, password);

  Future<void> save() async {
    await _p.setString('serverUrl', serverUrl);
    await _p.setString('user', user);
    await _p.setString('password', password);
    await _p.setString('musicPath', musicPath);
    await _p.setString('obsidianPath', obsidianPath);
    await _p.setBool('readTags', readTags);
    await _p.setBool('clicker', clicker);
    await _p.setBool('haptics', haptics);
    await _p.setInt('dsFavRating', dsFavRating);
    await _p.setBool('shelfFavorites', shelfFavorites);
    await _p.setBool('shelfRecent', shelfRecent);
    await _p.setBool('blackBody', blackBody);
    await _p.setBool('shuffle', shuffle);
    await _p.setInt('repeat', repeat.index);
    await _p.setInt('source', source.index);
    await _p.setString('dsUrl', dsUrl);
    await _p.setString('dsDid', dsDid);
    await _p.setBool('dsTranscode', dsTranscode);
    await _p.setString('skin', skin);
    await _p.setString('hudTheme', hudTheme);
    notifyListeners();
  }
}
