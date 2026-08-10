-- One-off diagnostic: surface user_locations + recent community_check_nearby
-- notifications via RAISE NOTICE so they're visible in `supabase db push`
-- output without needing a local Postgres client. No schema changes.
do $$
declare
  r record;
begin
  raise notice '--- user_locations ---';
  for r in select user_id, latitude, longitude, updated_at from public.user_locations order by updated_at desc loop
    raise notice 'user_id=% lat=% lng=% updated_at=%', r.user_id, r.latitude, r.longitude, r.updated_at;
  end loop;

  raise notice '--- recent community_check_nearby notifications ---';
  for r in select user_id, title, body, reference_id, created_at from public.notifications
           where type = 'community_check_nearby' order by created_at desc limit 20 loop
    raise notice 'user_id=% ref=% created_at=% body=%', r.user_id, r.reference_id, r.created_at, r.body;
  end loop;

  raise notice '--- profiles (id, full_name) for reference ---';
  for r in select id, full_name from public.profiles loop
    raise notice 'id=% full_name=%', r.id, r.full_name;
  end loop;
end $$;
