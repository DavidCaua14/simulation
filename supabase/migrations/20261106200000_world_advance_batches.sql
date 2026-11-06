-- Preparação da partida mais rápida e sem lote vazio (2026-11-06).
-- Medição em produção: cada lote parava em 1,2 s; com a CPU do banco ocupada, o lote podia terminar
-- sem avançar nenhum dia nem jogo, e o app mostrava "O calendário não avançou". Agora o lote só para
-- pelo tempo depois de algum progresso, e o orçamento sobe para 2 s (com folga: um passo ainda pode
-- somar ~3 s antes do limite de 8 s do PostgREST). Menos lotes por preparação = menos idas e voltas.

CREATE OR REPLACE FUNCTION public.career_world_advance(p_days integer, p_request uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
#variable_conflict use_column
declare car public.careers;w public.cw_world;c public.mgr_coach;s public.career_seasons;prev jsonb;result jsonb;attention jsonb;
 started timestamptz:=clock_timestamp();from_date date;target date;next_date date;due date;boundary date;summary jsonb;n int:=0;stopped boolean:=false;ready boolean:=false;
begin
 car:=public.mgr_lock();
 if not(select enabled from public.cw_runtime_rules) then raise exception 'Calendário temporariamente pausado. Seu progresso está preservado';end if;
 if not public.cw_runtime_enabled(car.id) then return public.career_world_advance_before_v45(p_days,p_request);end if;
 if p_days is null or p_days<0 or p_days>(select max_days_per_call from public.cw_rules) then raise exception 'Quantidade de dias acima do limite por atualização';end if;
 prev:=public.cw_advance_receipt(car.id,p_request,p_days);if prev is not null then return prev;end if;
 if exists(select 1 from public.mgr_matches where career_id=car.id and status='live' and user_side is not null) then raise exception 'Termine a partida em andamento';end if;
 select * into w from public.cw_world where career_id=car.id;from_date:=w.today;target:=w.today+p_days;
 loop
  n:=n+public.cw_simulate_due(car.id,24);
  select * into w from public.cw_world where career_id=car.id;
  select * into c from public.mgr_coach where career_id=car.id;
  select * into s from public.career_seasons where id=w.primary_season;
  -- Close a completed season before a new job interrupts time advancement.
  -- Otherwise an unemployed coach can receive successive offers forever without closing the year.
  if s.status='active' and not w.needs_sync
   and not exists(select 1 from public.season_fixtures where season_id=s.id and status='pending')
   and not exists(select 1 from public.season_competitions where season_id=s.id and status<>'finished') then
   summary:=public.mgr_season_end(s.id);select * into s from public.career_seasons where id=s.id;
  end if;
  attention:=public.cw_attention(car.id);exit when attention is not null;
  select min(d.due_on) into due from public.season_fixtures f join public.cw_fixture_dates d on d.fixture_id=f.id
   where f.season_id=w.primary_season and f.status='pending' and c.club_id in(f.home_club,f.away_club);
  stopped:=due<=w.today;
  ready:=s.status='finished' and w.today>=public.cw_start(s.region,s.year+1);
  exit when w.needs_sync or w.today>=target or coalesce(stopped,false) or ready
   -- Orçamento do lote: só encerra depois de algum progresso (dia ou jogo), senão o app recebe um lote vazio.
   or (clock_timestamp()-started>interval '2000 milliseconds' and (n>0 or w.today>from_date));
  next_date:=least(target,coalesce(due,target),w.today+(select market_interval from public.cw_runtime_rules),
   (date_trunc('month',w.today)+interval '1 month')::date,
   case when extract(day from w.today)<15 then date_trunc('month',w.today)::date+14 else (date_trunc('month',w.today)+interval '1 month')::date end);
  select min(reply_on) into boundary from public.cw_negotiations where career_id=car.id and status in('club_pending','player_pending') and reply_on>w.today;
  next_date:=least(next_date,coalesce(boundary,next_date));
  select contract_until-7 into boundary from public.cw_coach where career_id=car.id and contract_until-7>w.today;
  next_date:=least(next_date,coalesce(boundary,next_date));
  select contract_until-1 into boundary from public.cw_coach where career_id=car.id and contract_until-1>w.today;
  next_date:=least(next_date,coalesce(boundary,next_date));
  select min(expires_on+1) into boundary from public.cw_contracts where career_id=car.id and status='active' and expires_on>=w.today;
  next_date:=least(next_date,coalesce(boundary,next_date));
  select min(expires_on-7) into boundary from public.cw_contracts where career_id=car.id and club_id=c.club_id and status='active' and expires_on-7>w.today;
  next_date:=least(next_date,coalesce(boundary,next_date));
  select min(expires_on-1) into boundary from public.cw_contracts where career_id=car.id and club_id=c.club_id and status='active' and expires_on-1>w.today;
  next_date:=least(next_date,coalesce(boundary,next_date));
  select min(register_on) into boundary from public.cw_negotiations where career_id=car.id and status in('agreed','precontract') and register_on>w.today;
  next_date:=least(next_date,coalesce(boundary,next_date));
  select min(expires_on-1) into boundary from public.season_offers where career_id=car.id and kind='coach' and status='pending' and expires_on-1>w.today;
  next_date:=least(next_date,coalesce(boundary,next_date));
  select min(expires_on-1) into boundary from public.cw_negotiations where career_id=car.id and status in('seller_review','club_counter','player_counter') and expires_on-1>w.today;
  next_date:=least(next_date,coalesce(boundary,next_date));
  if s.status='finished' then next_date:=least(next_date,public.cw_start(s.region,s.year+1));end if;
  perform public.cw_step_to(car.id,next_date);
 end loop;
 select * into w from public.cw_world where career_id=car.id;
 if attention is null and not w.needs_sync and not exists(select 1 from public.season_fixtures where season_id=w.primary_season and status='pending') and (select status from public.career_seasons where id=w.primary_season)='active' then summary:=public.mgr_season_end(w.primary_season);end if;
 perform public.cw_recover_club(car.id,c.club_id);
 update public.cw_runtime set version=version+1 where career_id=car.id;
 result:=jsonb_build_object('today',w.today,'days',w.today-from_date,'days_remaining',greatest(0,target-w.today),'matches',n,
 'more',w.needs_sync and attention is null,'stopped_for_match',coalesce(stopped,false),'next_season_ready',ready,
 'stop_reason',case when attention is not null then 'decision_required' when stopped then 'match' when ready then 'season_boundary' else 'batch' end,
 'requires_attention',attention is not null,'attention',attention,'rounds','[]'::jsonb,'offers','[]'::jsonb,
 'season_finished',summary is not null,'season_summary',summary,'state_version',(select version from public.cw_runtime where career_id=car.id));
 insert into public.cw_operations(career_id,request_id,kind,parameters,result) values(car.id,p_request,'advance',jsonb_build_object('days',p_days),result);
 insert into public.cw_runtime_metrics(career_id,calls,total_ms,max_ms,matches,days)
 values(car.id,1,extract(epoch from(clock_timestamp()-started))*1000,extract(epoch from(clock_timestamp()-started))*1000,n,w.today-from_date)
 on conflict(career_id) do update set calls=cw_runtime_metrics.calls+1,total_ms=cw_runtime_metrics.total_ms+excluded.total_ms,max_ms=greatest(cw_runtime_metrics.max_ms,excluded.max_ms),matches=cw_runtime_metrics.matches+excluded.matches,days=cw_runtime_metrics.days+excluded.days;
 return result;
end $function$;
