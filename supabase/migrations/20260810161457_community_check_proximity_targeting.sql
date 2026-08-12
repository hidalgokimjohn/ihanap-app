-- Community Check proximity targeting
--
-- Lets a Community Check specify a target location distinct from the
-- poster's own device location (e.g. asking about Masao while physically
-- in Libertad), and lets the app notify only users currently within a
-- given radius of that target point.

-- Each user's last-known location, kept in sync by the client as
-- LocationService already tracks movement (updates every ~100m).
create table if not exists public.user_locations (
  user_id    uuid primary key references auth.users(id) on delete cascade,
  latitude   double precision not null,
  longitude  double precision not null,
  updated_at timestamptz not null default now()
);

alter table public.user_locations enable row level security;

drop policy if exists "Users manage their own location" on public.user_locations;
create policy "Users manage their own location"
  on public.user_locations
  for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- What the check is actually asking about — captured from a location
-- search pick, not the poster's GPS.
alter table public.community_checks
  add column if not exists target_lat double precision,
  add column if not exists target_lng double precision;

-- Returns the ids of users within [radius_meters] of a point, using a
-- stale-location cutoff so long-inactive devices don't get notified.
-- SECURITY DEFINER so callers never need direct SELECT on user_locations
-- (RLS above only allows a user to read their own row) — they only ever
-- get back a list of ids, never anyone else's raw coordinates.
create or replace function public.nearby_user_ids(
  target_lat double precision,
  target_lng double precision,
  radius_meters double precision default 100
)
returns table (user_id uuid)
language sql
security definer
set search_path = public
as $$
  select ul.user_id
  from public.user_locations ul
  where ul.updated_at > now() - interval '30 minutes'
    and (
      6371000 * acos(
        least(1.0, greatest(-1.0,
          cos(radians(target_lat)) * cos(radians(ul.latitude)) *
          cos(radians(ul.longitude) - radians(target_lng)) +
          sin(radians(target_lat)) * sin(radians(ul.latitude))
        ))
      )
    ) <= radius_meters;
$$;

grant execute on function public.nearby_user_ids(double precision, double precision, double precision) to authenticated;
