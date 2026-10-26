begin;
create table public.notebook_revisions (
    id uuid primary key,
    owner_id uuid not null default auth.uid() references auth.users(id),
    notebook_id uuid not null,
    parent_id uuid,
    checksum text not null check (checksum ~ '^[a-f0-9]{64}$'),
    object_path text not null,
    created_at timestamptz not null default now(),
    unique (owner_id, id),
    foreign key (owner_id, parent_id) references public.notebook_revisions(owner_id, id),
    check (object_path = owner_id::text || '/' || notebook_id::text || '/' || id::text || '.catnote')
);
create index notebook_revisions_owner_notebook on public.notebook_revisions(owner_id, notebook_id, created_at);
alter table public.notebook_revisions enable row level security;
alter table public.notebook_revisions force row level security;
revoke all on public.notebook_revisions from anon, authenticated;
grant select, insert on public.notebook_revisions to authenticated;
create policy own_revisions_read on public.notebook_revisions for select to authenticated using ((select auth.uid()) = owner_id);
create policy own_revisions_insert on public.notebook_revisions for insert to authenticated with check ((select auth.uid()) = owner_id);
-- Immutable revisions prevent a concurrent writer from replacing another device's notes.
insert into storage.buckets(id, name, public, file_size_limit, allowed_mime_types)
values ('notebooks', 'notebooks', false, 157286400, array['application/octet-stream']);
create policy own_notebook_files_read on storage.objects for select to authenticated
using (bucket_id = 'notebooks' and (storage.foldername(name))[1] = (select auth.uid())::text);
create policy own_notebook_files_insert on storage.objects for insert to authenticated
with check (bucket_id = 'notebooks' and (storage.foldername(name))[1] = (select auth.uid())::text
and name ~ '^[a-f0-9-]{36}/[a-f0-9-]{36}/[a-f0-9-]{36}\.catnote$');
-- No UPDATE/DELETE policies: a client cannot erase an existing revision or binary.
commit;
