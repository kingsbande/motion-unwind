-- Online attendance and secure public event data links.
-- Run once in Supabase > SQL Editor after setup.sql, upgrade.sql, and friend-count.sql.

begin;

alter table public.registrations
  alter column city drop not null,
  add column if not exists attendance_type text not null default 'in_person',
  add column if not exists joining_from text;

alter table public.registrations
  drop constraint if exists registrations_attendance_type_check,
  drop constraint if exists registrations_attendance_location_check;

alter table public.registrations
  add constraint registrations_attendance_type_check
    check (attendance_type in ('in_person', 'online')),
  add constraint registrations_attendance_location_check
    check (
      (attendance_type = 'in_person' and city is not null and joining_from is null)
      or (
        attendance_type = 'online' and city is null and joining_from is not null
        and char_length(btrim(joining_from)) between 2 and 100
      )
    );

create table if not exists public.event_public_links (
  event_id uuid primary key references public.events(id) on delete cascade,
  share_token uuid not null unique default gen_random_uuid(),
  created_at timestamptz not null default now()
);

alter table public.event_public_links enable row level security;
revoke all on table public.event_public_links from public, anon, authenticated;
grant select, insert on table public.event_public_links to authenticated;

drop policy if exists "Admins view event public links" on public.event_public_links;
create policy "Admins view event public links" on public.event_public_links
  for select to authenticated using (public.is_admin());

drop policy if exists "Admins create event public links" on public.event_public_links;
create policy "Admins create event public links" on public.event_public_links
  for insert to authenticated with check (public.is_admin());

create or replace function public.get_public_event_data(p_share_token uuid)
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select jsonb_build_object(
    'event', jsonb_build_object(
      'name', e.name,
      'subtitle', e.subtitle,
      'event_date', e.event_date,
      'venues', e.venues
    ),
    'registrations', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'created_at', r.created_at,
          'full_name', r.full_name,
          'phone', r.phone,
          'city', r.city,
          'attendance_type', r.attendance_type,
          'joining_from', r.joining_from,
          'allergies', r.allergies,
          'bringing_friend', r.bringing_friend,
          'friend_count', r.friend_count
        )
        order by r.created_at desc
      )
      from public.registrations r
      where r.event_id = e.id
    ), '[]'::jsonb)
  )
  from public.event_public_links l
  join public.events e on e.id = l.event_id
  where l.share_token = p_share_token;
$$;

revoke all on function public.get_public_event_data(uuid) from public;
grant execute on function public.get_public_event_data(uuid) to anon, authenticated;

commit;
