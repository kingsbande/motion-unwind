-- Merry Motion upgrade: events, admin allowlist, delete registrations
-- Run once in Supabase > SQL Editor, AFTER setup.sql. Safe to keep your existing registrations.

-- 1) Admin allowlist --------------------------------------------------------
create table public.admin_emails (
  email text primary key check (email = lower(email)),
  added_at timestamptz not null default now()
);

-- First admin. Change this to the email you sign in with, if different.
insert into public.admin_emails (email) values ('hope.l.bande@gmail.com');

create or replace function public.is_admin()
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select exists (
    select 1 from public.admin_emails
    where email = lower(auth.jwt() ->> 'email')
  );
$$;

alter table public.admin_emails enable row level security;

create policy "Admins view admins" on public.admin_emails
  for select to authenticated using (public.is_admin());

create policy "Admins add admins" on public.admin_emails
  for insert to authenticated with check (public.is_admin());

create policy "Admins remove other admins" on public.admin_emails
  for delete to authenticated
  using (public.is_admin() and email <> lower(auth.jwt() ->> 'email'));

-- 2) Events -----------------------------------------------------------------
create table public.events (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  slug text not null unique check (slug ~ '^[a-z0-9-]{3,60}$'),
  name text not null check (char_length(name) between 2 and 100),
  subtitle text check (char_length(subtitle) <= 100),
  event_date timestamptz not null,
  venues jsonb not null default '[]'::jsonb,   -- [{"name":"Blantyre","venue":"Chinyonga"}, ...]
  description text check (char_length(description) <= 400),
  dress_note text check (char_length(dress_note) <= 400),
  registration_open boolean not null default true
);

alter table public.events enable row level security;

create policy "Anyone can view events" on public.events
  for select to anon, authenticated using (true);

create policy "Admins create events" on public.events
  for insert to authenticated with check (public.is_admin());

create policy "Admins update events" on public.events
  for update to authenticated using (public.is_admin()) with check (public.is_admin());

-- Your first event
insert into public.events (slug, name, subtitle, event_date, venues, description, dress_note)
values (
  'merry-motion-unwind-christmas-2026',
  'Merry Motion',
  'Unwind Christmas Edition',
  '2026-12-19 13:00:00+02',
  '[{"name":"Blantyre","venue":"Chinyonga"},{"name":"Lilongwe","venue":"Beacon House Church Office"},{"name":"Zomba","venue":"Botanical Gardens"}]'::jsonb,
  'An afternoon to celebrate each other: birthdays, achievements, and everything worth cheering for.',
  'Wear your favourite shades of red, green, white and gold. Pick one shade or layer them all. No outfit? No problem, just come!'
);

-- 3) Link registrations to events -------------------------------------------
alter table public.registrations add column event_id uuid references public.events(id);

update public.registrations
  set event_id = (select id from public.events where slug = 'merry-motion-unwind-christmas-2026');

alter table public.registrations alter column event_id set not null;

-- A phone number can register once per event (but can come to the next one)
drop index if exists public.registrations_phone_key;
create unique index registrations_event_phone_key on public.registrations (event_id, phone);

-- 4) Replace the old registration policies ----------------------------------
drop policy if exists "Public can register" on public.registrations;
drop policy if exists "Admins can view registrations" on public.registrations;

-- Public can register only for events that are open
create policy "Public can register for open events" on public.registrations
  for insert to anon, authenticated
  with check (exists (
    select 1 from public.events e where e.id = event_id and e.registration_open
  ));

create policy "Admins view registrations" on public.registrations
  for select to authenticated using (public.is_admin());

create policy "Admins delete registrations" on public.registrations
  for delete to authenticated using (public.is_admin());
