-- EVOLUÇÃO 31: "Avançar para a próxima partida" mais rápido e sem estourar o tempo limite da API.
-- Só substitui duas funções (create or replace). Não altera tabelas nem dados de carreiras, jogadores ou resultados.
--  * career_world_advance: cada chamada trabalha no máximo ~1,2 s (antes 3 s) e simula até 12 jogos por lote
--    (antes 24). Com o tempo de cada etapa somado, a chamada antiga podia passar de 8 s (limite do papel
--    authenticated no Supabase) e voltar erro. O app continua os lotes sozinho (flag "more").
--  * cw_step_day: a recuperação diária do elenco só atualiza linhas que mudam (condição < 100, ritmo ≠ 35 ou
--    lesão em andamento). O resultado é idêntico; antes regravava todos os atletas de todos os clubes por dia.
begin;
create or replace function public.cw_step_day(p_career uuid)
returns date language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare w public.cw_world;
begin
 select * into w from public.cw_world where career_id=p_career for update;
 if w.needs_sync then raise exception 'Conclua a atualização do calendário antes de avançar outro dia';end if;
 if exists(select 1 from public.mgr_matches where career_id=p_career and status='live' and user_side is not null) then raise exception 'Termine a partida em andamento';end if;
 update public.cw_world set today=today+1,elapsed_days=elapsed_days+1,last_services_on=null,needs_sync=true where career_id=p_career returning * into w;
 update public.career_seasons set day_no=w.elapsed_days where career_id=p_career and status='active' and mode in('coach','world');
 update public.mgr_players set condition=least(100,condition+4.3),rhythm=greatest(35,rhythm-.4),
  injury=case when injured_until<=w.elapsed_days then null else injury end,
  injured_until=case when injured_until<=w.elapsed_days then null else injured_until end
  where career_id=p_career and (condition<100 or rhythm is distinct from 35 or injured_until is not null or injury is not null);
 perform public.cw_finance_tick(p_career);
 perform public.cw_market_tick(p_career);
 perform public.cw_jobs_tick(p_career);
 update public.cw_world set last_services_on=w.today where career_id=p_career;
 return w.today;
end $$;
revoke all on function public.cw_step_day(uuid) from public,anon,authenticated,service_role;

create or replace function public.career_world_advance(p_days int,p_request uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare car public.careers;w public.cw_world;c public.mgr_coach;prev jsonb;days int:=0;n int:=0;t timestamptz:=clock_timestamp();sid uuid;summary jsonb;stopped boolean;ready boolean;s public.career_seasons;
begin
 car:=public.mgr_lock();prev:=public.econ_request_get(car.id,p_request,'world_advance');if prev is not null then return prev;end if;
 if p_days is null or (p_days<0 or p_days>(select max_days_per_call from public.cw_rules)) then raise exception 'Quantidade de dias acima do limite por atualização';end if;
 if exists(select 1 from public.mgr_matches where career_id=car.id and status='live' and user_side is not null) then raise exception 'Termine a partida em andamento';end if;
 loop
  n:=n+public.cw_simulate_due(car.id,12);select * into w from public.cw_world where career_id=car.id;select * into c from public.mgr_coach where career_id=car.id;
  select * into s from public.career_seasons where id=w.primary_season;
  exit when w.needs_sync or days>=p_days or clock_timestamp()-t>interval '1200 milliseconds';
  exit when s.status='finished' and w.today>=public.cw_start(s.region,s.year+1);
  exit when exists(select 1 from public.season_fixtures f join public.cw_fixture_dates fd on fd.fixture_id=f.id where f.season_id=w.primary_season and f.status='pending' and c.club_id in(f.home_club,f.away_club) and fd.due_on<=w.today);
  perform public.cw_step_day(car.id);days:=days+1;
 end loop;
 if not exists(select 1 from public.season_fixtures where season_id=w.primary_season and status='pending') and(select status from public.career_seasons where id=w.primary_season)='active' then summary:=public.mgr_season_end(w.primary_season);end if;
 select exists(select 1 from public.season_fixtures f join public.cw_fixture_dates fd on fd.fixture_id=f.id where f.season_id=w.primary_season and f.status='pending' and c.club_id in(f.home_club,f.away_club) and fd.due_on<=w.today) into stopped;
 select cs.status='finished' and w.today>=public.cw_start(cs.region,cs.year+1) into ready from public.career_seasons cs where cs.id=w.primary_season;
 return public.econ_request_save(car.id,p_request,'world_advance',jsonb_build_object('today',w.today,'days',days,'days_remaining',greatest(0,p_days-days),'stopped_for_match',stopped,'next_season_ready',ready,'matches',n,'more',w.needs_sync,'rounds','[]'::jsonb,'offers','[]'::jsonb,'season_finished',summary is not null,'season_summary',summary));
end $$;
revoke all on function public.career_world_advance(int,uuid) from public,anon,service_role;
grant execute on function public.career_world_advance(int,uuid) to authenticated;
notify pgrst,'reload schema';
commit;
