import 'package:flutter/material.dart';

import '../app.dart';
import '../core/dsaudio.dart';
import '../core/series.dart';
import '../core/settings.dart';
import '../core/webdav.dart';

/// 接続先の設定。WebDAV（フォルダを直接スキャン）か DS audio（Audio Station の API）
Future<void> showServerDialog(BuildContext context) {
  final s = services.settings;
  var source = s.source;
  final url = TextEditingController(text: s.serverUrl.isEmpty ? 'http://' : s.serverUrl);
  final dsUrl = TextEditingController(text: s.dsUrl.isEmpty ? 'http://' : s.dsUrl);
  final user = TextEditingController(text: s.user);
  final pass = TextEditingController(text: s.password);
  final path = TextEditingController(text: s.musicPath);
  final otp = TextEditingController();
  var transcode = s.dsTranscode;
  String? result;
  bool testing = false;
  String? hubDid; // ハブから受け取ったデバイストークン
  final hub = Series.hub();

  return showDialog<void>(
    context: context,
    builder: (context) => StatefulBuilder(builder: (context, setState) {
      Future<void> apply() async {
        final changed = s.dsUrl != dsUrl.text.trim() || s.user != user.text.trim() || s.password != pass.text;
        s.source = source;
        s.serverUrl = url.text.trim() == 'http://' ? '' : url.text.trim();
        s.dsUrl = dsUrl.text.trim() == 'http://' ? '' : dsUrl.text.trim();
        s.user = user.text.trim();
        s.password = pass.text;
        s.musicPath = path.text.trim().isEmpty ? '/music' : path.text.trim();
        s.dsTranscode = transcode;
        if (changed) {
          s.dsDid = '';
          services.ds.reset();
        }
        if (hubDid != null) {
          s.dsDid = hubDid!;
          services.ds.reset();
        }
        if (otp.text.trim().isNotEmpty) services.ds.setOtp(otp.text);
        await s.save();
      }

      Future<void> test() async {
        setState(() {
          testing = true;
          result = null;
        });
        try {
          if (source == MusicSource.dsaudio) {
            await apply();
            final d = await services.ds.call('SYNO.AudioStation.Song', 'list', {'limit': '1', 'library': 'all'}, version: 3);
            result = 'OK: Audio Station ${d['total'] ?? 0} 曲';
          } else {
            final dav = WebDavClient(url.text, user.text, pass.text);
            try {
              final e = await dav.list(path.text.trim());
              final dirs = e.where((x) => x.isDir).length;
              result = 'OK: フォルダ $dirs / ファイル ${e.length - dirs}';
            } finally {
              dav.close();
            }
          }
        } on DsOtpException catch (e) {
          result = 'NG: $e';
        } catch (e) {
          result = 'NG: $e';
        }
        setState(() => testing = false);
      }

      final ds = source == MusicSource.dsaudio;
      return AlertDialog(
        title: const Text('接続先'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            // 同じ端末の Theta Home Hatch（設定のハブ）から NAS の設定を受け取る（spec THETA_SHARED_SETTINGS §4.0・§4.1）
            FutureBuilder<String>(
              future: hub,
              builder: (context, snap) {
                final h = snap.data ?? '';
                if (h.isEmpty) return const SizedBox.shrink();
                final name = h.endsWith('kidshome') ? 'Theta KidsHome Hatch' : 'Theta Home Hatch';
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.home_outlined),
                    label: Text('$name の NAS の設定を使う'),
                    onPressed: testing
                        ? null
                        : () async {
                            setState(() {
                              testing = true;
                              result = null;
                            });
                            try {
                              final info = await Series.info();
                              final nasUrl = info['nas.url'] ?? '';
                              if (nasUrl.isEmpty) throw Exception('$name に NAS が登録されていません');
                              final pw = await Series.secret('nas.password');
                              var did = '';
                              try {
                                did = await Series.secret('nas.deviceToken');
                              } catch (_) {}
                              // ハブの nas.url は DSM の URL なので DS audio で使う（WebDAV にも切り替えられる）
                              source = MusicSource.dsaudio;
                              dsUrl.text = nasUrl;
                              if ((info['nas.user'] ?? '').isNotEmpty) user.text = info['nas.user']!;
                              if (pw.isNotEmpty) pass.text = pw;
                              hubDid = did;
                              result = 'OK: $name から受け取りました（保存で反映）';
                            } catch (e) {
                              result = 'NG: $e';
                            }
                            setState(() => testing = false);
                          },
                  ),
                );
              },
            ),
            SegmentedButton<MusicSource>(
              segments: const [
                ButtonSegment(value: MusicSource.webdav, label: Text('WebDAV')),
                ButtonSegment(value: MusicSource.dsaudio, label: Text('DS audio')),
              ],
              selected: {source},
              onSelectionChanged: (v) => setState(() {
                source = v.first;
                result = null;
              }),
            ),
            const SizedBox(height: 4),
            Text(
              ds
                  ? 'Audio Station の API で曲の一覧と再生を行います（スキャン不要・タグは NAS 側のもの）。'
                  : 'NAS のフォルダを WebDAV で直接スキャンします（Audio Station 不要）。',
              style: const TextStyle(fontSize: 12),
            ),
            if (ds)
              TextField(
                controller: dsUrl,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                  labelText: 'DSM の URL',
                  hintText: 'http://nas.tailXXXX.ts.net:5000',
                  helperText: 'ポートを省くと http:5000 を使います',
                ),
              )
            else
              TextField(
                controller: url,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                  labelText: 'WebDAV の URL',
                  hintText: 'http://nas.tailXXXX.ts.net:5005',
                  helperText: 'Tailscale の IP(100.x.x.x) か MagicDNS 名',
                ),
              ),
            TextField(controller: user, decoration: const InputDecoration(labelText: 'ユーザー名')),
            TextField(controller: pass, obscureText: true, decoration: const InputDecoration(labelText: 'パスワード')),
            if (!ds)
              TextField(
                controller: path,
                decoration: const InputDecoration(labelText: 'Music フォルダ', hintText: '/music'),
              ),
            if (ds) ...[
              TextField(
                controller: otp,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: '2 段階認証コード（必要なときだけ）',
                  helperText: s.dsDid.isNotEmpty ? 'この端末は登録済み（コード不要）' : '1 回入れれば次から要りません',
                ),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('MP3 に変換して受け取る', style: TextStyle(fontSize: 14)),
                subtitle: const Text('回線が細いとき・端末で再生できない形式のとき', style: TextStyle(fontSize: 11)),
                value: transcode,
                onChanged: (v) => setState(() => transcode = v),
              ),
            ],
            const SizedBox(height: 12),
            if (testing) const LinearProgressIndicator(),
            if (result != null)
              Text(result!, style: TextStyle(color: result!.startsWith('OK') ? Colors.green : Colors.red)),
            if (source != s.source || (ds && services.library.tracks.isNotEmpty && services.library.tracks.first.id.isEmpty) ||
                (!ds && services.library.tracks.isNotEmpty && services.library.tracks.first.id.isNotEmpty))
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text('接続方式を変えたら、ライブラリを更新してください。', style: TextStyle(fontSize: 12)),
              ),
          ]),
        ),
        actions: [
          TextButton(onPressed: testing ? null : test, child: const Text('接続テスト')),
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('キャンセル')),
          FilledButton(
            onPressed: () async {
              await apply();
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('保存'),
          ),
        ],
      );
    }),
  );
}

