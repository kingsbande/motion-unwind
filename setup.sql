-- Merry Motion registrations: run once in Supabase > SQL Editor

create table public.registrations (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  full_name text not null check (char_length(full_name) between 2 and 100),
  phone text not null check (char_length(phone) between 7 and 20),
  city text check (char_length(city) between 2 and 50),
  allergies text check (char_length(allergies) <= 300),
  bringing_friend boolean not null default false,
  friend_count integer not null default 0 constraint registrations_friend_count_nonnegative check (friend_count >= 0),
  attendance_type text not null default 'in_person' check (attendance_type in ('in_person', 'online')),
  joining_from text,
  constraint registrations_attendance_location_check check (
    (attendance_type = 'in_person' and city is not null and joining_from is null)
    or (
      attendance_type = 'online' and city is null and joining_from is not null
      and char_length(btrim(joining_from)) between 2 and 100
    )
  )
);

-- One registration per phone number (stops accidental double sign-ups)
create unique index registrations_phone_key on public.registrations (phone);

alter table public.registrations enable row level security;

-- Anyone with the public page can register, but cannot read anyone's data
create policy "Public can register"
  on public.registrations for insert
  to anon, authenticated
  with check (true);

-- Only signed-in admins can view the list and headcounts
create policy "Admins can view registrations"
  on public.registrations for select
  to authenticated
  using (true);
