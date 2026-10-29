import 'library.dart';
import 'models.dart';

/// 検索・音声検索。「宇多田ヒカルをかけて」「First Love 再生」のような言い方から、
/// 曲名・アルバム・アーティストを探す。かな/カナ・全角/半角・大文字/小文字・空白の違いは無視する。

/// 比較用に正規化：小文字、全角英数→半角、カタカナ→ひらがな、空白と記号を除く
String normalizeForSearch(String s) {
  final b = StringBuffer();
  for (final r in s.toLowerCase().runes) {
    var c = r;
    if (c >= 0xFF01 && c <= 0xFF5E) c -= 0xFEE0; // 全角 ASCII
    if (c >= 0x41 && c <= 0x5A) c += 0x20;
    if (c >= 0x30A1 && c <= 0x30F6) c -= 0x60; // カタカナ → ひらがな
    if (_skip.contains(c)) continue;
    b.writeCharCode(c);
  }
  return b.toString();
}

final _skip = {
  for (final ch in ' 　\t・･.,，．、。\'"’”「」『』()（）[]【】!！?？-‐―_~〜:：;；/／&＆'.runes) ch,
};

/// 末尾・先頭の「再生して」などの言い方。play=true なら見つかった曲をすぐ流す
class VoiceCommand {
  final String query;
  final bool play;
  final bool shuffle;
  const VoiceCommand(this.query, {this.play = false, this.shuffle = false});
}

const _playSuffixes = [
  'をかけてください', 'かけてください', 'をかけて', 'かけて', 'をかける', 'かける',
  'を再生してください', '再生してください', 'を再生して', '再生して', 'を再生', '再生',
  'を流してください', '流してください', 'を流して', '流して',
  'を聴かせて', 'を聞かせて', '聴かせて', '聞かせて', 'が聴きたい', 'が聞きたい', '聴きたい', '聞きたい',
  'をプレイ', 'プレイ',
];
const _shuffleSuffixes = ['をシャッフル再生', 'シャッフル再生', 'をシャッフルで', 'シャッフルで', 'をシャッフル', 'シャッフル'];

VoiceCommand parseVoiceCommand(String text) {
  var q = text.trim();
  var play = false;
  var shuffle = false;
  final lower = q.toLowerCase();
  for (final p in ['play ', 'shuffle ']) {
    if (lower.startsWith(p)) {
      q = q.substring(p.length);
      play = true;
      shuffle = p == 'shuffle ';
    }
  }
  // 「〜をシャッフルでかけて」のように重なることもあるので、何回か剥がす
  for (var i = 0; i < 3; i++) {
    final t = q.trimRight();
    String? hit;
    for (final s in _shuffleSuffixes) {
      if (t.endsWith(s)) {
        hit = s;
        shuffle = true;
        break;
      }
    }
    if (hit == null) {
      for (final s in _playSuffixes) {
        if (t.endsWith(s)) {
          hit = s;
          break;
        }
      }
    }
    if (hit == null) break;
    play = true;
    q = t.substring(0, t.length - hit.length);
  }
  q = q.trim();
  for (final s in ['の曲', 'のアルバム', 'の歌']) {
    if (q.endsWith(s)) q = q.substring(0, q.length - s.length);
  }
  return VoiceCommand(q.trim(), play: play, shuffle: shuffle);
}

enum HitKind { artist, album, track }

class SearchHit {
  final HitKind kind;
  final int score;
  final Artist? artist;
  final Album? album;
  final Track? track;
  SearchHit.artist(this.artist, this.score) : kind = HitKind.artist, album = null, track = null;
  SearchHit.album(this.album, this.score) : kind = HitKind.album, artist = null, track = null;
  /// 曲のときの album は、その曲の入ったアルバム（続けて流す）
  SearchHit.track(this.track, this.score, [this.album]) : kind = HitKind.track, artist = null;

  String get label => switch (kind) {
        HitKind.artist => artist!.name,
        HitKind.album => '${album!.title} — ${album!.artist}',
        HitKind.track => '${track!.title} — ${track!.displayArtist}',
      };

