begin;
insert into auth.users(id) values('11111111-1111-4111-8111-111111111111');
insert into public.careers(id,user_id,nickname,club_id,country,age,bonus_energy)
values('22222222-2222-4222-8222-222222222222','11111111-1111-4111-8111-111111111111','Coach UI','palmeiras','BR',30,1000);
select set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',true) is not null;
create temp table ui_ctx as select public.mgr_hub() as hub;
select jsonb_build_object(
 'hub',u.hub,'squad',public.mgr_squad(),
 'scout',public.mgr_opponent_report((u.hub->'next_event'->>'fixture_id')::bigint),
 'match',public.mgr_match_start(),
 'career',(select to_jsonb(c) from public.careers c where c.id='22222222-2222-4222-8222-222222222222'),
 'formations',(select jsonb_agg(to_jsonb(f)) from public.sim_formations f),
 'competitions',(select jsonb_agg(to_jsonb(c)) from public.sim_competitions c),
 'fixtures',(select jsonb_agg(to_jsonb(f)) from public.season_fixtures f where f.season_id=(u.hub->'season'->>'id')::uuid))
 from ui_ctx u;
rollback;
