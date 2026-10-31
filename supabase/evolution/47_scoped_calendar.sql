-- Simulação resumida da IA, calendário local e avanço com pontos de decisão.
begin;
do $$ begin
 if to_regprocedure('public.cw_simulate_due_before_v45(uuid,integer)') is null then alter function public.cw_simulate_due(uuid,integer) rename to cw_simulate_due_before_v45;end if;
 if to_regprocedure('public.cw_step_day_before_v45(uuid)') is null then alter function public.cw_step_day(uuid) rename to cw_step_day_before_v45;end if;
 if to_regprocedure('public.career_world_advance_before_v45(integer,uuid)') is null then alter function public.career_world_advance(integer,uuid) rename to career_world_advance_before_v45;end if;
 if to_regprocedure('public.mgr_shootout_before_v45(bigint,integer)') is null then alter function public.mgr_shootout(bigint,integer) rename to mgr_shootout_before_v45;end if;
 if to_regprocedure('public.mgr_sim_fixture_before_v45(bigint,uuid)') is null then alter function public.mgr_sim_fixture(bigint,uuid) rename to mgr_sim_fixture_before_v45;end if;
end $$;

create or replace function public.cw_random(p_seed text)
returns double precision language sql immutable set search_path=public as $$
 select (('x'||substr(md5(p_seed),1,8))::bit(32)::bigint+.5)/4294967296.0
$$;
create or replace function public.cw_poisson(p_lambda double precision,p_seed text)
returns integer language plpgsql immutable set search_path=public as $$
declare u double precision:=public.cw_random(p_seed);p double precision:=exp(-p_lambda);s double precision:=p;k int:=0;
begin while u>s and k<10 loop k:=k+1;p:=p*p_lambda/k;s:=s+p;end loop;return k;end $$;

create or replace function public.mgr_shootout(p_fixture bigint, p_minute int)
returns int[] language plpgsql security definer set search_path = public as $$
declare
  v_seed text;
  v_tk_h text[];
  v_tk_a text[];
  v_fin  jsonb;
  v_gk   numeric[] := array[60, 60];
  v_gkp  text[] := array[null, null];
  v_sc   int[] := array[0, 0];
  v_k    int := 0;
  v_s    int;
  v_pid  text;
  v_n    int;
  v_done boolean := false;
  v_g1   numeric;
  v_g2   numeric;
  v_p1   text;
  v_p2   text;
begin
  select state->>'summary_seed' into v_seed from public.mgr_matches where fixture_id=p_fixture;
  if v_seed is null then return public.mgr_shootout_before_v45(p_fixture,p_minute);end if;
  select array_agg(player_id order by c_fin desc,player_id) into v_tk_h from public.mgr_match_players
   where fixture_id = p_fixture and side = 'h' and status = 'on' and pos <> 'GOL';
  select array_agg(player_id order by c_fin desc,player_id) into v_tk_a from public.mgr_match_players
   where fixture_id = p_fixture and side = 'a' and status = 'on' and pos <> 'GOL';
  select jsonb_object_agg(player_id, c_fin) into v_fin from public.mgr_match_players where fixture_id = p_fixture;
  select coalesce(max(c_gk) filter (where side = 'h' and pos = 'GOL' and status = 'on'), 45),
         coalesce(max(c_gk) filter (where side = 'a' and pos = 'GOL' and status = 'on'), 45)
    into v_g1, v_g2 from public.mgr_match_players where fixture_id = p_fixture;
  v_gk := array[v_g1, v_g2];
  select max(player_id) filter (where side = 'h' and pos = 'GOL' and status = 'on'),
         max(player_id) filter (where side = 'a' and pos = 'GOL' and status = 'on')
    into v_p1, v_p2 from public.mgr_match_players where fixture_id = p_fixture;
  v_gkp := array[v_p1, v_p2];
  if v_tk_h is null then v_tk_h := array[v_gkp[1]]; end if;
  if v_tk_a is null then v_tk_a := array[v_gkp[2]]; end if;

  while not v_done and v_k < 30 loop
    v_k := v_k + 1;
    for v_s in 1 .. 2 loop
      if v_s = 1 then v_n := array_length(v_tk_h, 1); v_pid := v_tk_h[1 + (v_k - 1) % v_n];
      else v_n := array_length(v_tk_a, 1); v_pid := v_tk_a[1 + (v_k - 1) % v_n]; end if;
      if public.cw_random(v_seed||':shootout:'||v_k||':'||v_s) < greatest(0.55, least(0.9, 0.74 + 0.004 * (coalesce((v_fin ->> v_pid)::numeric, 50) - v_gk[3 - v_s]))) then
        v_sc[v_s] := v_sc[v_s] + 1;
        perform public.mgr_event(p_fixture, p_minute, case when v_s = 1 then 'h' else 'a' end, 'so_goal', v_pid);
      else
        perform public.mgr_event(p_fixture, p_minute, case when v_s = 1 then 'h' else 'a' end, 'so_miss', v_pid, v_gkp[3 - v_s]);
      end if;
      -- decidido nas 5 primeiras?
      if v_k <= 5 then
        if v_sc[1] > v_sc[2] + (5 - v_k) + (case when v_s = 1 then 1 else 0 end)
           or v_sc[2] > v_sc[1] + (5 - v_k) then v_done := true; exit; end if;
      end if;
    end loop;
    if v_k >= 5 and v_sc[1] <> v_sc[2] then v_done := true; end if;
  end loop;
  return v_sc;
