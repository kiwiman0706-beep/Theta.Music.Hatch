import 'package:flutter/material.dart';

import '../app.dart';
import '../core/webdav.dart';

Future<void> showServerDialog(BuildContext context) {
  final s = services.settings;
  final url = TextEditingController(text: s.serverUrl.isEmpty ? 'http://' : s.serverUrl);
  final user = TextEditingController(text: s.user);
  final pass = TextEditingController(text: s.password);
  final path = TextEditingController(text: s.musicPath);
  String? result;
  bool testing = false;

  return showDialog<void>(
    context: context,
    builder: (context) => StatefulBuilder(builder: (context, setState) {
      Future<void> test() async {
        setState(() {
          testing = true;
          result = null;
        });
        final dav = WebDavClient(url.text, user.text, pass.text);
        try {
          final e = await dav.list(path.text.trim());
          final dirs = e.where((x) => x.isDir).length;
          result = 'OK: フォルダ $dirs / ファイル ${e.length - dirs}';
        } catch (e) {
          result = 'NG: $e';
        } finally {
          dav.close();
        }
        setState(() => testing = false);
      }

      return AlertDialog(
        title: const Text('NAS サーバー (WebDAV)'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: url,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: 'サーバー URL',
                hintText: 'http://nas.tailXXXX.ts.net:5005',
                helperText: 'Tailscale の IP(100.x.x.x) か MagicDNS 名',
              ),
            ),
            TextField(controller: user, decoration: const InputDecoration(labelText: 'ユーザー名')),
            TextField(controller: pass, obscureText: true, decoration: const InputDecoration(labelText: 'パスワード')),
            TextField(
              controller: path,
              decoration: const InputDecoration(labelText: 'Music フォルダ', hintText: '/music'),
            ),
            const SizedBox(height: 12),
            if (testing) const LinearProgressIndicator(),
            if (result != null)
              Text(result!, style: TextStyle(color: result!.startsWith('OK') ? Colors.green : Colors.red)),
          ]),
        ),
        actions: [
          TextButton(onPressed: testing ? null : test, child: const Text('接続テスト')),
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('キャンセル')),
          FilledButton(
            onPressed: () async {
              s.serverUrl = url.text.trim();
              s.user = user.text.trim();
              s.password = pass.text;
              s.musicPath = path.text.trim().isEmpty ? '/music' : path.text.trim();
              await s.save();
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
            labelText: 'NAS 上のフォルダ (WebDAV パス)',
            hintText: '/home/Obsidian/MyVault/Music',
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Vault 内のフォルダを指定してください。Albums/ と Artists/ にノートを作成します。'
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
