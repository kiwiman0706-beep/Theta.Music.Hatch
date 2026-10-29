"""DSM（Audio Station / File Station API）を真似たテスト用サーバー。

    pip install mutagen
    python3 test/fake_dsm.py <音楽フォルダ> <書き出し用フォルダ> [port] [--otp]
    DS_URL=http://127.0.0.1:5000 DS_USER=u DS_PASS=p DS_VAULT=/vault/Music \
        flutter test test/ds_integration_test.dart

本物の DSM の応答の形（SYNO.API.Info / Auth / AudioStation.Song / Stream / Cover /
FileStation.Download / Upload / CreateFolder）に合わせているが、細部は実機と異なる場合がある。
"""
import json
import os
import sys
import urllib.parse
from email.parser import BytesParser
from email.policy import default
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import mutagen

MUSIC, VAULT = sys.argv[1], sys.argv[2]
PORT = int(sys.argv[3]) if len(sys.argv) > 3 and sys.argv[3].isdigit() else 5000
NEED_OTP = '--otp' in sys.argv
USER, PASS, OTP, SID, DID = 'u', 'p', '123456', 'sid-xyz', 'did-abc'

APIS = {
    'SYNO.API.Info': {'path': 'query.cgi', 'minVersion': 1, 'maxVersion': 1},
    'SYNO.API.Auth': {'path': 'auth.cgi', 'minVersion': 1, 'maxVersion': 6},
    'SYNO.AudioStation.Song': {'path': 'AudioStation/song.cgi', 'minVersion': 1, 'maxVersion': 3},
    'SYNO.AudioStation.Stream': {'path': 'AudioStation/stream.cgi', 'minVersion': 1, 'maxVersion': 2},
    'SYNO.AudioStation.Cover': {'path': 'AudioStation/cover.cgi', 'minVersion': 1, 'maxVersion': 3},
    'SYNO.FileStation.Download': {'path': 'entry.cgi', 'minVersion': 1, 'maxVersion': 2},
    'SYNO.FileStation.Upload': {'path': 'entry.cgi', 'minVersion': 1, 'maxVersion': 3},
    'SYNO.FileStation.CreateFolder': {'path': 'entry.cgi', 'minVersion': 1, 'maxVersion': 2},
}

SONGS = []
for root, _, files in os.walk(MUSIC):
    for f in sorted(files):
        full = os.path.join(root, f)
        try:
            m = mutagen.File(full, easy=True)
        except Exception:
            m = None
        if m is None:
            continue
        tag = lambda k: (m.get(k) or [''])[0] if m.tags else ''
        num = lambda k: int((tag(k).split('/')[0] or '0') if tag(k).split('/')[0].isdigit() else 0)
        rel = '/music/' + os.path.relpath(full, MUSIC).replace(os.sep, '/')
        SONGS.append({
            'id': 'music_%d' % (len(SONGS) + 1), 'path': rel, 'title': tag('title'), 'type': 'file',
            'additional': {
                'song_tag': {'artist': tag('artist'), 'album_artist': tag('albumartist'), 'album': tag('album'),
                             'genre': tag('genre'), 'year': num('date'), 'track': num('tracknumber'),
                             'disc': num('discnumber'), 'composer': '', 'comment': ''},
                'song_audio': {'filesize': os.path.getsize(full), 'duration': int(m.info.length), 'bitrate': 0},
                'song_rating': {'rating': 0},
            },
            '_file': full,
        })


def vault_path(p):
    # DSM の共有フォルダのパス（/vault/...）を手元のフォルダに
    assert p.startswith('/vault')
    return os.path.join(VAULT, p[len('/vault'):].lstrip('/'))