end;
$$;


create or replace function public.mgr_sim_fixture(p_fixture bigint,p_career uuid)
returns void language plpgsql security definer set search_path=public as $$
declare f public.season_fixtures;m public.mgr_matches;seed text;h int;a int;i int;v_side char;scorer text;helper text;yb int;extra_shots int;extra_sot int;extra_fouls int;possession int;
 sh numeric;sa numeric;neutral boolean;minute int;duration int:=90;et boolean:=false;
begin
 if not public.cw_runtime_enabled(p_career) then perform public.mgr_sim_fixture_before_v45(p_fixture,p_career);return;end if;
 select * into f from public.season_fixtures where id=p_fixture for update;
 if not found or not exists(select 1 from public.career_seasons where id=f.season_id and career_id=p_career) then raise exception 'Partida fora da carreira';end if;
 if f.status='played' then return;end if;
 if exists(select 1 from public.cw_world w join public.mgr_coach c using(career_id) where w.career_id=p_career and w.primary_season=f.season_id and c.status='employed' and c.club_id in(f.home_club,f.away_club)) then raise exception 'A partida do treinador exige intervenção';end if;
 if exists(select 1 from public.mgr_matches where fixture_id=p_fixture and user_side is not null) then raise exception 'Partida do usuário preservada';end if;
 perform public.mgr_match_create(p_fixture,p_career,null,null);
 select * into m from public.mgr_matches where fixture_id=p_fixture;
 select r.seed::text||':'||p_fixture||':v1' into seed from public.cw_runtime r where r.career_id=p_career;
 sh:=(m.state->'strength'->>0)::numeric;sa:=(m.state->'strength'->>1)::numeric;
 neutral:=coalesce((m.state->>'neutral')::boolean,false);
 possession:=greatest(30,least(70,round(50+(sh-sa)*.6+(public.cw_random(seed||':possession')-.5)*12)::int));
 h:=public.cw_poisson((case when neutral then 1.25 else 1.4 end)*exp(.022*(sh-sa)),seed||':home');
 a:=public.cw_poisson((case when neutral then 1.25 else 1.05 end)*exp(.022*(sa-sh)),seed||':away');
 et:=coalesce((m.state->>'extra_time_rule')::boolean,false) and h+coalesce((m.state->'agg'->>0)::int,0)=a+coalesce((m.state->'agg'->>1)::int,0);
 if et then
  duration:=120;
  h:=h+public.cw_poisson(.42*exp(.022*(sh-sa)),seed||':extra-home');
  a:=a+public.cw_poisson(.35*exp(.022*(sa-sh)),seed||':extra-away');
 end if;
 update public.mgr_matches set state=state||jsonb_build_object('summary_seed',seed,'et',et) where fixture_id=p_fixture;
 update public.mgr_match_players set minutes=case when status='on' then duration else 0 end,
 cond=case when status='on' then greatest(15,cond-.2*duration) else cond end where fixture_id=p_fixture;
 foreach v_side in array array['h'::char,'a'::char] loop
  for i in 1..case when v_side='h' then h else a end loop
   select player_id into scorer from public.mgr_match_players where fixture_id=p_fixture and mgr_match_players.side=v_side and status='on'
   order by public.cw_random(seed||':goal:'||v_side||':'||i||':'||player_id)*case when pos in('ATA','PD','PE','MEI') then 3 else 1 end desc,player_id limit 1;
   minute:=1+floor(public.cw_random(seed||':minute:'||v_side||':'||i)*89)::int;
   update public.mgr_match_players set goals=goals+1,shots=shots+1,sot=sot+1 where fixture_id=p_fixture and player_id=scorer;
   helper:=null;
   if public.cw_random(seed||':assist-chance:'||v_side||':'||i)<.72 then
    select player_id into helper from public.mgr_match_players where fixture_id=p_fixture and side=v_side and status='on' and player_id<>scorer and pos<>'GOL'
    order by public.cw_random(seed||':assist:'||v_side||':'||i||':'||player_id)*case when pos in('PD','PE','MEI','MC') then 2 else 1 end desc,player_id limit 1;
    update public.mgr_match_players set assists=assists+1 where fixture_id=p_fixture and player_id=helper;
   end if;
   perform public.mgr_event(p_fixture,minute,v_side,'goal',scorer,helper,'Gol');
  end loop;
  yb:=1+floor(public.cw_random(seed||':cards:'||v_side)*3)::int;
  for i in 1..yb loop
   select player_id into scorer from public.mgr_match_players where fixture_id=p_fixture and mgr_match_players.side=v_side and status='on' and yellow=0
   order by public.cw_random(seed||':yellow:'||v_side||':'||i||':'||player_id),player_id limit 1;
   update public.mgr_match_players set yellow=1,fouls=fouls+1 where fixture_id=p_fixture and player_id=scorer;
   perform public.mgr_event(p_fixture,10+i*20,v_side,'yellow',scorer,null,'Cartão amarelo');
  end loop;
  extra_shots:=public.cw_poisson(9.0*duration/90,seed||':shots:'||v_side);
  extra_sot:=floor(extra_shots*(.25+.2*public.cw_random(seed||':sot:'||v_side)))::int;
  extra_fouls:=public.cw_poisson(10.0*duration/90,seed||':fouls:'||v_side);
  with ranked as(select player_id,row_number() over(order by case when pos in('ATA','PD','PE','MEI') then 0 else 1 end,player_id) rn,count(*) over() n
   from public.mgr_match_players where fixture_id=p_fixture and side=v_side and status='on' and pos<>'GOL')
  update public.mgr_match_players mp set shots=shots+extra_shots/ranked.n+(ranked.rn<=extra_shots%ranked.n)::int,
   sot=sot+extra_sot/ranked.n+(ranked.rn<=extra_sot%ranked.n)::int,
   fouls=fouls+extra_fouls/ranked.n+(ranked.rn<=extra_fouls%ranked.n)::int
  from ranked where mp.fixture_id=p_fixture and mp.player_id=ranked.player_id;
  -- Sparse discipline/injury events, rather than minute-by-minute engine writes.
  if public.cw_random(seed||':red-chance:'||v_side)<.015 then
   select player_id into scorer from public.mgr_match_players where fixture_id=p_fixture and side=v_side and status='on'
   order by public.cw_random(seed||':red:'||player_id),player_id limit 1;
   minute:=20+floor(public.cw_random(seed||':red-minute:'||v_side)*(duration-20))::int;
   update public.mgr_match_players set red=1,status='sent_off',left_min=minute,minutes=minute,slot=null where fixture_id=p_fixture and player_id=scorer;
   perform public.mgr_event(p_fixture,minute,v_side,'red',scorer,null,'Cartão vermelho');
  end if;
  if public.cw_random(seed||':injury-chance:'||v_side)<.05 then
   select player_id into scorer from public.mgr_match_players where fixture_id=p_fixture and side=v_side and status='on'
   order by public.cw_random(seed||':injury:'||player_id),player_id limit 1;
   minute:=20+floor(public.cw_random(seed||':injury-minute:'||v_side)*(duration-20))::int;
   update public.mgr_match_players set injured=true,status='injured_off',left_min=minute,minutes=minute,slot=null where fixture_id=p_fixture and player_id=scorer;
   perform public.mgr_event(p_fixture,minute,v_side,'injury',scorer);
  end if;
 end loop;
 update public.mgr_match_players g set saves=(select greatest(0,coalesce(sum(sot-goals),0)) from public.mgr_match_players p where p.fixture_id=p_fixture and p.side<>g.side)
 where g.fixture_id=p_fixture and g.pos='GOL' and g.starter;
 update public.mgr_matches set minute=duration,state=state||jsonb_build_object('score',jsonb_build_array(h,a),'poss',jsonb_build_array(possession,100-possession),'corners',jsonb_build_array(public.cw_poisson(4.5,seed||':corners:h'),public.cw_poisson(4,seed||':corners:a')),'offsides',jsonb_build_array(public.cw_poisson(1.5,seed||':offside:h'),public.cw_poisson(1.5,seed||':offside:a'))) where fixture_id=p_fixture;
 -- Existing finalization owns ties, penalties, discipline, totals, bonuses and appearances.
 perform public.mgr_match_finish(p_fixture);
 update public.season_fixtures set stats=stats||jsonb_build_object('simulation','summary','algorithm',1) where id=p_fixture;
 delete from public.mgr_matches where fixture_id=p_fixture and user_side is null and status='finished';
