-- Local validation only. Capture existing tables, excluding volatile ctid ordering changes from VACUUM.
-- Only the columns that exist now are hashed: later migrations may add columns, never change existing values.
create table public._test_scoped_preservation(name text primary key,hash text not null,n bigint not null,cols text[] not null,rows text[],mode text);
do $$ declare r record;h text;n bigint;c text[];rs text[];begin
 for r in select tablename from pg_tables where schemaname='public' and tablename<>'_test_scoped_preservation' order by tablename loop
 select array_agg(column_name::text order by column_name) into c from information_schema.columns where table_schema='public' and table_name=r.tablename;
 execute format('select md5(coalesce(string_agg(h,'''' order by h),'''')),count(*),array_agg(h order by h) from(select md5((select jsonb_object_agg(k,v) from jsonb_each(to_jsonb(t)) e(k,v) where k=any($1))::text) h from public.%I t)x',r.tablename) into h,n,rs using c;
 insert into public._test_scoped_preservation values(r.tablename,h,n,c,
  case when r.tablename in('sim_difficulty_profiles','mgr_matches','mgr_match_players','mgr_match_events','cw_club_dates','cw_ai_days','mgr_messages',
   'cw_offer_history','cw_finance','cw_contracts','cw_negotiations','cw_appearances','season_fixture_slots','econ_requests','cw_commitments') then rs end,
  case when r.tablename='sim_difficulty_profiles' then 'grow' when r.tablename in('mgr_matches','mgr_match_players','mgr_match_events','cw_club_dates','cw_ai_days',
   'mgr_messages','cw_offer_history','cw_finance','cw_contracts','cw_negotiations','cw_appearances','season_fixture_slots','econ_requests','cw_commitments') then 'shrink' end);
 end loop;
end $$;
