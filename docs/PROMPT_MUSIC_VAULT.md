# 音楽の整理・ジャケット・Obsidian Vault づくりを、ローカルの Claude Code に頼む文

自分の PC（Windows）で動く Claude Code に、下の「---」から下を貼る。
NAS の共有フォルダ `music` と `Obsidian` をネットワークドライブとしてつないでおく（例 `M:`＝music、`O:`＝Obsidian）。
1 回で全部やろうとせず、**フォルダ 1 つずつ**頼む（例：「まず 邦楽 の あ行 だけ」）。

---

NAS（Synology DS1825+）の音楽を整理して、ジャケットをそろえ、Obsidian の Vault に音楽のノートを作りたいです。手伝ってください。

## 読んでほしいもの

GitHub の公開リポジトリから読んでください。

- `kiwiman0706-beep/Theta.Hatch.Series`
  - `docs/PROMPT_NAS_ORGANIZE.md`（整理の進め方。**この手順と「守ってほしいこと」に必ず従う**）
  - `spec/THETA_LIBRARY_SPEC.md` の §2（名前の決まり）・§4（音楽）・§7（整理の約束）
  - `spec/THETA_VAULT_SPEC.md`（Vault の形。特に「NAS の置き場所」「Obsidian での一覧（Bases）」）
- `kiwiman0706-beep/Theta.Music.Hatch`
  - `lib/core/obsidian.dart`（アプリがノートを書き出す形。**このファイルと同じ形で作る**）

今回の対象：**＜例：`M:\邦楽\あ行\`＞**
Vault：`O:\Theta Vault\`（音楽のノートは `O:\Theta Vault\Music\`）

## やること（この順で。各段階で私に見せて OK をもらってから次へ）

### 1. 調べる（読むだけ）

件数・形式・今の並び方、タグの欠け（アルバムアーティスト・年・トラック番号・ディスク番号）、Shift_JIS などの文字化け、名前のゆれ（全角・半角、「The」の有無）、ジャケットの有無（埋め込み・`cover.jpg`・`folder.jpg` など）、重複をまとめて見せてください。

### 2. タグとフォルダの整理（`THETA_LIBRARY_SPEC.md` §4）

- スナップショットを撮るよう私に頼んでから、変更案 CSV（今の場所・新しい場所・直すタグ・理由・確かさ）を作ってください。
- 形は `music/<アルバムアーティスト>/<アルバム> (<年>)/01 <曲名>.flac`（複数ディスクは `1-01`）。オムニバスはアルバムアーティストを `Various Artists`。
- タグは UTF-8（MP3 は ID3v2.4）。Shift_JIS の古いタグは UTF-8 に直す。
- **アルバムアーティストを必ず入れる**。アプリはアルバムアーティストでアーティストとアルバムをまとめます。空だと、同じアルバムが歌手ごとに分かれます。プロデュース作・トリビュートのように、別の歌手の曲が入るアルバムも、アルバムアーティストを 1 つに決めます。

### 3. ジャケット（アプリのキャッシュにもなる）

- 各アルバムのフォルダに **`cover.jpg`**（正方形、500px 以上、できれば 1000px 前後、JPEG）を置いてください。
  - 埋め込みのジャケットがあれば、それを取り出して `cover.jpg` に（埋め込みは消さない・曲のファイルは変えない）
  - どこにも無いアルバムは一覧にして私に見せてください（ネットから勝手に取ってこない）
- アプリ（Theta Music Hatch）は、WebDAV では `cover` → `folder` → `front` → `album` の順にフォルダの画像を探します。DS audio では Audio Station のジャケット（フォルダの `cover.jpg` も読みます）を使います。
- **Vault 用のサムネイル**：同じジャケットを 300px 前後に縮小した JPEG を `O:\Theta Vault\Music\_files\<アルバムの id>.jpg` に置いてください（id は下の 4.）。大きな画像は Vault に入れない（Vault の決まり）。

### 4. Vault のノート（アプリの書き出しと同じ形）

`lib/core/obsidian.dart` と同じファイル名・`id`・中身にしてください。**同じ形で作れば、あとでアプリが書き出し直しても、ノートが二重にならず、手で書いたメモも残ります。**

- **置き場所**
  - アルバム：`Music/Albums/<アーティスト> - <アルバム>.md`
  - アーティスト：`Music/Artists/<アーティスト>.md`
  - 名前に使えない文字 `\ / : * ? " < > | # ^ [ ]` は `_` にする。前後の空白は取り、120 文字まで
