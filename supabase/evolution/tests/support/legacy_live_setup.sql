-- Preparação ANTES da migração; apenas banco descartável do runner.
insert into auth.users(id) values('21212121-0000-0000-0000-000000000001');
insert into public.careers(id,user_id,nickname,club_id,country,age,bonus_energy) values
('21212121-0000-0000-0000-0000000000ca','21212121-0000-0000-0000-000000000001','legacy_live','palmeiras','BR',30,1000);
select set_config('request.jwt.claim.sub','21212121-0000-0000-0000-000000000001',false);
select public.mgr_hub() is not null;
select public.mgr_match_start() is not null;
select public.mgr_match_step((select fixture_id from public.mgr_matches where career_id='21212121-0000-0000-0000-0000000000ca' and user_side is not null),0,20,null,false,0) is not null;
-- Resultado antigo e finalizado, independente da partida em andamento.
update public.season_fixtures set status='played',home_goals=2,away_goals=1,played_at=now()
 where id=(select f.id from public.season_fixtures f join public.career_seasons s on s.id=f.season_id
  where s.career_id='21212121-0000-0000-0000-0000000000ca' and f.competition_id='brasileirao' and not exists(select 1 from public.mgr_matches m where m.fixture_id=f.id) order by f.id limit 1);
create table public.test_upgrade_snapshot as select m.fixture_id,to_jsonb(m) as match_data,
 (select jsonb_agg(to_jsonb(p) order by p.player_id) from public.mgr_match_players p where p.fixture_id=m.fixture_id) as players,
 (select jsonb_agg(to_jsonb(e) order by e.seq) from public.mgr_match_events e where e.fixture_id=m.fixture_id) as events,
 (select to_jsonb(c) from public.careers c where c.id=m.career_id) as career,
 (select jsonb_agg(to_jsonb(f) order by f.id) from public.season_fixtures f where f.season_id=m.season_id and f.status='played') as played
 from public.mgr_matches m where m.career_id='21212121-0000-0000-0000-0000000000ca' and m.user_side is not null;
