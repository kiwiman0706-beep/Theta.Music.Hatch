/// ライブラリのデータモデル。library.json にそのまま保存される。
class Track {
  final String path; // サーバー上の絶対パス（デコード済み） 例: /music/Artist/Album/01 Song.flac
  final int size;
  final int mtime; // epoch ms
  final String title;
  final String artist;
  final String albumArtist;
  final String album;
  final String genre;
  final int year;
  final int trackNo;
  final int discNo;
  // カバー画像: フォルダ画像のパス、または埋め込み画像 (path + offset/length)
  final String? artPath;
  final int artOffset;
  final int artLength;
  // Audio Station の曲 ID（DS audio 経由のときだけ）
  final String id;

  const Track({
    required this.path,
    required this.size,
    required this.mtime,
    required this.title,
    this.artist = '',
    this.albumArtist = '',
    this.album = '',
    this.genre = '',
    this.year = 0,
    this.trackNo = 0,
    this.discNo = 0,
    this.artPath,
    this.artOffset = 0,
    this.artLength = 0,
    this.id = '',
  });

  String get displayArtist => artist.isNotEmpty ? artist : 'Unknown Artist';
  String get groupArtist => albumArtist.isNotEmpty ? albumArtist : displayArtist;
  String get displayAlbum => album.isNotEmpty ? album : 'Unknown Album';
  String get albumKey => '${groupArtist.toLowerCase()}\u0000${displayAlbum.toLowerCase()}';
  String get folder => path.substring(0, path.lastIndexOf('/'));
  String get fileName => path.substring(path.lastIndexOf('/') + 1);

  ArtRef? get art => artPath == null
      ? null
      : ArtRef(artPath!, offset: artOffset, length: artLength);

  Map<String, dynamic> toJson() => {
        'p': path,
        's': size,
        'm': mtime,
        't': title,
        if (artist.isNotEmpty) 'ar': artist,
        if (albumArtist.isNotEmpty) 'aa': albumArtist,
        if (album.isNotEmpty) 'al': album,
        if (genre.isNotEmpty) 'g': genre,
        if (year != 0) 'y': year,
        if (trackNo != 0) 'n': trackNo,
        if (discNo != 0) 'd': discNo,
        if (artPath != null) 'ap': artPath,
        if (artLength != 0) 'ao': artOffset,
        if (artLength != 0) 'alen': artLength,
        if (id.isNotEmpty) 'i': id,
      };

  factory Track.fromJson(Map<String, dynamic> j) => Track(
        path: j['p'] as String,
        size: j['s'] as int? ?? 0,
        mtime: j['m'] as int? ?? 0,
        title: j['t'] as String? ?? '',
        artist: j['ar'] as String? ?? '',
        albumArtist: j['aa'] as String? ?? '',
        album: j['al'] as String? ?? '',
        genre: j['g'] as String? ?? '',
        year: j['y'] as int? ?? 0,
        trackNo: j['n'] as int? ?? 0,
        discNo: j['d'] as int? ?? 0,
        artPath: j['ap'] as String?,
        artOffset: j['ao'] as int? ?? 0,
        artLength: j['alen'] as int? ?? 0,
        id: j['i'] as String? ?? '',
      );
}

/// 画像の参照。length > 0 のときはファイル内の埋め込み画像（Range取得）。
/// path が `ds:` で始まるときは Audio Station のカバー（`ds:<曲ID>`）。
class ArtRef {
  final String path;
  final int offset;
  final int length;
  const ArtRef(this.path, {this.offset = 0, this.length = 0});
  bool get embedded => length > 0;
  String get key => '$path#$offset:$length';
}

class Album {
  final String title;
  final String artist;
  final List<Track> tracks;
  Album(this.title, this.artist, this.tracks);
  String get key => tracks.first.albumKey;
  int get year => tracks.map((t) => t.year).fold(0, (a, b) => b > a ? b : a);
  String get genre => tracks.firstWhere((t) => t.genre.isNotEmpty, orElse: () => tracks.first).genre;
  ArtRef? get art {
    for (final t in tracks) {
      if (t.art != null) return t.art;
    }
    return null;
  }
}

class Artist {
  final String name;
  final List<Album> albums;
  Artist(this.name, this.albums);
  String get key => name.toLowerCase();
  List<Track> get tracks => [for (final a in albums) ...a.tracks];
}
