import 'dart:convert';
import 'dart:typed_data';

import 'package:charset/charset.dart';

/// タグ読み取り結果
class TagInfo {
  String title = '';
  String artist = '';
  String albumArtist = '';
  String album = '';
  String genre = '';
  int year = 0;
  int trackNo = 0;
  int discNo = 0;
  int artOffset = 0;
  int artLength = 0;
}

typedef RangeFetcher = Future<Uint8List> Function(int offset, int length);

/// ネットワーク越しのファイルを 64KB ブロック単位でキャッシュしながらランダムアクセス
class RemoteReader {
  static const block = 64 * 1024;
  final RangeFetcher fetch;
  final int size;
  final Map<int, Uint8List> _cache = {};
  int requests = 0;
  RemoteReader(this.fetch, this.size);

  Future<Uint8List> read(int offset, int length) async {
    if (offset >= size || length <= 0) return Uint8List(0);
    if (offset + length > size) length = size - offset;
    final out = Uint8List(length);
    var pos = offset;
    while (pos < offset + length) {
      final bi = pos ~/ block;
      var data = _cache[bi];
      if (data == null) {
        if (++requests > 24) throw StateError('too many range requests');
        // 連続する未取得ブロックはまとめて取得
        var nb = 1;
        while ((bi + nb) * block < offset + length && !_cache.containsKey(bi + nb) && nb < 16) {
          nb++;
        }
        final got = await fetch(bi * block, nb * block);
        for (var i = 0; i < nb; i++) {
          final s = i * block;
          if (s >= got.length) break;
          _cache[bi + i] = Uint8List.sublistView(got, s, (s + block).clamp(0, got.length));
        }
        data = _cache[bi];
        if (data == null) break;
      }
      final inBlock = pos - bi * block;
      if (inBlock >= data.length) break;
      final n = (data.length - inBlock).clamp(0, offset + length - pos);
      out.setRange(pos - offset, pos - offset + n, data, inBlock);
      pos += n;
    }
    return pos - offset == length ? out : Uint8List.sublistView(out, 0, pos - offset);
  }
}

Future<TagInfo?> readTags(RemoteReader r, String ext) async {
  try {
    switch (ext) {
      case 'mp3':
        return await _readId3(r);
      case 'flac':
        return await _readFlac(r);
      case 'm4a':
      case 'mp4':
      case 'aac':
      case 'alac':
        return await _readMp4(r);
      default:
        return null;
    }
  } catch (_) {
    return null;
  }
}

// ---------------------------------------------------------------- text helpers

String _decodeLegacy(List<int> b) {
  // ID3 の「Latin-1」は日本の古いファイルだと Shift_JIS のことが多い
  if (b.every((c) => c < 0x80)) return ascii.decode(b);
  try {
    return utf8.decode(b);
  } catch (_) {}
  try {
    final s = const ShiftJISDecoder().convert(b);
    if (!s.contains('�')) return s;
  } catch (_) {}
  return latin1.decode(b);
}

String _clean(String s) => s.replaceAll('\u0000', ' ').replaceAll('﻿', '').trim();

int _firstInt(String s) => int.tryParse(RegExp(r'\d+').firstMatch(s)?.group(0) ?? '') ?? 0;

String _decodeId3Text(int enc, Uint8List b) {
  switch (enc) {
    case 0:
      return _clean(_decodeLegacy(_trimNull(b, 1)));
    case 1:
      return _clean(_utf16(b, bomDefault: Endian.little));
    case 2:
      return _clean(_utf16(b, bomDefault: Endian.big));
    default:
      return _clean(utf8.decode(_trimNull(b, 1), allowMalformed: true));
  }
}

List<int> _trimNull(Uint8List b, int width) {
  var end = b.length;
  while (end >= width && b[end - 1] == 0) {
    end--;
  }
  return b.sublist(0, end);
}

String _utf16(Uint8List b, {required Endian bomDefault}) {
  var endian = bomDefault;
  var i = 0;
  if (b.length >= 2) {
    if (b[0] == 0xFF && b[1] == 0xFE) {
      endian = Endian.little;
      i = 2;
    } else if (b[0] == 0xFE && b[1] == 0xFF) {
      endian = Endian.big;
      i = 2;
    }
  }
  final units = <int>[];
  for (; i + 1 < b.length; i += 2) {
    final u = endian == Endian.little ? b[i] | (b[i + 1] << 8) : (b[i] << 8) | b[i + 1];
    if (u == 0) {
      // 複数値 (ID3v2.4) は " / " で連結
      units.addAll(' / '.codeUnits);
      continue;
    }
    if (u == 0xFEFF) continue;
    units.add(u);
  }
  var s = String.fromCharCodes(units);
  while (s.endsWith(' / ')) {
    s = s.substring(0, s.length - 3);
  }
  return s;
}

