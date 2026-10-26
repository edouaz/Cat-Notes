#!/usr/bin/env python3
"""Validate migration policies in disposable PostgreSQL, with minimal Supabase schema stubs."""
from pathlib import Path
import subprocess
import tempfile

BOOTSTRAP = """
create role anon;
create role authenticated;
create schema auth;
create schema storage;
create table auth.users(id uuid primary key);
create function auth.uid() returns uuid language sql stable as
$$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
create table storage.buckets(id text primary key, name text, public boolean, file_size_limit bigint, allowed_mime_types text[]);
create table storage.objects(id uuid primary key default gen_random_uuid(), bucket_id text, name text);
create function storage.foldername(text) returns text[] language sql immutable as
$$ select (string_to_array($1, '/'))[1:array_length(string_to_array($1, '/'),1)-1] $$;
alter table storage.objects enable row level security;
grant usage on schema public, auth, storage to anon, authenticated;
grant select, insert, update, delete on storage.objects to anon, authenticated;
insert into auth.users values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb');
"""


def checks(owner, other, revision):
    note = 'cccccccc-cccc-cccc-cccc-cccccccccccc'
    path = f'{owner}/{note}/{revision}.catnote'
    return f"""
set role authenticated;
set request.jwt.claim.sub = '{owner}';
insert into storage.objects(bucket_id,name) values ('notebooks','{path}');
insert into public.notebook_revisions(id,owner_id,notebook_id,checksum,object_path)
values ('{revision}','{owner}','{note}',repeat('a',64),'{path}');
do $$ begin
  if not exists(select 1 from public.notebook_revisions where id = '{revision}') then raise exception 'owner read denied'; end if;
  if not exists(select 1 from storage.objects where name = '{path}') then raise exception 'owner binary denied'; end if;
end $$;
set request.jwt.claim.sub = '{other}';
do $$ declare affected integer; begin
  if exists(select 1 from public.notebook_revisions where id = '{revision}') then raise exception 'cross owner metadata visible'; end if;
  if exists(select 1 from storage.objects where name = '{path}') then raise exception 'cross owner binary visible'; end if;
  begin
    insert into storage.objects(bucket_id,name) values ('notebooks','{path}');
    raise exception 'cross owner binary insert allowed';
  exception when insufficient_privilege then null; end;
  begin
    insert into public.notebook_revisions(id,owner_id,notebook_id,checksum,object_path)
    values (gen_random_uuid(),'{owner}','{note}',repeat('a',64),'{path}');
    raise exception 'cross owner metadata insert allowed';
  exception when insufficient_privilege then null; end;
  begin
    update public.notebook_revisions set checksum=repeat('b',64) where id='{revision}';
    raise exception 'immutable metadata update allowed';
  exception when insufficient_privilege then null; end;
  update storage.objects set name='changed' where name='{path}';
  get diagnostics affected = row_count;
  if affected <> 0 then raise exception 'immutable binary changed'; end if;
end $$;
reset role;
"""


def main():
    with tempfile.TemporaryDirectory(prefix='opennotes-pg-') as temp:
        root = Path(temp)
        data = root / 'data'
        subprocess.run(['initdb', '-D', str(data), '--auth=trust', '--no-locale', '-E', 'UTF8'], check=True, stdout=subprocess.DEVNULL)
        started = False
        try:
            subprocess.run(['pg_ctl', '-D', str(data), '-l', str(root/'server.log'), '-o', f"-k {temp} -h '' -p 55439", '-w', 'start'], check=True, stdout=subprocess.DEVNULL)
            started = True
            migration = Path(__file__).resolve().parents[1] / 'supabase/migrations/202610210001_notebooks.sql'
            sql = BOOTSTRAP + migration.read_text()
            sql += checks('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', '11111111-1111-1111-1111-111111111111')
            sql += checks('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '22222222-2222-2222-2222-222222222222')
            sql += """
set role anon;
set request.jwt.claim.sub = '';
do $$ begin
  begin perform * from public.notebook_revisions; raise exception 'anonymous metadata allowed';
  exception when insufficient_privilege then null; end;
  if exists(select 1 from storage.objects) then raise exception 'anonymous storage visible'; end if;
end $$;
"""
            result = subprocess.run(['psql', '-h', temp, '-p', '55439', '-d', 'postgres', '-v', 'ON_ERROR_STOP=1'], input=sql, capture_output=True, text=True)
            assert result.returncode == 0, result.stderr
            print('PASS: SQL migration, owner read/write, A/B isolation, immutable revisions/files, anonymous denial (local PostgreSQL stubs only).')
        finally:
            if started:
                subprocess.run(['pg_ctl', '-D', str(data), '-m', 'fast', '-w', 'stop'], check=True, stdout=subprocess.DEVNULL)


if __name__ == '__main__':
    main()
