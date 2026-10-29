begin;
insert into auth.users(id) values('11111111-1111-4111-8111-111111111111');
insert into public.careers(id,user_id,nickname,club_id,country,age,bonus_energy)
values('22222222-2222-4222-8222-222222222222','11111111-1111-4111-8111-111111111111','Coach UI','palmeiras','BR',30,10);
select set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',true) is not null;
create temp table ui_ctx as select public.mgr_hub() as hub;
insert into auth.users(id) values('44444444-4444-4444-8444-444444444444');
insert into public.careers(id,user_id,nickname,club_id,country,age,bonus_energy)
values('55555555-5555-4555-8555-555555555555','44444444-4444-4444-8444-444444444444','Coach Europe UI','arsenal','EN',30,10);
select set_config('request.jwt.claim.sub','44444444-4444-4444-8444-444444444444',true) is not null;
create temp table ui_europe as select public.mgr_hub() as hub,public.mgr_squad() as squad;
select set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',true) is not null;
alter table ui_ctx add column match jsonb;
update ui_ctx set match=public.mgr_match_start();
alter table ui_ctx add column finished jsonb;
do $$ declare m jsonb;begin
 select match into m from ui_ctx;
 for attempt in 1..12 loop
  m:=public.mgr_match_step((m->>'fixture_id')::bigint,(m->>'minute')::int,120,null,true,0);
  exit when m->>'status'='finished';
 end loop;
 update ui_ctx set finished=m;
end $$;
select jsonb_build_object(
 'hub',u.hub,'squad',public.mgr_squad(),
 'europeanSquad',(select squad from ui_europe),'europeanHub',(select hub from ui_europe),
 'rivalSquad',public.mgr_squad(case when u.hub->'next_event'->'match'->>'home'=u.hub->'coach'->>'club_id' then u.hub->'next_event'->'match'->>'away' else u.hub->'next_event'->'match'->>'home' end),
 'profile',public.profile_me()||'{"migrated_local":true}'::jsonb,
 'energy',public.energy_catalog(), 'cosmetics',public.cosmetics_catalog(), 'events',public.events_overview(),
 'scout',public.mgr_opponent_report((u.hub->'next_event'->>'fixture_id')::bigint),
 'match',u.match,'finishedMatch',u.finished,
 'career',(select to_jsonb(c) from public.careers c where c.id='22222222-2222-4222-8222-222222222222'),
 'formations',(select jsonb_agg(to_jsonb(f)) from public.sim_formations f),
 'competitions',(select jsonb_agg(to_jsonb(c)) from public.sim_competitions c),
 'fixtures',(select jsonb_agg(to_jsonb(f)) from public.season_fixtures f where f.season_id=(u.hub->'season'->>'id')::uuid))
 from ui_ctx u;
rollback;