int _be32(Uint8List b, int o) => (b[o] << 24) | (b[o + 1] << 16) | (b[o + 2] << 8) | b[o + 3];
int _le32(Uint8List b, int o) => b[o] | (b[o + 1] << 8) | (b[o + 2] << 16) | (b[o + 3] << 24);
int _syncsafe(Uint8List b, int o) =>
    ((b[o] & 0x7f) << 21) | ((b[o + 1] & 0x7f) << 14) | ((b[o + 2] & 0x7f) << 7) | (b[o + 3] & 0x7f);

const _id3Genres = [
  'Blues', 'Classic Rock', 'Country', 'Dance', 'Disco', 'Funk', 'Grunge', 'Hip-Hop', 'Jazz', 'Metal',
  'New Age', 'Oldies', 'Other', 'Pop', 'R&B', 'Rap', 'Reggae', 'Rock', 'Techno', 'Industrial',
  'Alternative', 'Ska', 'Death Metal', 'Pranks', 'Soundtrack', 'Euro-Techno', 'Ambient', 'Trip-Hop',
  'Vocal', 'Jazz+Funk', 'Fusion', 'Trance', 'Classical', 'Instrumental', 'Acid', 'House', 'Game',
  'Sound Clip', 'Gospel', 'Noise', 'AlternRock', 'Bass', 'Soul', 'Punk', 'Space', 'Meditative',
  'Instrumental Pop', 'Instrumental Rock', 'Ethnic', 'Gothic', 'Darkwave', 'Techno-Industrial',
  'Electronic', 'Pop-Folk', 'Eurodance', 'Dream', 'Southern Rock', 'Comedy', 'Cult', 'Gangsta',
  'Top 40', 'Christian Rap', 'Pop/Funk', 'Jungle', 'Native American', 'Cabaret', 'New Wave',
  'Psychadelic', 'Rave', 'Showtunes', 'Trailer', 'Lo-Fi', 'Tribal', 'Acid Punk', 'Acid Jazz', 'Polka',
  'Retro', 'Musical', 'Rock & Roll', 'Hard Rock',
];

String _normGenre(String g) {
  final m = RegExp(r'^\((\d+)\)(.*)$').firstMatch(g) ?? RegExp(r'^(\d+)$').firstMatch(g);
  if (m != null) {
    final rest = m.groupCount >= 2 ? (m.group(2) ?? '').trim() : '';
    if (rest.isNotEmpty) return rest;
    final i = int.parse(m.group(1)!);
    if (i < _id3Genres.length) return _id3Genres[i];
  }
  return g;
}

// ---------------------------------------------------------------- ID3v2 / v1

Future<TagInfo?> _readId3(RemoteReader r) async {
  final head = await r.read(0, 10);
  TagInfo? info;
  if (head.length == 10 && head[0] == 0x49 && head[1] == 0x44 && head[2] == 0x33) {
    info = await _parseId3v2(r, head);
  }
  if (info == null || info.title.isEmpty) {
    final v1 = await _readId3v1(r);
    if (v1 != null) {
      if (info == null) return v1;
      info.title = v1.title;
      if (info.artist.isEmpty) info.artist = v1.artist;
      if (info.album.isEmpty) info.album = v1.album;
    }
  }
  return info;
}