end $$;

create or replace function public.cw_simulate_due(p_career uuid,p_limit integer default 24)
returns integer language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare w public.cw_world;own text;r record;f record;n int:=0;t timestamptz:=clock_timestamp();
begin
 if not public.cw_runtime_enabled(p_career) then return public.cw_simulate_due_before_v45(p_career,p_limit);end if;
 select * into w from public.cw_world where career_id=p_career for update;
 select club_id into own from public.mgr_coach where career_id=p_career and status='employed';
 perform public.cw_schedule(w.primary_season);
 for r in select fx.competition_id,fx.stage,fx.round_no,min(d.due_on) due_on
 from public.season_fixtures fx join public.cw_fixture_dates d on d.fixture_id=fx.id
 where fx.season_id=w.primary_season and fx.status='pending'
 group by fx.competition_id,fx.stage,fx.round_no
 having min(d.due_on)<=w.today and coalesce(max(d.due_on) filter(where own in(fx.home_club,fx.away_club)),w.today)<=w.today
 order by min(d.due_on),fx.competition_id,fx.round_no loop
  -- Complete the round's AI games in one transaction; never expose half a round.
  for f in select id from public.season_fixtures where season_id=w.primary_season and competition_id=r.competition_id and stage=r.stage and round_no=r.round_no and status='pending'
  and (own is null or own not in(home_club,away_club)) order by id loop
   perform public.mgr_sim_fixture(f.id,p_career);n:=n+1;
  end loop;
  perform public.sim_advance(w.primary_season,r.competition_id);
  perform public.cw_schedule(w.primary_season);
  exit when n>=greatest(1,p_limit) or clock_timestamp()-t>interval '1200 milliseconds';
 end loop;
 update public.cw_world set needs_sync=exists(
 select 1 from public.season_fixtures fx join public.cw_fixture_dates d on d.fixture_id=fx.id
 where fx.season_id=w.primary_season and fx.status='pending' and (own is null or own not in(fx.home_club,fx.away_club)) and d.due_on<=w.today
 and not exists(select 1 from public.season_fixtures mf join public.cw_fixture_dates md on md.fixture_id=mf.id where mf.season_id=fx.season_id and mf.competition_id=fx.competition_id and mf.stage=fx.stage and mf.round_no=fx.round_no and mf.status='pending' and own in(mf.home_club,mf.away_club) and md.due_on>w.today))
 where career_id=p_career;
 return n;