  /// 再生する曲と開始位置
  (List<Track>, int) get playable {
    switch (kind) {
      case HitKind.artist:
        return (artist!.tracks, 0);
      case HitKind.album:
        return (album!.tracks, 0);
      case HitKind.track:
        if (album == null) return ([track!], 0);
        final i = album!.tracks.indexWhere((t) => t.path == track!.path);
        return i < 0 ? ([track!], 0) : (album!.tracks, i);
    }
  }
}

class SearchResult {
  final String query;
  final List<Artist> artists;
  final List<Album> albums;
  final List<Track> tracks;
  final SearchHit? best;
  const SearchResult(this.query, this.artists, this.albums, this.tracks, this.best);
  bool get isEmpty => artists.isEmpty && albums.isEmpty && tracks.isEmpty;
}

int _score(String name, String q) {
  if (q.isEmpty || name.isEmpty) return 0;
  if (name == q) return 100;
  if (name.startsWith(q)) return 80;
  if (name.contains(q)) return 60;
  if (name.length >= 2 && q.contains(name)) return 40; // 「宇多田ヒカルのfirstlove」に artist が含まれる
  return 0;
}

SearchResult search(Library lib, String query, {int limit = 50}) {
  final q = normalizeForSearch(query);
  if (q.isEmpty) return SearchResult(query, const [], const [], const [], null);

  final artists = <(Artist, int)>[];
  for (final a in lib.artists) {
    final s = _score(normalizeForSearch(a.name), q);
    if (s > 0) artists.add((a, s));
  }
  final albums = <(Album, int)>[];
  for (final a in lib.albums) {
    final s = _score(normalizeForSearch(a.title), q);
    if (s > 0) albums.add((a, s));
  }
  final tracks = <(Track, int)>[];
  for (final t in lib.songs) {
    final s = _score(normalizeForSearch(t.title), q);
    if (s > 0) tracks.add((t, s));
  }

  // 「アーティストの曲名／アルバム名」
  SearchHit? combo;
  final no = query.lastIndexOf('の');
  if (no > 0 && no < query.length - 1) {
    final qa = normalizeForSearch(query.substring(0, no));
    final qt = normalizeForSearch(query.substring(no + 1));
    for (final a in lib.artists) {
      if (_score(normalizeForSearch(a.name), qa) < 60) continue;
      for (final al in a.albums) {
        final s = _score(normalizeForSearch(al.title), qt);
        if (s >= 60 && (combo == null || s + 10 > combo.score)) combo = SearchHit.album(al, s + 10);
        for (final t in al.tracks) {
          final st = _score(normalizeForSearch(t.title), qt);
          if (st >= 60 && (combo == null || st + 9 > combo.score)) combo = SearchHit.track(t, st + 9, al);
        }
      }
    }
  }

  artists.sort((a, b) => b.$2.compareTo(a.$2));
  albums.sort((a, b) => b.$2.compareTo(a.$2));
  tracks.sort((a, b) => b.$2.compareTo(a.$2));

  // 同じ点ならアーティスト > アルバム > 曲。部分一致（40）だけのときは「の」で分けた方を優先
  SearchHit? best = combo;
  void consider(SearchHit h) {
    if (best == null || h.score > best!.score) best = h;
  }

  if (artists.isNotEmpty) consider(SearchHit.artist(artists.first.$1, artists.first.$2 + 2));
  if (albums.isNotEmpty) consider(SearchHit.album(albums.first.$1, albums.first.$2 + 1));
  if (tracks.isNotEmpty) {
    final t = tracks.first.$1;
    Album? al;
    for (final a in lib.albums) {
      if (a.key == t.albumKey) {
        al = a;
        break;
      }
    }
    consider(SearchHit.track(t, tracks.first.$2, al));
  }

  List<T> take<T>(List<(T, int)> l) => [for (final e in l.take(limit)) e.$1];
  return SearchResult(query, take(artists), take(albums), take(tracks), best);
}

/// 音声認識の候補（最大 5 つ）からいちばん当たったものを選ぶ
(SearchResult, VoiceCommand)? searchVoice(Library lib, List<String> alternatives) {
  (SearchResult, VoiceCommand)? out;
  for (final alt in alternatives) {
    final cmd = parseVoiceCommand(alt);
    if (cmd.query.isEmpty) continue;
    final r = search(lib, cmd.query);
    final score = r.best?.score ?? 0;
    if (out == null || score > (out.$1.best?.score ?? 0)) out = (r, cmd);
  }
  return out;
}
