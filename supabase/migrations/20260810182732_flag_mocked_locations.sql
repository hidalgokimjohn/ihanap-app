-- Mock-location defense in depth.
--
-- Clients already refuse to sync/act on a GPS reading the device itself
-- flags as coming from a mock provider (Android's Location.isFromMockProvider,
-- iOS 15+'s CLLocationSourceInformation.isSimulatedBySoftware). This adds a
-- server-side backstop: even if a tampered client skipped that check and
-- synced a mocked position anyway, nearby_user_ids never counts it, so a
-- spoofed location can't be used to fake proximity for Community Check.

alter table public.user_locations
  add column if not exists is_mocked boolean not null default false;

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
    and ul.is_mocked = false
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
