# Theta Music

Tailscale 経由で NAS の Music フォルダを直接再生する、iPod classic 風 UI の Android 音楽プレーヤー（Flutter）。

## 仕組み

```
スマホ (Tailscale VPN ON)
  └─ Theta Music ── WebDAV (HTTP) ──> NAS (Tailscale IP / MagicDNS)
                                       └─ /music/Artist/Album/*.flac ...
```

- **接続**: NAS の WebDAV（Synology なら「WebDAV Server」パッケージ、HTTP 5005 / HTTPS 5006）。
  Tailscale がトンネルを暗号化するので HTTP でも通信内容は保護されます。
- **再生**: just_audio (ExoPlayer) で NAS から直接ストリーミング。バックグラウンド再生・ロック画面操作対応。
  通信が切れた場合は同じ位置から最大 3 回自動で再接続。
- **ライブラリ**: アプリ内で独自スキャン → 端末内 `library.json` にキャッシュ。
  - フォルダを PROPFIND で巡回し、各ファイルのタグ部分だけ Range 取得して読む（ファイル全体はダウンロードしない）
  - 対応タグ: MP3 (ID3v1/v2.2–2.4, Shift_JIS 自動判定), FLAC (Vorbis Comment), M4A/AAC (iTunes タグ)
  - タグが無い場合はフォルダ構成 `Artist/Album/01 Title.ext`（`Disc 1/` 等も考慮）から推測
  - アート: 埋め込み画像（Range 取得）か `cover.jpg` / `folder.jpg` 等
  - 2 回目以降は**差分スキャン**（サイズ・更新日時が変わったファイルだけ読み直し）
- **Obsidian 連携**: Library → Export to Obsidian で、NAS 上の Vault フォルダに Markdown を書き出し
  - `Albums/<Artist> - <Album>.md`（frontmatter: artist/album/year/genre/tracks + 曲リスト表）
  - `Artists/<Artist>.md`（アルバムへの `[[wikilink]]`）
  - `Music Library.md`（Dataview クエリ付きインデックス）
  - 再書き出ししても、自動生成区間の外に書いたメモや frontmatter に追加した独自キー（`rating:` など）は保持

## 操作（クリックホイール）

| 操作 | 動作 |
|---|---|
| リングをなぞる | スクロール（Now Playing では音量） |
| 中央ボタン | 決定（Now Playing ではシークモード切替） |
| MENU | 戻る（Android の戻るボタンでも可） |
| ▶❚❚ | 再生/一時停止 |
| ◀◀ / ▶▶ | 前/次の曲、長押しで巻き戻し/早送り |

リストの項目は直接タップでも選択できます。

## セットアップ

1. NAS: WebDAV を有効化（Synology: パッケージセンター → WebDAV Server → HTTP 5005 を有効）
2. スマホ: Tailscale アプリで VPN を ON
3. APK をインストールして起動 → サーバー設定
   - URL: `http://<NASのTailscale IP または MagicDNS名>:5005`
   - Music フォルダ: `/music`（共有フォルダ名）
   - 「接続テスト」で OK を確認
4. Library → Update Library でスキャン

## ビルド

```bash
flutter pub get
flutter build apk --release   # build/app/outputs/flutter-apk/app-release.apk
```

GitHub Actions（`.github/workflows/build-apk.yml`）でも push ごとに APK をビルドし、Artifacts に保存します。

署名: `android/key.properties`（Git 管理外）があればその鍵、無ければデバッグ鍵で署名します。
ビルド環境ごとにデバッグ鍵が違うため、別環境でビルドした APK に入れ替える際はアンインストールが必要です。
固定したい場合は自分の PC で鍵を作り `key.properties` を置いてください:

```properties
storeFile=/path/to/theta.jks
storePassword=...
keyAlias=theta
keyPassword=...
```

## 結合テスト（任意）

```bash
pip install wsgidav cheroot
# /music と /vault を公開する WebDAV を立ててから
DAV_URL=http://127.0.0.1:8765 DAV_USER=u DAV_PASS=p flutter test test/dav_integration_test.dart
```
