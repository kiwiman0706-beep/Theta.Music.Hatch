# Theta Music

Tailscale 経由で NAS の音楽を再生する Android 音楽プレーヤー（Flutter）。
見た目は **iPod classic 風（クリックホイール）** と **ThetaHomeHatch 風（HUD・右端の縦タブ）** を切り替えられます。

## 仕組み

```
スマホ (Tailscale VPN ON)
  └─ Theta Music ── WebDAV (HTTP) ──> NAS (Tailscale IP / MagicDNS)
                                       └─ /music/Artist/Album/*.flac ...
```

- **接続**（設定で切り替え）
  - **WebDAV**: NAS のフォルダを直接スキャン（Synology なら「WebDAV Server」パッケージ、HTTP 5005）。Audio Station 不要
  - **DS audio**: Synology Audio Station の Web API（DS audio と同じ `SYNO.AudioStation.*`）で曲の一覧・再生・カバーを取得。
    スキャン不要で、タグは NAS 側のもの。ログインは ThetaHomeHatch と同じ手順（`SYNO.API.Info` → `SYNO.API.Auth`、
    2 段階認証は初回だけコード入力 → デバイストークンで次から不要）。必要なら MP3 に変換して受け取れます
  - Tailscale がトンネルを暗号化するので HTTP でも通信内容は保護されます
- **再生**: just_audio (ExoPlayer) で NAS から直接ストリーミング。バックグラウンド再生・ロック画面操作対応。
  通信が切れた場合は同じ位置から最大 3 回自動で再接続。
- **ライブラリ**: アプリ内で独自スキャン → 端末内 `library.json` にキャッシュ。
  - フォルダを PROPFIND で巡回し、各ファイルのタグ部分だけ Range 取得して読む（ファイル全体はダウンロードしない）
  - 対応タグ: MP3 (ID3v1/v2.2–2.4, Shift_JIS 自動判定), FLAC (Vorbis Comment), M4A/AAC (iTunes タグ)
  - タグが無い場合はフォルダ構成 `Artist/Album/01 Title.ext`（`Disc 1/` 等も考慮）から推測
  - アート: 埋め込み画像（Range 取得）か `cover.jpg` / `folder.jpg` 等
  - 2 回目以降は**差分スキャン**（サイズ・更新日時が変わったファイルだけ読み直し）
- **Obsidian 連携**: Library → Export to Obsidian で、NAS 上の Vault フォルダに Markdown を書き出し
  （WebDAV のときは WebDAV、DS audio のときは File Station API で書き込み）
  - `Albums/<Artist> - <Album>.md`（frontmatter: artist/album/year/genre/tracks + 曲リスト表）
  - `Artists/<Artist>.md`（アルバムへの `[[wikilink]]`）
  - `Music Library.md`（Dataview クエリ付きインデックス）
  - 再書き出ししても、自動生成区間の外に書いたメモや frontmatter に追加した独自キー（`rating:` など）は保持

## お気に入り・音声検索

- **お気に入り**：曲・アルバム・アーティストを ★ で登録（端末内の `favorites.json`。ライブラリを更新しても、
  WebDAV / DS audio を切り替えても同じ曲なら残る）。お気に入りだけを通しで再生・シャッフルもできる。
  Obsidian に書き出すと `favorite: true` と `#music/favorite` が付き、曲の表には ★ が付く
  - **DS audio のときの曲は、Audio Station / DS audio の★評価と同期**（`SYNO.AudioStation.Song` の `setrating`）。
    ★4 以上をお気に入りとみなし、登録すると★5、外すと★0 を NAS に書く（しきい値は ★3+ / ★4+ / ★5 / 同期しない から選べる）。
    DS audio や Audio Station で付けた評価もそのまま反映される。アルバム・アーティストは端末内だけ
    （Audio Station のピン留め API は一覧の取得しか確認できていないため）
