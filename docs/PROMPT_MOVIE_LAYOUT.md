# Music Hatch 1.7.0・1.7.1 の画面の変更を、Theta Movie Hatch のスレッドに伝える文

Movie Hatch のスレッドに、下の「---」から下を貼る。

---

Theta Music Hatch の Theta スキンの画面を、1.7.0・1.7.1 で 4 つ直しました。Movie Hatch は同じ作り（Theta スキン＋クリックホイール）なので、同じように直してください。

## 読んでほしいもの

GitHub の `kiwiman0706-beep/Theta.Music.Hatch`（読めなければ add_repo で足して clone）。

- `lib/ui/shell.dart`：`_thetaList`（タブとリスト）、`build` の中の横並びにするかどうかの判断（`thetaLayout`・`wide`）、`_onButton` の `WheelButton.menu`、`_guide`（ホイールの案内）、`_railOpen`
- `lib/ui/theta_layout.dart`：`ThetaTabs`（`width`・`extra`・`_row`）
- `lib/ui/menus.dart`：設定の `Layout`・`Tab Labels`
- `lib/core/settings.dart`：`thetaLayout`・`tabLabels`
- `docs/releases/v1.7.0.md`・`v1.7.1.md`

コードはそのまま写さず、Movie の画面に合わせて作ってください。

## 変えたこと

### 1. Fold の広げた画面も横並びに

- 前は「横長（幅 > 高さ）で幅 600 以上」だけ横並び（左にリスト、右に再生中のパネルとホイール）。Galaxy Z Fold5 の広げた画面（縦横がほぼ同じ）は縦並びになり、間延びしていた
- 今は **幅 600 以上で、幅 ≥ 高さ × 0.75** なら横並び。縦に持ったスマホ・縦に持ったタブレットは今までどおり縦並び
- 設定 **Layout**：Auto（上の判断）→ Wide（いつも横並び）→ Tall（いつも縦並び）を押すたびに切り替え。保存の名前は `thetaLayout`（`auto`・`wide`・`tall`）

### 2. 左のタブに文字を出せる

- 設定 **Tab Labels**（`tabLabels`、既定はオフ）。オンにすると、タブの幅が 40 から 116 に広がり、印の横に文字（FAVS・ARTISTS など）が並ぶ
- タブの中身は幅で決める：90 以上なら印＋文字を横に、狭いときは今までどおり印だけ、または縦書きの文字
- 幅を変えるときは 180 ms のアニメーション

### 3. いちばん上の階層で MENU を押すとタブが広がる

- モードの一覧（いちばん上）で MENU を押すと、タブが文字付きに広がる（`_railOpen`）。もう一度押すと再生中のパネルへ移る。再生していなければタブをたたむ
- Tab Labels がオンのときは最初から広がっているので、MENU を押すとすぐ再生中へ
- モードを選んだら `_railOpen` を戻す
- ホイールの MENU の下の案内も合わせる：「タブを広げる」→「再生中へ」（再生していなければ「タブをたたむ」）。いちばん上でなければ「上の階層へ」のまま

### 4. いちばん上の階層では、同じ一覧を 2 つ出さない（1.7.1）

- タブを文字付きに広げた状態でいちばん上の階層にいると、左のタブと右のモードの一覧に同じものが並んでいた（利用者の指摘：「両方同じものが出るのは無駄。左だけでいい」）
- 今は、いちばん上の階層でタブが文字付きのとき、**右のリストを出さず、タブだけがリストの場所いっぱいに広がる**。モードの一覧の代わりになる
  - ホイールを回すとモードの一覧の選択が動き、それに合わせてタブが光る（光らせるのは `_modes.selected`）。SELECT で開く。タブを押しても開く
  - モードの一覧のうちタブに無い行（Music では Shuffle Songs）は、タブの下に 1 行足す（`ThetaTabs.extra`。番号はタブの続きにする）
  - 幅が 200 以上のときは、印と文字を少し大きく（印 22、文字 16）
  - いちばん上の階層でなければ、今までどおり左にタブ（40 か 116）、右にリスト

## 確かめ方

- `flutter analyze`・`flutter test`
- 見た目は Web で描いて確かめた（`flutter build web` ＋ Playwright）。大きさは 757×880（Fold5 の広げた画面くらい）と 400×860（スマホの縦）
- 実機（Fold5 の広げた画面・スマホ）でまだ確かめていないことは、Movie の TESTING.md にも書く

終わったら版を上げて Release を作り、Theta.Hatch.Series の `progress/movie.md` に書いてください。