class H(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def send_json(self, obj):
        b = json.dumps(obj).encode()
        self.send_response(200)
        self.send_header('Content-Type', 'application/json; charset=utf-8')
        self.send_header('Content-Length', str(len(b)))
        self.end_headers()
        self.wfile.write(b)

    def ok(self, data=None):
        self.send_json({'success': True, 'data': data or {}})

    def err(self, code):
        self.send_json({'success': False, 'error': {'code': code}})

    def params(self):
        u = urllib.parse.urlparse(self.path)
        q = {k: v[0] for k, v in urllib.parse.parse_qs(u.query).items()}
        files = {}
        if self.command == 'POST':
            body = self.rfile.read(int(self.headers.get('Content-Length', 0)))
            ctype = self.headers.get('Content-Type', '')
            if ctype.startswith('multipart/form-data'):
                msg = BytesParser(policy=default).parsebytes(b'Content-Type: ' + ctype.encode() + b'\r\n\r\n' + body)
                for part in msg.iter_parts():
                    name = part.get_param('name', header='content-disposition')
                    if part.get_filename():
                        files[name] = (part.get_filename(), part.get_payload(decode=True))
                    else:
                        q[name] = part.get_content().strip()
            else:
                q.update({k: v[0] for k, v in urllib.parse.parse_qs(body.decode()).items()})
        return u.path, q, files

    def do_GET(self):
        self.handle_req()

    def do_POST(self):
        self.handle_req()

    def handle_req(self):
        path, q, files = self.params()
        api = q.get('api')
        if api == 'SYNO.API.Info':
            return self.ok(APIS)
        if api == 'SYNO.API.Auth':
            if q.get('account') != USER or q.get('passwd') != PASS:
                return self.err(400)
            if NEED_OTP and q.get('device_id') != DID:
                if 'otp_code' not in q:
                    return self.err(403)
                if q['otp_code'] != OTP:
                    return self.err(404)
                return self.ok({'sid': SID, 'did': DID})
            return self.ok({'sid': SID})
        if q.get('_sid') != SID:
            return self.err(119)
        if api == 'SYNO.AudioStation.Song' and q.get('method') == 'setrating':
            s = next((s for s in SONGS if s['id'] == q.get('id')), None)
            if s is None:
                return self.err(400)
            s['additional']['song_rating']['rating'] = int(q.get('rating', 0))
            return self.ok({})
        if api == 'SYNO.AudioStation.Song':
            off, lim = int(q.get('offset', 0)), int(q.get('limit', 1000))
            songs = [{k: v for k, v in s.items() if k != '_file'} for s in SONGS[off:off + lim]]
            return self.ok({'offset': off, 'total': len(SONGS), 'songs': songs})
        if api in ('SYNO.AudioStation.Stream', 'SYNO.AudioStation.Cover'):
            s = next((s for s in SONGS if s['id'] == q.get('id')), None)
            if s is None:
                return self.err(400)
            if api == 'SYNO.AudioStation.Cover':
                pics = []
                m = mutagen.File(s['_file'])
                if hasattr(m, 'pictures'):
                    pics = [p.data for p in m.pictures]
                elif m.tags is not None:
                    pics = [v.data for k, v in m.tags.items() if k.startswith('APIC')] if hasattr(m.tags, 'items') else []
                    pics += [bytes(c) for c in (m.tags.get('covr') or [])] if 'covr' in m.tags else []
                if not pics:
                    return self.err(400)
                data, ctype = pics[0], 'image/jpeg'
            else:
                data, ctype = open(s['_file'], 'rb').read(), 'audio/mpeg'
            self.send_response(200)
            self.send_header('Content-Type', ctype)
            self.send_header('Content-Length', str(len(data)))
            self.end_headers()
            self.wfile.write(data)
            return
        if api == 'SYNO.FileStation.CreateFolder':
            parent = json.loads(q['folder_path'])[0]
            name = json.loads(q['name'])[0]
            os.makedirs(os.path.join(vault_path(parent), name), exist_ok=True)
            return self.ok({'folders': [{'path': parent + '/' + name}]})
        if api == 'SYNO.FileStation.Upload':
            d = vault_path(q['path'])
            if q.get('create_parents') == 'true':
                os.makedirs(d, exist_ok=True)
            fname, data = files['file']
            target = os.path.join(d, fname)
            if os.path.exists(target) and q.get('overwrite') != 'true':
                return self.err(414)
            open(target, 'wb').write(data)
            return self.ok({})
        if api == 'SYNO.FileStation.Download':
            p = vault_path(json.loads(q['path'])[0])
            if not os.path.exists(p):
                return self.err(408)
            data = open(p, 'rb').read()
            self.send_response(200)
            self.send_header('Content-Type', 'application/octet-stream')
            self.send_header('Content-Length', str(len(data)))
            self.end_headers()
            self.wfile.write(data)
            return
        self.err(102)


print('fake DSM on', PORT, 'songs:', len(SONGS), 'otp' if NEED_OTP else '', flush=True)
ThreadingHTTPServer(('127.0.0.1', PORT), H).serve_forever()
