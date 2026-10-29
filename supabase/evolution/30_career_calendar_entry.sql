begin;
set local lock_timeout='5s';
select pg_advisory_xact_lock(hashtext('career-calendar-entry-v2'));
alter table public.cw_world add column if not exists parallel_entry_aligned boolean not null default false;
alter table public.cw_seasons add column if not exists calendar_shift int not null default 0 check(calendar_shift>=0);
-- The deployment itself never changes progress or existing match dates.
create temp table cw_entry_results on commit drop as select id,to_jsonb(f) as original from public.season_fixtures f where status='played';
create temp table cw_entry_live on commit drop as select fixture_id,to_jsonb(m) as original from public.mgr_matches m where status='live';
create temp table cw_entry_wallet on commit drop as select id,to_jsonb(c) as original from public.careers c;
-- Lazily repair only unplayed foreign schedules. No catch-up results are invented.
create or replace function public.cw_schedule(p_season uuid)
returns int language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare n int:=0;r record;chosen date;
begin
 for r in
 select f.id,f.season_id,f.home_club,f.away_club,s.career_id,s.ends_on+s.calendar_shift as ends_on,
 least(s.ends_on+s.calendar_shift,greatest(s.starts_on+s.calendar_shift,s.starts_on+s.calendar_shift+case
  when public.sim_phase(f.competition_id,f.stage)->>'type'='league' then 14+(f.round_no-1)*greatest(1,330/greatest(coalesce((c.rules->>'calendar_rounds')::int,38)-1,1))
  when public.sim_phase(f.competition_id,f.stage)->>'type' in('groups','group','swiss') then 60+(f.round_no-1)*18
  when c.kind='continental' then 210+greatest(0,public.sim_phase_index(f.competition_id,f.stage)-2)*28+greatest(coalesce(f.leg,1)-1,0)*7
  else 90+greatest(0,public.sim_phase_index(f.competition_id,f.stage)-1)*50+greatest(coalesce(f.leg,1)-1,0)*7 end)) as proposed
 from public.season_fixtures f join public.cw_seasons s on s.season_id=f.season_id join public.sim_competitions c on c.id=f.competition_id
 where f.season_id=p_season and f.status='pending' and not exists(select 1 from public.cw_fixture_dates d where d.fixture_id=f.id)
 order by exists(select 1 from public.mgr_matches m where m.fixture_id=f.id and m.status='live' and m.user_side is not null) desc,proposed,c.sort_order,f.id loop
  chosen:=case when exists(select 1 from public.mgr_matches m where m.fixture_id=r.id and m.status='live' and m.user_side is not null) then (select today from public.cw_world where career_id=r.career_id) else greatest(r.proposed,(select today from public.cw_world where career_id=r.career_id)) end;
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
 insert into public.cw_seasons(career_id,region,year,season_id,starts_on,ends_on,calendar_shift) values(p_career,p_region,p_year,sid,starts,(starts+interval '1 year - 1 day')::date,greatest(0,(select today from public.cw_world where career_id=p_career)-starts));
 perform public.sim_participants_build(sid);
 for co in select * from public.sim_competitions where region=p_region and active order by sort_order loop
  phase:=public.sim_phase_at(co.id,1);
  insert into public.season_competitions(season_id,competition_id,stage) values(sid,co.id,phase->>'id');
  perform public.sim_phase_create(sid,co.id,phase->>'id',null);
 end loop;
 perform public.cw_schedule(sid);return sid;
end $$;
create or replace function public.cw_align_parallel_entry(p_career uuid)
returns void language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare w public.cw_world;s record;first_due date;delta int;
begin
 perform 1 from public.careers where id=p_career for update;
 select * into w from public.cw_world where career_id=p_career for update;
 if not found or w.parallel_entry_aligned then return;end if;
 -- Preserve even the dates of an interrupted interactive match.
 if exists(select 1 from public.mgr_matches where career_id=p_career and status='live' and user_side is not null) then return;end if;
 for s in select ws.season_id from public.cw_seasons ws join public.career_seasons cs on cs.id=ws.season_id
  where ws.career_id=p_career and ws.season_id<>w.primary_season and cs.status='active' loop
  select min(fd.due_on) into first_due from public.cw_fixture_dates fd join public.season_fixtures f on f.id=fd.fixture_id
   where fd.season_id=s.season_id and f.status='pending';
  if first_due<w.today then
   delta:=w.today+2-first_due;
   -- Remove/reinsert reservations so positive shifts cannot hit their own old unique keys.
   delete from public.cw_club_dates cd using public.season_fixtures f where cd.fixture_id=f.id and f.season_id=s.season_id and f.status='pending';
   update public.cw_fixture_dates fd set due_on=due_on+delta from public.season_fixtures f
    where fd.fixture_id=f.id and f.season_id=s.season_id and f.status='pending';
   update public.cw_seasons set calendar_shift=calendar_shift+delta where season_id=s.season_id;
   insert into public.cw_club_dates(career_id,club_id,due_on,fixture_id)
    select fd.career_id,c.club_id,fd.due_on,f.id from public.season_fixtures f join public.cw_fixture_dates fd on fd.fixture_id=f.id
    cross join lateral(values(f.home_club),(f.away_club))c(club_id) where f.season_id=s.season_id and f.status='pending';
  end if;
 end loop;
 update public.cw_world set parallel_entry_aligned=true,needs_sync=exists(
  select 1 from public.cw_fixture_dates fd join public.season_fixtures f on f.id=fd.fixture_id join public.career_seasons cs on cs.id=f.season_id
  left join public.mgr_coach co on co.career_id=fd.career_id and co.status='employed'
  where fd.career_id=p_career and cs.status='active' and f.status='pending' and fd.due_on<=w.today
  and not(f.season_id=w.primary_season and co.club_id is not null and co.club_id in(f.home_club,f.away_club)))
 where career_id=p_career;
end $$;
create or replace function public.cw_ensure(p_career uuid)
returns void language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare s public.career_seasons;starts date;current_day date;v_region text;sid uuid;
begin
 perform 1 from public.careers where id=p_career for update;
 if exists(select 1 from public.cw_world where career_id=p_career) then perform public.cw_align_parallel_entry(p_career);return;end if;
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
 perform public.cw_align_parallel_entry(p_career);
end $$;

revoke all on function public.cw_schedule(uuid),public.cw_create_region(uuid,text,int),public.cw_align_parallel_entry(uuid),public.cw_ensure(uuid) from public,anon,authenticated,service_role;
do $preserved$ begin
 if exists(select 1 from cw_entry_results b left join public.season_fixtures f using(id) where b.original is distinct from to_jsonb(f)) then raise exception 'Calendar deployment changed a played result';end if;
 if exists(select 1 from cw_entry_live b left join public.mgr_matches m using(fixture_id) where b.original is distinct from to_jsonb(m)) then raise exception 'Calendar deployment changed a live match';end if;
 if exists(select 1 from cw_entry_wallet b left join public.careers c using(id) where b.original is distinct from to_jsonb(c)) then raise exception 'Calendar deployment changed a user wallet';end if;
end $preserved$;
commit;