Future<TagInfo?> _parseId3v2(RemoteReader r, Uint8List head) async {
  final ver = head[3];
  final flags = head[5];
  final tagSize = _syncsafe(head, 6);
  final unsync = flags & 0x80 != 0;
  final info = TagInfo();
  var pos = 10;
  final end = 10 + tagSize;
  if (flags & 0x40 != 0 && ver >= 3) {
    final eh = await r.read(pos, 4);
    pos += ver == 4 ? _syncsafe(eh, 0) : _be32(eh, 0) + 4;
  }
  final idLen = ver == 2 ? 3 : 4;
  final hdrLen = ver == 2 ? 6 : 10;
  var frames = 0;
  while (pos + hdrLen < end && frames++ < 200) {
    final fh = await r.read(pos, hdrLen);
    if (fh.length < hdrLen || fh[0] == 0) break;
    final id = latin1.decode(fh.sublist(0, idLen));
    if (!RegExp(r'^[A-Z0-9]+$').hasMatch(id)) break;
    final int size;
    if (ver == 2) {
      size = (fh[3] << 16) | (fh[4] << 8) | fh[5];
    } else if (ver == 4) {
      size = _syncsafe(fh, 4);
    } else {
      size = _be32(fh, 4);
    }
    final dataPos = pos + hdrLen;
    if (size <= 0 || dataPos + size > end + 16) break;
    final isPic = id == 'APIC' || id == 'PIC';
    if (isPic) {
      if (info.artLength == 0 && !unsync) {
        final h = await r.read(dataPos, size.clamp(0, 512));
        final o = _picDataOffset(h, ver);
        if (o != null && o < size) {
          info.artOffset = dataPos + o;
          info.artLength = size - o;
        }
      }
    } else if (id.startsWith('T') && size < 4096) {
      final d = await r.read(dataPos, size);
      if (d.isNotEmpty) {
        final text = _decodeId3Text(d[0], Uint8List.sublistView(d, 1));
        switch (id) {
          case 'TIT2':
          case 'TT2':
            info.title = text;
          case 'TPE1':
          case 'TP1':
            info.artist = text;
          case 'TPE2':
          case 'TP2':
            info.albumArtist = text;
          case 'TALB':
          case 'TAL':
            info.album = text;
          case 'TCON':
          case 'TCO':
            info.genre = _normGenre(text);
          case 'TRCK':
          case 'TRK':
            info.trackNo = _firstInt(text);
          case 'TPOS':
          case 'TPA':
            info.discNo = _firstInt(text);
          case 'TYER':
          case 'TYE':
          case 'TDRC':
            info.year = _firstInt(text);
        }
      }
    }
    pos = dataPos + size;
  }
  return info;
}

/// APIC/PIC フレーム先頭から画像データ開始までのオフセット
int? _picDataOffset(Uint8List h, int ver) {
  if (h.isEmpty) return null;
  final enc = h[0];
  var i = 1;
  if (ver == 2) {
    i += 3; // format
  } else {
    while (i < h.length && h[i] != 0) {
      i++;
    }
    i++; // null
  }
  i++; // picture type
  if (enc == 1 || enc == 2) {
    while (i + 1 < h.length && !(h[i] == 0 && h[i + 1] == 0)) {
      i += 2;
    }
    i += 2;
  } else {
    while (i < h.length && h[i] != 0) {
      i++;
    }
    i++;
  }
  return i <= h.length ? i : null;
}

Future<TagInfo?> _readId3v1(RemoteReader r) async {
  if (r.size < 128) return null;
  final b = await r.read(r.size - 128, 128);
  if (b.length < 128 || b[0] != 0x54 || b[1] != 0x41 || b[2] != 0x47) return null;
  String f(int s, int l) => _clean(_decodeLegacy(_trimNull(Uint8List.sublistView(b, s, s + l), 1)));
  final info = TagInfo()
    ..title = f(3, 30)
    ..artist = f(33, 30)
    ..album = f(63, 30)
    ..year = _firstInt(f(93, 4));
  if (b[125] == 0 && b[126] != 0) info.trackNo = b[126];
  if (b[127] < _id3Genres.length) info.genre = _id3Genres[b[127]];
  return info;
}

// ---------------------------------------------------------------- FLAC

Future<TagInfo?> _readFlac(RemoteReader r) async {
  var pos = 0;
  var h = await r.read(0, 10);
  if (h.length >= 10 && h[0] == 0x49 && h[1] == 0x44 && h[2] == 0x33) {
    pos = 10 + _syncsafe(h, 6);
  }
  h = await r.read(pos, 4);
  if (latin1.decode(h) != 'fLaC') return null;
  pos += 4;
  final info = TagInfo();
  for (var n = 0; n < 64; n++) {
    final bh = await r.read(pos, 4);
    if (bh.length < 4) break;
    final last = bh[0] & 0x80 != 0;
    final type = bh[0] & 0x7f;
    final len = (bh[1] << 16) | (bh[2] << 8) | bh[3];
    final data = pos + 4;
    if (type == 4) {
      final d = await r.read(data, len);
      _parseVorbis(d, info);
    } else if (type == 6 && info.artLength == 0) {
      final d = await r.read(data, len.clamp(0, 1024));
      var i = 4;
      final mimeLen = _be32(d, i);
      i += 4 + mimeLen;
      final descLen = _be32(d, i);
      i += 4 + descLen + 16;
      final dataLen = _be32(d, i);
      i += 4;
      info.artOffset = data + i;
      info.artLength = dataLen;
    }
    pos = data + len;
    if (last) break;
  }
  return info;
}

