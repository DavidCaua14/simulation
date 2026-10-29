begin;
create or replace function public.cw_region(p_club text)
returns text language sql stable set search_path=public as $$
 select coalesce(region,case when country in('ENG','WAL','ESP','ITA','GER','FRA','POR','NED','BEL','SCO','AUT','SUI','CZE','TUR','UKR','NOR','GRE','SVK','AZE') then 'ENG' else 'BRA' end) from public.sim_clubs where id=p_club
$$;
create or replace function public.cw_year(p_region text,p_date date)
returns int language sql immutable as $$select extract(year from p_date)::int-case when p_region='ENG' and extract(month from p_date)<7 then 1 else 0 end$$;
create or replace function public.cw_start(p_region text,p_year int)
returns date language sql immutable as $$select make_date(p_year,case when p_region='ENG' then 7 else 1 end,1)$$;
create or replace function public.cw_window_open(p_region text,p_date date)
returns boolean language sql stable security definer set search_path=public as $$
 select exists(select 1 from public.cw_windows w where w.region=p_region and p_date between make_date(extract(year from p_date)::int,w.start_month,w.start_day) and make_date(extract(year from p_date)::int,w.end_month,w.end_day))
$$;
create or replace function public.cw_next_window(p_region text,p_date date)
returns date language sql stable security definer set search_path=public as $$
 select min(make_date(extract(year from p_date)::int+y.n,w.start_month,w.start_day)) from public.cw_windows w cross join generate_series(0,1) as y(n)
 where w.region=p_region and make_date(extract(year from p_date)::int+y.n,w.start_month,w.start_day)>=p_date
$$;
create or replace function public.cw_deadline(p_date date)
returns date language sql stable security definer set search_path=public as $$select p_date+max_negotiation_days from public.cw_rules$$;
create or replace function public.cw_news_add(p_career uuid,p_key text,p_kind text,p_title text,p_body text,p_priority int default 40,p_club text default null,p_player text default null,p_season uuid default null,p_meta jsonb default '{}')
returns void language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
begin
 insert into public.cw_news(career_id,event_key,on_date,kind,title,body,priority,club_id,player_id,season_id,metadata)
 select p_career,p_key,today,p_kind,p_title,p_body,p_priority,p_club,p_player,p_season,p_meta from public.cw_world where career_id=p_career on conflict do nothing;
end $$;
create or replace function public.cw_schedule(p_season uuid)
returns int language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare n int:=0;r record;chosen date;
begin
 for r in
 select f.id,f.season_id,f.home_club,f.away_club,s.career_id,s.ends_on,
 least(s.ends_on,greatest(s.starts_on,s.starts_on+case
  when public.sim_phase(f.competition_id,f.stage)->>'type'='league' then 14+(f.round_no-1)*greatest(1,330/greatest(coalesce((c.rules->>'calendar_rounds')::int,38)-1,1))
  when public.sim_phase(f.competition_id,f.stage)->>'type' in('groups','group','swiss') then 60+(f.round_no-1)*18
  when c.kind='continental' then 210+greatest(0,public.sim_phase_index(f.competition_id,f.stage)-2)*28+greatest(coalesce(f.leg,1)-1,0)*7
  else 90+greatest(0,public.sim_phase_index(f.competition_id,f.stage)-1)*50+greatest(coalesce(f.leg,1)-1,0)*7 end)) as proposed
 from public.season_fixtures f join public.cw_seasons s on s.season_id=f.season_id join public.sim_competitions c on c.id=f.competition_id
 where f.season_id=p_season and f.status='pending' and not exists(select 1 from public.cw_fixture_dates d where d.fixture_id=f.id)
 order by exists(select 1 from public.mgr_matches m where m.fixture_id=f.id and m.status='live' and m.user_side is not null) desc,proposed,c.sort_order,f.id loop
  chosen:=case when exists(select 1 from public.mgr_matches m where m.fixture_id=r.id and m.status='live' and m.user_side is not null) then (select today from public.cw_world where career_id=r.career_id) when r.season_id=(select primary_season from public.cw_world where career_id=r.career_id) then greatest(r.proposed,(select today from public.cw_world where career_id=r.career_id)) else r.proposed end;
  while exists(select 1 from public.cw_club_dates d where d.career_id=r.career_id and d.club_id in(r.home_club,r.away_club) and d.due_on between chosen-1 and chosen+1) loop
   chosen:=chosen+1;
   if chosen>r.ends_on+45 then raise exception 'Calendário sem data válida';end if;
  end loop;
  insert into public.cw_fixture_dates values(r.id,r.season_id,r.career_id,chosen);
  insert into public.cw_club_dates values(r.career_id,r.home_club,chosen,r.id),(r.career_id,r.away_club,chosen,r.id);
  n:=n+1;
 end loop;
 return n;