end $$;

create or replace function public.cw_step_to(p_career uuid,p_date date)
returns date language plpgsql security definer set search_path=public as $$
declare w public.cw_world;last_market date;gap int;
begin
 select * into w from public.cw_world where career_id=p_career for update;
 if w.needs_sync then raise exception 'Conclua a rodada antes de avançar';end if;
 if p_date<=w.today then return w.today;end if;
 if p_date>w.today+14 then raise exception 'Intervalo de avanço inválido';end if;
 if public.cw_attention(p_career) is not null then return w.today;end if;
 if exists(select 1 from public.mgr_matches where career_id=p_career and status='live' and user_side is not null) then raise exception 'Termine a partida em andamento';end if;
 gap:=p_date-w.today;
 perform set_config('app.cw_tick_days',gap::text,true);
 update public.cw_world set today=p_date,elapsed_days=elapsed_days+gap,last_services_on=null,needs_sync=true where career_id=p_career returning * into w;
 update public.career_seasons set day_no=w.elapsed_days where id=w.primary_season;
 perform public.cw_finance_tick(p_career);
 -- Existing negotiations/clauses are always processed, including foreign manual deals.
 perform public.cw_market_tick(p_career);
 perform public.cw_v32_tick(p_career);
 perform public.cw_jobs_tick(p_career);
 update public.cw_runtime set last_market_on=p_date,version=version+1 where career_id=p_career;
 update public.cw_world set last_services_on=p_date where career_id=p_career;
 return p_date;
