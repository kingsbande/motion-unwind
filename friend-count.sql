-- Friend counts: run once in Supabase > SQL Editor after setup.sql and upgrade.sql.
-- Existing "yes" registrations are migrated as one friend each.

alter table public.registrations
  add column if not exists friend_count integer not null default 0;

update public.registrations
  set friend_count = 1
  where bringing_friend and friend_count = 0;

alter table public.registrations
  drop constraint if exists registrations_friend_count_nonnegative;

alter table public.registrations
  add constraint registrations_friend_count_nonnegative check (friend_count >= 0);