end $$;
create or replace function public.cw_create_region(p_career uuid,p_region text,p_year int)
returns uuid language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare sid uuid;seq int;co record;phase jsonb;starts date;
begin
 perform 1 from public.careers where id=p_career for update;
 select season_id into sid from public.cw_seasons where career_id=p_career and region=p_region and year=p_year;
 if sid is not null then return sid;end if;
 -- Reuse legacy regional history; a completed year must never be generated twice.
 select cs.id into sid from public.career_seasons cs where cs.career_id=p_career and cs.region=p_region and cs.year=p_year and cs.mode in('coach','world') order by cs.season_no desc limit 1;
 if sid is not null then
  starts:=public.cw_start(p_region,p_year);
  insert into public.cw_seasons(career_id,region,year,season_id,starts_on,ends_on) values(p_career,p_region,p_year,sid,starts,(starts+interval '1 year - 1 day')::date);
  update public.career_seasons set was_coached=was_coached or mode='coach' where id=sid;
  if(select status from public.career_seasons where id=sid)='active' then perform public.cw_schedule(sid);end if;
  return sid;
 end if;
 if not exists(select 1 from public.sim_competitions where region=p_region and active) then raise exception 'Região sem competições cadastradas';end if;
 select coalesce(max(season_no),0)+1 into seq from public.career_seasons where career_id=p_career;
 insert into public.career_seasons(career_id,season_no,year,club_id,region,mode,day_no)
 values(p_career,seq,p_year,null,p_region,'world',coalesce((select elapsed_days from public.cw_world where career_id=p_career),0)) returning id into sid;
 perform public.mgr_init_world(p_career);perform public.cw_initialize_finances(p_career);
 starts:=public.cw_start(p_region,p_year);
 insert into public.cw_seasons(career_id,region,year,season_id,starts_on,ends_on) values(p_career,p_region,p_year,sid,starts,(starts+interval '1 year - 1 day')::date);
 perform public.sim_participants_build(sid);
 for co in select * from public.sim_competitions where region=p_region and active order by sort_order loop
  phase:=public.sim_phase_at(co.id,1);
  insert into public.season_competitions(season_id,competition_id,stage) values(sid,co.id,phase->>'id');
  perform public.sim_phase_create(sid,co.id,phase->>'id',null);
 end loop;
 perform public.cw_schedule(sid);return sid;
end $$;
create or replace function public.cw_ensure(p_career uuid)
returns void language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare s public.career_seasons;starts date;current_day date;v_region text;sid uuid;
begin
 perform 1 from public.careers where id=p_career for update;
 if exists(select 1 from public.cw_world where career_id=p_career) then return;end if;
 select * into s from public.career_seasons where career_id=p_career and mode='coach' order by season_no desc limit 1;
 if not found then raise exception 'Carreira de treinador não inicializada';end if;
 starts:=public.cw_start(s.region,s.year);
 current_day:=case when s.status='finished' then(starts+interval '1 year - 1 day')::date else least((starts+interval '1 year - 1 day')::date,starts+s.day_no*3) end;
 -- Legacy careers advanced regions sequentially. Do not move the global date behind an already completed regional year.
 select greatest(current_day,coalesce(max((public.cw_start(cs.region,cs.year)+interval '1 year - 1 day')::date),current_day)) into current_day
 from public.career_seasons cs where cs.career_id=p_career and cs.mode='coach' and (cs.status='finished' or(cs.status='archived' and not exists(select 1 from public.season_fixtures fx where fx.season_id=cs.id and fx.status='pending')));
 insert into public.cw_world(career_id,today,started_on,elapsed_days,primary_season) values(p_career,current_day,current_day,s.day_no,s.id) on conflict do nothing;
 insert into public.cw_coach(career_id,monthly_salary,contract_until) select p_career,round(70+reputation*3)::bigint,(current_day+interval '2years')::date from public.mgr_coach where career_id=p_career on conflict do nothing;
 insert into public.cw_seasons(career_id,region,year,season_id,starts_on,ends_on) values(p_career,s.region,s.year,s.id,starts,(starts+interval '1 year - 1 day')::date) on conflict do nothing;
 update public.career_seasons set was_coached=true where id=s.id;
 perform public.mgr_init_world(p_career);
 perform public.cw_initialize_finances(p_career);
 perform public.cw_schedule(s.id);
 for v_region in select distinct comp.region from public.sim_competitions comp where comp.active and comp.region<>s.region loop
  sid:=public.cw_create_region(p_career,v_region,public.cw_year(v_region,current_day));
  if(select status from public.career_seasons where id=sid)<>'active' then sid:=public.cw_create_region(p_career,v_region,public.cw_year(v_region,current_day)+1);end if;
 end loop;
 update public.season_offers set expires_on=current_day+greatest(1,coalesce(expires_day-s.day_no,7)),
 salary=coalesce(salary,150),contract_years=coalesce(contract_years,2),budget_guarantee=coalesce(budget_guarantee,0)
 where career_id=p_career and status='pending' and kind='coach' and expires_on is null;
 perform public.cw_news_add(p_career,'world:created','world','O mundo do futebol está em movimento',
 'Brasil e Europa agora seguem calendários próprios na sua carreira. Contratos, finanças e notícias evoluem com os dias.',65,s.club_id);