end $$;
create or replace function public.cw_step_day(p_career uuid)
returns date language plpgsql security definer set search_path=public as $$
begin
 if not public.cw_runtime_enabled(p_career) then return public.cw_step_day_before_v45(p_career);end if;
 return public.cw_step_to(p_career,(select today+1 from public.cw_world where career_id=p_career));
end $$;

create or replace function public.career_world_advance(p_days integer,p_request uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
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
  exit when w.needs_sync or w.today>=target or coalesce(stopped,false) or ready or clock_timestamp()-started>interval '1200 milliseconds';
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
end $$;

-- Preserve existing RPC signature; only the active calendar is searched.
-- A fresh UUID from a stale browser tab must not apply another calendar step.
create or replace function public.career_world_prepare(p_days integer,p_request uuid,p_expected_version bigint)
returns jsonb language plpgsql security definer set search_path=public as $$
declare c public.careers;v bigint;receipt jsonb;
begin
 c:=public.mgr_lock();
 receipt:=public.cw_advance_receipt(c.id,p_request,p_days);
 if receipt is not null then return receipt;end if;
 select version into v from public.cw_runtime where career_id=c.id;
 if p_expected_version is null or p_expected_version<>v then
  return jsonb_build_object('requires_refresh',true,'stop_reason','state_changed','state_version',v,'more',false,'matches',0,'days',0);
 end if;
 return public.career_world_advance(p_days,p_request);
end $$;
revoke all on function public.career_world_prepare(integer,uuid,bigint) from public,anon;
grant execute on function public.career_world_prepare(integer,uuid,bigint) to authenticated;

create or replace function public.sim_next_event(p_season uuid,p_club text)
returns table(o_comp text,o_kind text,o_stage text,o_round int)
language sql stable security definer set search_path=public as $$
 select * from public.sim_next_event_before_world(p_season,p_club) where not exists(select 1 from public.cw_seasons where season_id=p_season)
 union all
 (select f.competition_id,case when p_club in(f.home_club,f.away_club) then 'mine' else 'free' end,f.stage,f.round_no
 from public.season_fixtures f join public.cw_fixture_dates d on d.fixture_id=f.id
 where f.season_id=p_season and f.status='pending'
 order by (p_club in(f.home_club,f.away_club)) desc nulls last,d.due_on,f.id limit 1)
$$;

-- Restore private ACLs after renames and new definitions (Postgres grants PUBLIC by default).
do $$ declare r record;begin
 for r in select p.oid::regprocedure signature from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where n.nspname='public' and (p.proname like '%\_before_v45' escape '\' or p.proname in('cw_random','cw_poisson','cw_step_to','cw_step_day','cw_simulate_due','mgr_sim_fixture','mgr_shootout','cw_materialize_club','mgr_lock','mgr_match_create','cw_settle_month_before_v38')) loop
 execute format('revoke all on function %s from public,anon,authenticated',r.signature);
 end loop;
end $$;
revoke all on function public.career_world_advance(integer,uuid) from public,anon;
grant execute on function public.career_world_advance(integer,uuid) to authenticated;
revoke all on function public.mgr_squad(text),public.mgr_player_detail(text,bigint) from public,anon;
grant execute on function public.mgr_squad(text),public.mgr_player_detail(text,bigint) to authenticated;
notify pgrst,'reload schema';
commit;