Future<void> showObsidianDialog(BuildContext context) {
  final s = services.settings;
  final path = TextEditingController(text: s.obsidianPath);
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Obsidian 書き出し先'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(
          controller: path,
          decoration: const InputDecoration(
            labelText: 'NAS 上のフォルダ',
            hintText: '/home/Obsidian/MyVault/Music',
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Vault 内のフォルダを指定してください（共有フォルダから書く。例 /home/Obsidian/MyVault/Music）。'
          'WebDAV のときは WebDAV で、DS audio のときは File Station で書き込みます。'
          'Albums/ と Artists/ にノートを作成します。'
          'ノートに追記したメモは再書き出し時も保持されます。',
          style: TextStyle(fontSize: 12),
        ),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('キャンセル')),
        FilledButton(
          onPressed: () async {
            s.obsidianPath = path.text.trim();
            await s.save();
            if (context.mounted) Navigator.pop(context);
          },
          child: const Text('保存'),
        ),
      ],
    ),
  );
}

/// 文字で検索（音声入力が使えないとき・iPod の Search → Type）
Future<String?> showTextSearchDialog(BuildContext context) {
  final c = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('検索'),
      content: TextField(
        controller: c,
        autofocus: true,
        textInputAction: TextInputAction.search,
        onSubmitted: (v) => Navigator.pop(context, v),
        decoration: const InputDecoration(hintText: '曲名・アルバム・アーティスト（「〜をかけて」で再生）'),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('キャンセル')),
        FilledButton(onPressed: () => Navigator.pop(context, c.text), child: const Text('検索')),
      ],
    ),
  );
}