void _parseVorbis(Uint8List d, TagInfo info) {
  var i = 0;
  final vendorLen = _le32(d, i);
  i += 4 + vendorLen;
  final count = _le32(d, i);
  i += 4;
  for (var c = 0; c < count && i + 4 <= d.length; c++) {
    final l = _le32(d, i);
    i += 4;
    if (i + l > d.length) break;
    final s = utf8.decode(d.sublist(i, i + l), allowMalformed: true);
    i += l;
    final eq = s.indexOf('=');
    if (eq <= 0) continue;
    final k = s.substring(0, eq).toUpperCase();
    final v = _clean(s.substring(eq + 1));
    switch (k) {
      case 'TITLE':
        info.title = v;
      case 'ARTIST':
        info.artist = info.artist.isEmpty ? v : info.artist;
      case 'ALBUMARTIST':
      case 'ALBUM ARTIST':
        info.albumArtist = v;
      case 'ALBUM':
        info.album = v;
      case 'GENRE':
        info.genre = info.genre.isEmpty ? v : info.genre;
      case 'DATE':
      case 'YEAR':
        info.year = _firstInt(v);
      case 'TRACKNUMBER':
        info.trackNo = _firstInt(v);
      case 'DISCNUMBER':
        info.discNo = _firstInt(v);
    }
  }
}

// ---------------------------------------------------------------- MP4 / M4A

Future<TagInfo?> _readMp4(RemoteReader r) async {
  final info = TagInfo();
  final moov = await _findAtom(r, 0, r.size, 'moov');
  if (moov == null) return null;
  final udta = await _findAtom(r, moov.$1, moov.$2, 'udta');
  if (udta == null) return info;
  final meta = await _findAtom(r, udta.$1, udta.$2, 'meta');
  if (meta == null) return info;
  final ilst = await _findAtom(r, meta.$1 + 4, meta.$2, 'ilst'); // meta は full box
  if (ilst == null) return info;
  var pos = ilst.$1;
  var n = 0;
  while (pos + 8 <= ilst.$2 && n++ < 200) {
    final h = await r.read(pos, 8);
    final size = _be32(h, 0);
    if (size < 8) break;
    final type = latin1.decode(h.sublist(4, 8));
    // 子の 'data' atom: size(4) 'data'(4) type(4) locale(4) payload
    final dataPos = pos + 8;
    final payloadPos = dataPos + 16;
    final payloadLen = size - 8 - 16;
    if (payloadLen > 0) {
      if (type == 'covr') {
        if (info.artLength == 0) {
          info.artOffset = payloadPos;
          info.artLength = payloadLen;
        }
      } else if (payloadLen < 4096) {
        final p = await r.read(payloadPos, payloadLen);
        String str() => _clean(utf8.decode(p, allowMalformed: true));
        switch (type) {
          case '©nam':
            info.title = str();
          case '©ART':
            info.artist = str();
          case 'aART':
            info.albumArtist = str();
          case '©alb':
            info.album = str();
          case '©gen':
            info.genre = str();
          case '©day':
            info.year = _firstInt(str());
          case 'trkn':
            if (p.length >= 4) info.trackNo = (p[2] << 8) | p[3];
          case 'disk':
            if (p.length >= 4) info.discNo = (p[2] << 8) | p[3];
          case 'gnre':
            if (p.length >= 2) {
              final g = ((p[0] << 8) | p[1]) - 1;
              if (g >= 0 && g < _id3Genres.length) info.genre = _id3Genres[g];
            }
        }
      }
    }
    pos += size;
  }
  return info;
}

/// [start,end) の範囲から指定 atom を探し、その中身の範囲 (start,end) を返す
Future<(int, int)?> _findAtom(RemoteReader r, int start, int end, String name) async {
  var pos = start;
  var n = 0;
  while (pos + 8 <= end && n++ < 500) {
    final h = await r.read(pos, 16);
    if (h.length < 8) return null;
    var size = _be32(h, 0);
    var hdr = 8;
    final type = latin1.decode(h.sublist(4, 8));
    if (size == 1 && h.length >= 16) {
      size = (_be32(h, 8) << 32) | _be32(h, 12);
      hdr = 16;
    } else if (size == 0) {
      size = end - pos;
    }
    if (size < hdr) return null;
    if (type == name) return (pos + hdr, pos + size);
    pos += size;
  }
  return null;
}