- **アーティスト**：アルバムアーティスト。空ならアーティスト、それも空なら `Unknown Artist`。アルバム名が空なら `Unknown Album`
- **id**：アプリと同じ作り方にする。これで同じものだと見分けられます
  - アルバム：`md5("music/album:" + 小文字のアーティスト + "\u0000" + 小文字のアルバム)`
  - アーティスト：`md5("music/artist:" + 小文字のアーティスト)`
  - 32 文字を `8-4-4-4-12` で区切った UUID の形にする
- **アルバムの frontmatter**
  - `theta: music/album@1`
  - `id: …`
  - `type: album`
  - `artist: "[[Music/Artists/<アーティスト>|<アーティスト>]]"`
  - `album: "…"`
  - `year`・`genre`（あれば）
  - `tracks: <曲数>`
  - `nas_path: "nas://music/<アルバムのフォルダ>"`（`nas://<共有フォルダ>/…` の形）
  - `tags: [music/album]`
  - `updated: YYYY-MM-DD`
  - ジャケット：`cover: "Music/_files/<id>.jpg"`（アプリはこの項目を消さずに残します）
- **アーティストの frontmatter**
  - `theta: music/artist@1`
  - `id: …`
  - `type: artist`
  - `albums: <アルバム数>`
  - `songs: <曲数>`
  - `tags: [music/artist]`
  - `updated: …`
- **本文**
  - `<!-- theta-music:begin (この区間は自動生成。外側に書いたメモは保持されます) -->` と `<!-- theta-music:end -->` の間に書く
  - アルバムは `# アルバム名`・アーティストへのリンク・曲の表（`| # | Title | Artist |`）
  - アーティストは `# 名前` と `## Albums` の一覧（`- [[Music/Albums/…|アルバム名]] (年)`）
  - 区間の外は `## Notes` だけ置く
- **すでにノートがあるとき**
  - frontmatter の `favorite`・`favorite_songs`・`rating` など、私やアプリが付けた項目を消さない
  - 自動生成区間の外に書いたメモも消さない
  - 曲の表の `★`（お気に入りの印）も残す
- **一覧（Bases）**：`Music/アルバム.base` と `Music/アーティスト.base` は**無いときだけ**作る（あれば触らない）。カード表示で `cover` を出す見本を、別の名前（例 `Music/アルバム（ジャケット）.base`）で作ってもらえると嬉しいです。
- **Vault の登録**：`O:\Theta Vault\.theta\vault.json` の `apps` に `music` が無ければ足す（ほかの項目は消さない）。

### 5. 終わったら

件数が合っているか（消えた物が無いか）を確かめ、`_整理の記録/<日時>.csv` と元に戻すスクリプトを残してください。
そのうえで、次が要るかを教えてください。

- Audio Station の再インデックス（DSM → Audio Station → 設定 → 再インデックス、または DSM のインデックスサービス）
- アプリ（Theta Music Hatch）の Library →「Rebuild Library」（WebDAV のとき。タグを直したので全部読み直す）

## 守ってほしいこと（`PROMPT_NAS_ORGANIZE.md` と同じ。抜粋）

- **消さない**。重複・不明な物は `_未整理/` か一覧に回す。
- 曲のファイルの中身は変えない（再エンコード・形式の変換をしない）。直してよいのはタグだけ。それも変更案で確認してから。
- 1 回は数百件まで。大きな処理は、まず 10 件くらいで試して結果を見せてから。
- 道具は Python 3.12（タグは `mutagen`、画像は `Pillow`）。入っていない物は、入れ方を教えてから使う（`pip install mutagen`）。
- Vault の `.obsidian/` や、ほかのアプリのフォルダ（`Meishi/`・`Memo/` など）は触らない。
