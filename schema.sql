-- The Last Adventure Wiki: database setup for Supabase.
-- Paste this whole file into Supabase > SQL Editor > New query, then press Run.

create extension if not exists pgcrypto with schema extensions;

-- Content tables. Everyone can read. Nobody can write directly.
create table if not exists wiki_meta     (id text primary key, data jsonb not null, updated_at timestamptz not null default now());
create table if not exists wiki_sections (id text primary key, data jsonb not null, updated_at timestamptz not null default now());
create table if not exists wiki_media    (id text primary key, data text  not null, updated_at timestamptz not null default now());

-- Holds the hash of the edit code. No policy on purpose, so the browser can never read it.
create table if not exists wiki_settings (key text primary key, value text not null);

alter table wiki_meta     enable row level security;
alter table wiki_sections enable row level security;
alter table wiki_media    enable row level security;
alter table wiki_settings enable row level security;

drop policy if exists "public read" on wiki_meta;
drop policy if exists "public read" on wiki_sections;
drop policy if exists "public read" on wiki_media;
create policy "public read" on wiki_meta     for select to anon using (true);
create policy "public read" on wiki_sections for select to anon using (true);
create policy "public read" on wiki_media    for select to anon using (true);

-- THE EDIT CODE. Write it in CAPITAL LETTERS here. The site accepts any casing.
-- To change the code later, run only this statement again with the new code.
insert into wiki_settings (key, value)
values ('code_hash', encode(extensions.digest('TLA', 'sha256'), 'hex'))
on conflict (key) do update set value = excluded.value;

-- Code check
create or replace function wiki_check(p_code text) returns boolean
language sql security definer set search_path = public, extensions as $$
  select exists (
    select 1 from wiki_settings
    where key = 'code_hash'
      and value = encode(digest(upper(btrim(coalesce(p_code, ''))), 'sha256'), 'hex')
  );
$$;

-- Save a page or the wiki settings
create or replace function wiki_save(p_code text, p_kind text, p_id text, p_data jsonb) returns void
language plpgsql security definer set search_path = public, extensions as $$
begin
  if not wiki_check(p_code) then raise exception 'bad code' using errcode = '28000'; end if;
  if length(p_data::text) > 300000 then raise exception 'too large'; end if;
  if p_kind = 'meta' then
    insert into wiki_meta (id, data, updated_at) values ('meta', p_data, now())
    on conflict (id) do update set data = excluded.data, updated_at = now();
  elsif p_kind = 'section' then
    insert into wiki_sections (id, data, updated_at) values (p_id, p_data, now())
    on conflict (id) do update set data = excluded.data, updated_at = now();
  else
    raise exception 'bad kind';
  end if;
end;
$$;

-- Save a photo (stored as text)
create or replace function wiki_save_media(p_code text, p_id text, p_data text) returns void
language plpgsql security definer set search_path = public, extensions as $$
begin
  if not wiki_check(p_code) then raise exception 'bad code' using errcode = '28000'; end if;
  if length(p_data) > 400000 then raise exception 'too large'; end if;
  insert into wiki_media (id, data, updated_at) values (p_id, p_data, now())
  on conflict (id) do update set data = excluded.data, updated_at = now();
end;
$$;

-- Delete a page or a photo
create or replace function wiki_delete(p_code text, p_kind text, p_id text) returns void
language plpgsql security definer set search_path = public, extensions as $$
begin
  if not wiki_check(p_code) then raise exception 'bad code' using errcode = '28000'; end if;
  if p_kind = 'section' then delete from wiki_sections where id = p_id;
  elsif p_kind = 'media' then delete from wiki_media where id = p_id;
  else raise exception 'bad kind';
  end if;
end;
$$;

grant execute on function wiki_check(text)                     to anon;
grant execute on function wiki_save(text, text, text, jsonb)   to anon;
grant execute on function wiki_save_media(text, text, text)    to anon;
grant execute on function wiki_delete(text, text, text)        to anon;

-- Starter content (safe to delete from inside the wiki)
insert into wiki_meta (id, data) values ('meta', '{
  "title": "The Last Adventure Wiki",
  "tagline": "Everything about the world, its people, and the road ahead.",
  "labels": [
    {"id": "lore", "name": "Lore", "c": 1},
    {"id": "chars", "name": "Characters", "c": 2},
    {"id": "places", "name": "Places", "c": 4},
    {"id": "items", "name": "Items", "c": 3}
  ]
}') on conflict (id) do nothing;

insert into wiki_sections (id, data) values ('welcome', '{
  "title": "Welcome",
  "summary": "Start here. How this wiki works.",
  "labelId": "lore",
  "cover": null,
  "createdAt": "2026-11-04T19:00:00.000Z",
  "updatedAt": "2026-11-04T19:00:00.000Z",
  "blocks": [
    {"id": "w1", "type": "text", "text": "This is an example page. Press Edit, enter the code, and change anything. Everything saves by itself."}
  ]
}') on conflict (id) do nothing;
