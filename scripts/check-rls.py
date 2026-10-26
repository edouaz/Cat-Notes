#!/usr/bin/env python3
"""Integration check against a disposable, migrated Supabase project; creates immutable test data."""
import argparse
import hashlib
import json
import os
import urllib.error
import urllib.request
import uuid


def request(base, key, path, token=None, method='GET', data=None, binary=False):
    headers = {'apikey': key, 'Content-Type': 'application/octet-stream' if binary else 'application/json'}
    if token:
        headers['Authorization'] = 'Bearer ' + token
    body = data if binary else (json.dumps(data).encode() if data is not None else None)
    req = urllib.request.Request(base.rstrip('/') + '/' + path, headers=headers, method=method, data=body)
    try:
        with urllib.request.urlopen(req, timeout=30) as response:
            return response.status, response.read()
    except urllib.error.HTTPError as error:
        return error.code, error.read()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.parse_args()
    required = ['SUPABASE_URL', 'SUPABASE_PUBLISHABLE_KEY', 'TEST_A_EMAIL', 'TEST_A_PASSWORD', 'TEST_B_EMAIL', 'TEST_B_PASSWORD']
    if any(not os.environ.get(key) for key in required):
        parser.error('Set the six environment variables listed in docs/SUPABASE.md; no credentials are printed.')
    base, key = os.environ[required[0]], os.environ[required[1]]
    assert base.startswith('https://'), 'HTTPS required'
    users = []
    for name in ('A', 'B'):
        status, data = request(base, key, 'auth/v1/token?grant_type=password', method='POST',
                               data={'email': os.environ[f'TEST_{name}_EMAIL'], 'password': os.environ[f'TEST_{name}_PASSWORD']})
        assert status == 200, f'Login {name}: HTTP {status}'
        auth = json.loads(data)
        users.append((auth['user']['id'], auth['access_token']))
    assert users[0][0] != users[1][0], 'Two different accounts required'
    for index, (owner, token) in enumerate(users):
        other = users[1-index][1]
        note, revision = str(uuid.uuid4()), str(uuid.uuid4())
        path = f'{owner}/{note}/{revision}.catnote'
        binary = b'CatNotes RLS isolation fixture, not a valid notebook'
        status, _ = request(base, key, 'storage/v1/object/notebooks/' + path, token, 'POST', binary, True)
        assert status in (200, 201), f'Own upload: HTTP {status}'
        row = {'id': revision, 'owner_id': owner, 'notebook_id': note, 'parent_id': None,
               'checksum': hashlib.sha256(binary).hexdigest(), 'object_path': path}
        status, _ = request(base, key, 'rest/v1/notebook_revisions', token, 'POST', row)
        assert status in (200, 201), f'Own metadata insert: HTTP {status}'
        status, data = request(base, key, f'rest/v1/notebook_revisions?id=eq.{revision}', token)
        assert status == 200 and len(json.loads(data)) == 1, 'Own read denied'
        status, data = request(base, key, f'rest/v1/notebook_revisions?id=eq.{revision}', other)
        assert status == 200 and json.loads(data) == [], 'Other account can read metadata'
        status, _ = request(base, key, 'storage/v1/object/authenticated/notebooks/' + path, other)
        assert status in (400, 401, 403, 404), 'Other account can read binary'
        status, _ = request(base, key, f'rest/v1/notebook_revisions?id=eq.{revision}', other, 'PATCH', {'checksum': '0'*64})
        assert status in (401, 403), 'Metadata mutations must be denied'
        row['id'] = str(uuid.uuid4())
        row['object_path'] = f"{owner}/{note}/{row['id']}.catnote"
        status, _ = request(base, key, 'rest/v1/notebook_revisions', other, 'POST', row)
        assert status in (401, 403), 'Other account can insert under owner'
    print('PASS: bidirectional account isolation. Immutable fixtures retained in disposable project.')


if __name__ == '__main__':
    main()