- **音声検索**：Android の音声入力（Google の音声入力画面）で話す。アプリにマイクの権限は要らない
  - 「宇多田ヒカルをかけて」「Radiohead をシャッフルで再生」→ いちばん近いものをすぐ再生
  - 「サカナクション」だけなら検索結果を出す。「アーティストの曲名」の言い方もできる
  - かな/カナ・全角/半角・大文字小文字・空白の違いは無視。音声入力の候補（最大 5 つ）から、いちばん当たるものを選ぶ
  - 漢字の読みや、英語名をカタカナで認識された場合（「レディオヘッド」→ Radiohead）は当たらないことがある

| 操作 | iPod スキン | Theta スキン |
|---|---|---|
| お気に入りに登録・解除 | 中央ボタン長押し（行の長押しも可） | ★ ボタン、または行の長押し |
| お気に入りを見る | Favorites | FAVS タブ |
| 音声検索 | MENU 長押し、または Search → Voice Search | 検索欄のマイク（NOW の検索欄はライブラリ全体） |

## 見た目（スキン）

| スキン | 内容 |
|---|---|
| iPod | 上に液晶、下にクリックホイール。Settings → Skin で切り替え |
| Theta | ThetaHomeHatch と同じ HUD：黒地にオレンジ、細い線、角を落としたボタン、`[ CODE ]` の見出しと四隅のかぎ括弧、右端に縦書きのタブ（NOW / FAVS / ARTISTS / ALBUMS / SONGS / GENRES / FOLDERS / LIBRARY・SETUP）。テーマは DARK / LIGHT / POP / ALERT / SCI-FI / SYSTEM（配色は ThetaHomeHatch の `Theme.kt` と同じ値）。SETUP → SKIN で切り替え |

Theta スキンの書体 Oswald・Share Tech Mono は SIL Open Font License（`docs/licenses`）。

## 操作（iPod スキンのクリックホイール）

| 操作 | 動作 |
|---|---|
| リングをなぞる | スクロール（Now Playing では音量） |
| 中央ボタン | 決定（Now Playing ではシークモード切替）。長押しでお気に入り |
| MENU | 戻る（Android の戻るボタンでも可）。長押しで音声検索 |
| （設定） | Clicker：カリカリ音、Haptics：振動を、それぞれオン・オフ |
| ▶❚❚ | 再生/一時停止 |
| ◀◀ / ▶▶ | 前/次の曲、長押しで巻き戻し/早送り |

リストの項目は直接タップでも選択できます。

## セットアップ

1. NAS: WebDAV を有効化（Synology: パッケージセンター → WebDAV Server → HTTP 5005）
   または Audio Station が動いていれば DS audio 方式でそのまま使えます
2. スマホ: Tailscale アプリで VPN を ON
3. APK をインストールして起動 → 接続先を設定
   - WebDAV: URL `http://<NASのTailscale IP または MagicDNS名>:5005`、Music フォルダ `/music`
   - DS audio: URL `http://<同上>:5000`（ポート省略可）、2 段階認証を使っていれば初回だけコード
   - 「接続テスト」で OK を確認
4. ライブラリを更新（iPod: Library → Update Library / Theta: LIBRARY → UPDATE）

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
pip install wsgidav cheroot mutagen
# WebDAV: /music と /vault を公開する WebDAV を立ててから
DAV_URL=http://127.0.0.1:8765 DAV_USER=u DAV_PASS=p flutter test test/dav_integration_test.dart

# DS audio: 実際の NAS か、DSM の API を真似たテストサーバー（test/fake_dsm.py、--otp で 2 段階認証あり）
python3 test/fake_dsm.py <音楽フォルダ> <書き出し先フォルダ> 5000 --otp &
DS_URL=127.0.0.1:5000 DS_USER=u DS_PASS=p DS_VAULT=/vault/Music DS_OTP=123456 \
  flutter test test/ds_integration_test.dart
```

`fake_dsm.py` は応答の形を DSM に合わせたものなので、実機の Audio Station と細部が違う可能性があります。
