import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'webdav.dart';

enum RepeatSetting { off, one, all }

class AppSettings extends ChangeNotifier {
  late SharedPreferences _p;

  String serverUrl = '';
  String user = '';
  String password = '';
  String musicPath = '/music';
  String obsidianPath = '';
  bool readTags = true;
  bool clicker = true;
  bool blackBody = false;
  bool shuffle = false;
  RepeatSetting repeat = RepeatSetting.off;

  Future<void> load() async {
    _p = await SharedPreferences.getInstance();
    serverUrl = _p.getString('serverUrl') ?? '';
    user = _p.getString('user') ?? '';
    password = _p.getString('password') ?? '';
    musicPath = _p.getString('musicPath') ?? '/music';
    obsidianPath = _p.getString('obsidianPath') ?? '';
    readTags = _p.getBool('readTags') ?? true;
    clicker = _p.getBool('clicker') ?? true;
    blackBody = _p.getBool('blackBody') ?? false;
    shuffle = _p.getBool('shuffle') ?? false;
    repeat = RepeatSetting.values[(_p.getInt('repeat') ?? 0).clamp(0, 2)];
  }

  bool get configured => serverUrl.isNotEmpty;

  WebDavClient client() => WebDavClient(serverUrl, user, password);

  Future<void> save() async {
    await _p.setString('serverUrl', serverUrl);
    await _p.setString('user', user);
    await _p.setString('password', password);
    await _p.setString('musicPath', musicPath);
    await _p.setString('obsidianPath', obsidianPath);
    await _p.setBool('readTags', readTags);
    await _p.setBool('clicker', clicker);
    await _p.setBool('blackBody', blackBody);
    await _p.setBool('shuffle', shuffle);
    await _p.setInt('repeat', repeat.index);
    notifyListeners();
  }
}