end $$;

-- Process bounded batches with the existing match engine. No outcome/statistic is fabricated for news.
create or replace function public.cw_simulate_due(p_career uuid,p_limit int default 24)
returns int language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare w public.cw_world;f public.season_fixtures;s public.career_seasons;co public.mgr_coach;n int:=0;m public.mgr_matches;round_due record;sid uuid;v_region text;yr int;budget int;batch_started timestamptz:=clock_timestamp();
begin
 select * into w from public.cw_world where career_id=p_career for update;
 select * into co from public.mgr_coach where career_id=p_career;
 budget:=least(greatest(p_limit,1),(select max_matches_per_batch from public.cw_rules));
 for s in select cs.* from public.career_seasons cs join public.cw_seasons ws on ws.season_id=cs.id where ws.career_id=p_career and cs.status='active' loop perform public.cw_schedule(s.id);end loop;
 for round_due in
  select fx.season_id,fx.competition_id,fx.stage,fx.round_no,min(d.due_on) as due_on
  from public.season_fixtures fx join public.cw_fixture_dates d on d.fixture_id=fx.id join public.career_seasons cs on cs.id=fx.season_id
  where d.career_id=p_career and d.due_on<=w.today and fx.status='pending' and cs.status='active'
  group by fx.season_id,fx.competition_id,fx.stage,fx.round_no
  order by min(d.due_on),fx.season_id,fx.competition_id,fx.round_no loop
  for f in select * from public.season_fixtures where season_id=round_due.season_id and competition_id=round_due.competition_id and stage=round_due.stage and round_no=round_due.round_no and status='pending' and not(season_id=w.primary_season and co.status='employed' and co.club_id in(home_club,away_club)) and exists(select 1 from public.cw_fixture_dates fd where fd.fixture_id=season_fixtures.id and fd.due_on<=w.today) order by id loop
   exit when n>=budget or clock_timestamp()-batch_started>interval '2 seconds';
   -- The existing helper handles both halves, extra time and penalties before finalizing.
   perform public.mgr_sim_fixture(f.id,p_career);
   n:=n+1;
  end loop;
  perform public.sim_advance(round_due.season_id,round_due.competition_id);
  perform public.cw_schedule(round_due.season_id);
  exit when n>=budget or clock_timestamp()-batch_started>interval '2 seconds';
 end loop;
 for s in select cs.* from public.career_seasons cs join public.cw_seasons ws on ws.season_id=cs.id where ws.career_id=p_career and cs.status='active' and cs.mode='world'
  and not exists(select 1 from public.season_fixtures f where f.season_id=cs.id and status='pending') loop
  perform public.sim_season_transition(s.id);
  update public.career_seasons set status='finished',finished_at=now(),summary=jsonb_build_object('world',true,'transition',public.sim_season_transition(s.id)) where id=s.id;
 end loop;
 -- Rollover uses the completed regional history, never a fixed team list.
 for v_region in select distinct comp.region from public.sim_competitions comp where comp.active loop
  yr:=public.cw_year(v_region,w.today);
  if not exists(select 1 from public.cw_seasons where career_id=p_career and cw_seasons.region=v_region and year=yr)
   and not exists(select 1 from public.career_seasons cs join public.cw_seasons ws on ws.season_id=cs.id where ws.career_id=p_career and ws.region=v_region and cs.status='active') then
   sid:=public.cw_create_region(p_career,v_region,yr);
  end if;
  -- Prepare the next year during the off-season, using the completed regional standings.
  if not exists(select 1 from public.career_seasons cs where cs.career_id=p_career and cs.region=v_region and cs.mode in('coach','world') and cs.status='active') then
   select greatest(yr,coalesce(max(ws.year)+1,yr)) into yr from public.cw_seasons ws where ws.career_id=p_career and ws.region=v_region;
   sid:=public.cw_create_region(p_career,v_region,yr);
  end if;
 end loop;
 update public.cw_world set needs_sync=exists(
  select 1 from public.season_fixtures fx join public.cw_fixture_dates d on d.fixture_id=fx.id join public.career_seasons cs on cs.id=fx.season_id
  where d.career_id=p_career and d.due_on<=w.today and fx.status='pending' and cs.status='active'
  and not(fx.season_id=w.primary_season and co.status='employed' and co.club_id in(fx.home_club,fx.away_club)))
 where career_id=p_career;
 return n;
end $$;

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
  injured_until=case when injured_until<=w.elapsed_days then null else injured_until end where career_id=p_career;
 perform public.cw_finance_tick(p_career);
 perform public.cw_market_tick(p_career);
 perform public.cw_jobs_tick(p_career);
 update public.cw_world set last_services_on=w.today where career_id=p_career;
 return w.today;
end $$;
-- All helpers are private; public APIs are installed together in 29.
do $$ declare f record;begin
 for f in select p.oid::regprocedure as sig from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace where ns.nspname='public' and p.proname like 'cw_%' loop
  execute format('revoke all on function %s from public,anon,authenticated,service_role',f.sig);
 end loop;
end $$;
commit;
