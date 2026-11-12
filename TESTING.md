# 確かめたこと・まだのこと

## 確かめたこと（この環境で）

- `flutter analyze`・`flutter test`（検索・音声コマンドの解釈・お気に入り・棚の中身・Obsidian のマージ）
- WebDAV（wsgidav）での結合テスト：スキャン・タグ（MP3/FLAC/M4A/Shift_JIS）・Theta Vault への書き出し（`.base`・`.theta/vault.json`・`id`）・Vault からのお気に入りの復元
- DSM の真似（`test/fake_dsm.py`）での結合テスト：ログイン（2 段階認証→デバイストークン）・全曲の取得・ストリーム・カバー・★評価の往復・File Station での書き出し
- 本番の鍵（仮の鍵で代用）で APK を作ると、権限 `app.thetahatch.permission.SHARE` の定義が入り、デバッグ鍵では入らないこと
- 画面（Web で描いたスクリーンショット）：iPod・Theta の各画面

## 実機で未確認

- 再生・バックグラウンド再生・ロック画面の操作
- 本物の Synology（Audio Station・File Station）での動作。fake_dsm と細部が違うかもしれない
- 音声検索（Android の音声入力画面）
- クリック音（SoundPool。メディア音量で鳴るか）
- ハブ（Theta Home Hatch）から：スキン・NAS の設定・パスワード・デバイストークンの受け取り（デバイストークンを別アプリで使い回せるかは Synology 次第）
- 「更新する」でハブの更新画面が開く／ハブが無ければ Releases が開く
- Theta Home の棚：お気に入り・最近再生のジャケットが並び、押すと再生する
- パスワード・デバイストークンの暗号化保存（前の版の平文からの移し替え）
- 11 種のスキンの見た目（Flutter の Web 版で確かめたのは dark・light・pop・alert・scifi まで）
