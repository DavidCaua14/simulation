-- Runtime por país. Funções anteriores ficam disponíveis para recuperação.

begin;

do $$ begin if to_regprocedure('public.mgr_lock_before_v45()') is null then alter function public.mgr_lock() rename to mgr_lock_before_v45;end if;end $$;

CREATE OR REPLACE FUNCTION public.mgr_lock()
 RETURNS careers
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
#variable_conflict use_column
declare c public.careers;
begin
 c:=public.sim_lock_career();perform public.mgr_ensure(c);perform public.mgr_sync_base_cards(c.id);perform public.cw_ensure(c.id);perform public.cw_runtime_ensure(c.id);
 if not(select stats_initialized from public.cw_world where career_id=c.id) then perform public.cw_initialize_finances(c.id);end if;
 update public.season_offers set status='expired',responded_at=now() where career_id=c.id and kind='coach' and status='pending' and expires_on<(select today from public.cw_world where career_id=c.id);
 select * into c from public.careers where id=c.id;return c;
end $function$;

CREATE OR REPLACE FUNCTION public.cw_ensure(p_career uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
 update public.season_offers set expires_on=current_day+greatest(1,coalesce(expires_day-s.day_no,7)),
 salary=coalesce(salary,150),contract_years=coalesce(contract_years,2),budget_guarantee=coalesce(budget_guarantee,0)
 where career_id=p_career and status='pending' and kind='coach' and expires_on is null;
 perform public.cw_news_add(p_career,'world:created','world','O mundo do futebol está em movimento',
 'Brasil e Europa agora seguem calendários próprios na sua carreira. Contratos, finanças e notícias evoluem com os dias.',65,s.club_id);

end $function$;

CREATE OR REPLACE FUNCTION public.mgr_hub_before_seasons_v2()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_car   public.careers;
  v_c     public.mgr_coach;
  v_s     public.career_seasons;
  v_ev    record;
  v_next  jsonb;
  v_nf    public.season_fixtures;
  v_live  bigint;
  v_lineup public.mgr_lineups;
  v_issues jsonb := '[]'::jsonb;
  v_opp   text;
  v_objs  jsonb;
  v_form  jsonb;
  v_n     int;
begin
  v_car := public.cw_read_career();
  select * into v_c from public.mgr_coach where career_id = v_car.id;
  select * into v_s from public.career_seasons where career_id = v_car.id and mode = 'coach' order by season_no desc limit 1;

  select fixture_id into v_live from public.mgr_matches where career_id = v_car.id and status = 'live' and user_side is not null limit 1;

  if v_s.status = 'active' then
    select * into v_ev from public.sim_next_event(v_s.id, v_s.club_id);
    if found then
      if v_ev.o_kind = 'mine' then
        select * into v_nf from public.season_fixtures
         where season_id = v_s.id and competition_id = v_ev.o_comp and status = 'pending' and (home_club = v_s.club_id or away_club = v_s.club_id)
         order by round_no, id limit 1;
        v_opp := case when v_nf.home_club = v_s.club_id then v_nf.away_club else v_nf.home_club end;
        select * into v_lineup from public.mgr_lineups where career_id = v_car.id and club_id = v_c.club_id;
        v_issues := public.mgr_lineup_issues(v_car.id, v_c.club_id,
                      jsonb_build_object('formation', v_lineup.formation, 'slots', v_lineup.slots, 'bench', to_jsonb(v_lineup.bench)),
                      v_ev.o_comp, v_s.day_no);
        -- forma recente dos dois clubes (últimos 5 jogos na temporada)
        select jsonb_build_object(
                 'mine', (select coalesce(jsonb_agg(x.r order by x.d desc), '[]') from (
                    select case when (f.home_club = v_s.club_id and f.home_goals > f.away_goals) or (f.away_club = v_s.club_id and f.away_goals > f.home_goals) then 'W'
                                when f.home_goals = f.away_goals then 'D' else 'L' end as r, f.played_at as d
                      from public.season_fixtures f where f.season_id = v_s.id and f.status = 'played' and (f.home_club = v_s.club_id or f.away_club = v_s.club_id)
                     order by f.played_at desc, f.id desc limit 5) x),
                 'opp', (select coalesce(jsonb_agg(x.r order by x.d desc), '[]') from (
                    select case when (f.home_club = v_opp and f.home_goals > f.away_goals) or (f.away_club = v_opp and f.away_goals > f.home_goals) then 'W'
                                when f.home_goals = f.away_goals then 'D' else 'L' end as r, f.played_at as d
                      from public.season_fixtures f where f.season_id = v_s.id and f.status = 'played' and (f.home_club = v_opp or f.away_club = v_opp)
                     order by f.played_at desc, f.id desc limit 5) x))
          into v_form;
        v_next := jsonb_build_object('kind', 'mine', 'competition', v_ev.o_comp, 'stage', v_ev.o_stage, 'round', v_ev.o_round,
          'fixture_id', v_nf.id, 'opponent', v_opp,
          'opponent_position', (select t.pos from public.sim_standings(v_s.id, v_ev.o_comp, v_nf.group_label) t
                                 where t.club_id = v_opp and v_nf.stage in ('league', 'group')),
          'form', v_form,
          'match', jsonb_build_object('home', v_nf.home_club, 'away', v_nf.away_club, 'round', v_nf.round_no, 'stage', v_nf.stage,
            'leg', v_nf.leg, 'group', v_nf.group_label, 'venue', case when v_nf.home_club = v_s.club_id then 'home' else 'away' end,
            'neutral', coalesce((public.sim_phase(v_nf.competition_id, v_nf.stage) ->> 'neutral')::boolean, v_nf.stage = 'final')));
      else
        select count(*) into v_n from public.season_fixtures
         where season_id = v_s.id and competition_id = v_ev.o_comp and stage = v_ev.o_stage and round_no = v_ev.o_round;
        v_next := jsonb_build_object('kind', 'free', 'competition', v_ev.o_comp, 'stage', v_ev.o_stage, 'round', v_ev.o_round, 'matches', v_n);
      end if;
    end if;
  end if;

  select coalesce(jsonb_agg(jsonb_build_object('id', o.id, 'competition', o.competition_id, 'label', o.label, 'kind', o.kind,
           'target', o.target, 'priority', o.priority, 'status', o.status, 'club_id', o.club_id,
           'current', case when o.kind = 'league_pos' then (select t.pos from public.sim_standings(v_s.id, o.competition_id, null) t where t.club_id = o.club_id)
                           else public.mgr_best_stage(v_s.id, o.competition_id, o.club_id) end,
           'alive', case when o.kind = 'reach_stage' then public.sim_club_alive(v_s.id, o.competition_id, o.club_id) end)
         order by o.priority desc, o.id), '[]'::jsonb)
    into v_objs from public.mgr_objectives o
   where o.season_id = v_s.id and (o.spell_id = v_c.spell_id or (v_c.spell_id is null and o.status <> 'void'));

  return jsonb_build_object(
    'career', jsonb_build_object('id', v_car.id, 'nickname', v_car.nickname, 'country', v_car.country, 'photo_id', v_car.photo_id,
      'level', v_car.level, 'xp', v_car.xp, 'coins', v_car.coins, 'energy', v_car.energy, 'bonus_energy', v_car.bonus_energy,
      'diamonds', v_car.diamonds, 'next_reset_at', v_car.energy_reset_at + interval '5 hours', 'club_id', v_car.club_id),
    'coach', jsonb_build_object('status', v_c.status, 'club_id', v_c.club_id, 'reputation', round(v_c.reputation, 1),
      'board', round(v_c.board_confidence), 'fans', round(v_c.fan_mood), 'matches', v_c.matches, 'wins', v_c.wins, 'draws', v_c.draws,
      'losses', v_c.losses, 'gf', v_c.gf, 'ga', v_c.ga, 'titles', v_c.titles, 'fired_count', v_c.fired_count, 'seasons', v_c.seasons,
      'unemployed_days', case when v_c.status = 'unemployed' then
          case when v_c.unemployed_season_no = v_s.season_no then v_s.day_no - coalesce(v_c.unemployed_day, v_s.day_no) else v_s.day_no end end,
      'spell', (select jsonb_build_object('id', sp.id, 'club_id', sp.club_id, 'matches', sp.matches, 'wins', sp.wins, 'draws', sp.draws,
                                          'losses', sp.losses, 'started_year', sp.started_year, 'started_day', sp.started_day)
                  from public.mgr_spells sp where sp.id = v_c.spell_id)),
    'season', jsonb_build_object('id', v_s.id, 'season_no', v_s.season_no, 'year', v_s.year, 'region', v_s.region, 'day_no', v_s.day_no, 'status', v_s.status,
      'club_id', v_s.club_id, 'matches', v_s.matches, 'wins', v_s.wins, 'draws', v_s.draws, 'losses', v_s.losses,
      'xp_earned', v_s.xp_earned, 'coins_earned', v_s.coins_earned, 'summary', v_s.summary),
    'competitions', public.mgr_comp_items(v_s.id, v_s.club_id),
    'next_event', v_next,
    'live_match', v_live,
    'lineup', jsonb_build_object('formation', v_lineup.formation, 'issues', v_issues,
      'errors', (select count(*) from jsonb_array_elements(v_issues) i where i ->> 'level' = 'error'),
      'warnings', (select count(*) from jsonb_array_elements(v_issues) i where i ->> 'level' = 'warn')),
    'objectives', v_objs,
    'messages', (select coalesce(jsonb_agg(m.j order by m.id desc), '[]'::jsonb) from (
        select mm.id, jsonb_build_object('id', mm.id, 'kind', mm.kind, 'title', mm.title, 'body', mm.body, 'club_id', mm.club_id,
                                         'day_no', mm.day_no, 'read', mm.read, 'created_at', mm.created_at) as j
          from public.mgr_messages mm where mm.career_id = v_car.id order by mm.id desc limit 30) m),
    'unread', (select count(*) from public.mgr_messages where career_id = v_car.id and not read),
    'offers', (select coalesce(jsonb_agg(jsonb_build_object('id', o.id, 'club_id', o.from_club, 'bonus_coins', o.bonus_coins, 'pitch', o.pitch,
                 'expires_day', o.expires_day, 'days_left', o.expires_day - v_s.day_no, 'context', o.context, 'created_at', o.created_at)
                 order by o.created_at desc), '[]'::jsonb)
                 from public.season_offers o where o.career_id = v_car.id and o.status = 'pending' and o.kind = 'coach'),
    'offer_history', (select coalesce(jsonb_agg(x.j order by x.ts desc), '[]'::jsonb) from (
        select jsonb_build_object('id', h.id, 'club_id', h.from_club, 'status', h.status, 'bonus_coins', h.bonus_coins) as j,
               coalesce(h.responded_at, h.created_at) as ts
          from public.season_offers h where h.career_id = v_car.id and h.kind = 'coach' and h.status <> 'pending'
         order by 2 desc limit 8) x));
end;
$function$;

CREATE OR REPLACE FUNCTION public.cw_schedule(p_season uuid)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
  chosen:=case when exists(select 1 from public.mgr_matches m where m.fixture_id=r.id and m.status='live' and m.user_side is not null) then (select today from public.cw_world where career_id=r.career_id) else case when public.cw_runtime_enabled(r.career_id) and r.season_id<>(select primary_season from public.cw_world where career_id=r.career_id) then r.proposed else greatest(r.proposed,(select today from public.cw_world where career_id=r.career_id)) end end;
  while exists(select 1 from public.cw_club_dates d where d.career_id=r.career_id and d.club_id in(r.home_club,r.away_club) and d.due_on between chosen-1 and chosen+1) loop
   chosen:=chosen+1;
   if chosen>r.ends_on+45 then raise exception 'Calendário sem data válida';end if;
  end loop;
  insert into public.cw_fixture_dates values(r.id,r.season_id,r.career_id,chosen);
  insert into public.cw_club_dates values(r.career_id,r.home_club,chosen,r.id),(r.career_id,r.away_club,chosen,r.id);
  n:=n+1;
 end loop;
 return n;
end $function$;

CREATE OR REPLACE FUNCTION public.cw_create_region(p_career uuid, p_region text, p_year integer)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
 insert into public.cw_seasons(career_id,region,year,season_id,starts_on,ends_on,calendar_shift) values(p_career,p_region,p_year,sid,starts,(starts+interval '1 year - 1 day')::date,case when public.cw_runtime_enabled(p_career) then 0 else greatest(0,(select today from public.cw_world where career_id=p_career)-starts) end);
 perform public.sim_participants_build(sid);
 for co in select * from public.sim_competitions where region=p_region and active order by sort_order loop
  phase:=public.sim_phase_at(co.id,1);
  insert into public.season_competitions(season_id,competition_id,stage) values(sid,co.id,phase->>'id');
  perform public.sim_phase_create(sid,co.id,phase->>'id',null);
 end loop;
 perform public.cw_schedule(sid);return sid;
end $function$;

CREATE OR REPLACE FUNCTION public.mgr_make_offer(p_career uuid, p_season uuid, p_day integer, p_force_weak boolean DEFAULT false, p_any_region boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
#variable_conflict use_column
declare result jsonb;oid uuid;d date;cred numeric;club text;pay bigint;budget bigint;bonus int;
begin
 if not exists(select 1 from public.cw_world where career_id=p_career) then return public.mgr_make_offer_before_world(p_career,p_season,p_day,p_force_weak,p_any_region);end if;
 select credibility into cred from public.cw_coach where career_id=p_career;
 -- A financial dismissal reduces the reach of the next search, including forced low-tier searches.
 -- Clubes de outra região contratam técnico de fora sobretudo na pré-temporada ou na janela deles (evolução 34).
 select public.cw_region((select club_id from public.mgr_coach where career_id=p_career)) into club;
 select today into d from public.cw_world where career_id=p_career;
 result:=public.mgr_make_offer_before_world(p_career,p_season,p_day,p_force_weak or cred<45,
  random()<case when public.cw_foreign_hiring(case when coalesce(club,(select region from public.career_seasons where id=p_season))='ENG' then 'BRA' else 'ENG' end,d) then 1 else .25 end);
 if result is null then return null;end if;
 oid:=(result->>'id')::uuid;club:=result->>'club_id';perform public.cw_materialize_club(p_career,club);select today into d from public.cw_world where career_id=p_career;
 if (select prestige from public.cw_clubs where career_id=p_career and club_id=club)>55+(select reputation from public.mgr_coach where career_id=p_career)*.32+(cred-65)*.18 then
  update public.season_offers set status='expired',responded_at=now() where id=oid;return null;
 end if;
 pay:=greatest(70,round((select prestige from public.cw_clubs where career_id=p_career and club_id=club)*2.5+cred));
 budget:=greatest(0,public.cw_available_budget(p_career,club));
 select least(bonus_coins,greatest(0,budget/50)::int) into bonus from public.season_offers where id=oid;
 budget:=greatest(0,budget-bonus-2*pay);
 update public.season_offers set salary=pay,contract_years=2,budget_guarantee=budget,expires_on=public.cw_deadline(d),expires_day=p_day+(select max_negotiation_days from public.cw_rules),
 bonus_coins=bonus,pitch=replace(pitch,'na próxima temporada','na temporada em andamento') where id=oid;
 perform public.cw_news_add(p_career,'job-offer:'||oid,'job',public.mgr_club_name(club)||' procura novo treinador','Proposta de contrato por duas temporadas. Salário e orçamento podem ser negociados em Carreira.',95,club);
 return result||jsonb_build_object('salary',pay,'contract_years',2,'budget_guarantee',budget,'expires_on',public.cw_deadline(d));
end $function$;

CREATE OR REPLACE FUNCTION public.mgr_offer_respond(p_offer uuid, p_accept boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
#variable_conflict use_column
declare car public.careers;o public.season_offers;c public.mgr_coach;w public.cw_world;sid uuid;spell uuid;
begin
 car:=public.mgr_lock();select * into w from public.cw_world where career_id=car.id;
 select * into o from public.season_offers where id=p_offer and career_id=car.id and kind='coach' for update;
 if not found then raise exception 'Proposta inexistente';end if;
 if o.status='accepted' and p_accept then return jsonb_build_object('ok',true,'accepted',true,'club_id',o.from_club);end if;
 if o.status<>'pending' or o.expires_on<w.today then raise exception 'Proposta encerrada';end if;
 if exists(select 1 from public.mgr_matches where career_id=car.id and status='live' and user_side is not null) then raise exception 'Termine a partida em andamento';end if;
 if p_accept then
  if public.cw_runtime_enabled(car.id) then perform public.cw_simulate_due(car.id,24);select * into w from public.cw_world where career_id=car.id;perform public.cw_activate_region(car.id,public.cw_region(o.from_club));end if;
  if w.needs_sync then raise exception 'Atualize os resultados do mundo antes de trocar de clube';end if;
  select ws.season_id into sid from public.cw_seasons ws join public.career_seasons s on s.id=ws.season_id where ws.career_id=car.id and ws.region=public.cw_region(o.from_club) and s.status='active' order by ws.starts_on limit 1;
  if sid is null then raise exception 'Atualize o calendário regional antes de assumir o clube';end if;
  if (select cash-public.cw_reserved(car.id,o.from_club) from public.cw_clubs where career_id=car.id and club_id=o.from_club)<coalesce(o.bonus_coins,0)+2*o.salary or greatest(0,public.cw_available_budget(car.id,o.from_club)-coalesce(o.bonus_coins,0)-2*o.salary)<coalesce(o.budget_guarantee,0) then raise exception 'O clube não pode sustentar os termos do contrato';end if;
  select * into c from public.mgr_coach where career_id=car.id;
  if c.status='employed' then perform public.mgr_end_spell(car.id,'left');end if;
  perform public.cw_promote_season(car.id,sid,o.from_club);perform public.mgr_init_world(car.id);perform public.cw_initialize_finances(car.id);spell:=public.mgr_start_spell(car.id,o.from_club);
  update public.cw_coach set monthly_salary=o.salary,contract_until=(w.today+make_interval(years=>o.contract_years))::date,promised_budget=o.budget_guarantee where career_id=car.id;
  update public.cw_clubs set distress_since=case when financial_risk>=75 then w.today else distress_since end where career_id=car.id and club_id=o.from_club;
  insert into public.cw_coach_contracts(career_id,spell_id,club_id,starts_on,expires_on,monthly_salary)
   values(car.id,spell,o.from_club,w.today,(w.today+make_interval(years=>o.contract_years))::date,o.salary);
  if o.bonus_coins>0 then perform public.cw_cash(car.id,o.from_club,-o.bonus_coins,'coach_signing',o.id::text,'Luvas do treinador');perform public.econ_apply(car.id,'coins',o.bonus_coins,'coach_signing',o.id::text);end if;
  update public.season_offers set status='accepted',responded_at=now() where id=o.id;
  update public.season_offers set status='expired',responded_at=now() where career_id=car.id and kind='coach' and status='pending';
  perform public.cw_news_add(car.id,'coach-hired:'||spell,'job',public.mgr_club_name(o.from_club)||' anuncia novo treinador','Contrato por '||o.contract_years||' anos. A temporada e os resultados existentes continuam.',98,o.from_club);
 else update public.season_offers set status='declined',responded_at=now() where id=o.id;end if;
 return jsonb_build_object('ok',true,'accepted',p_accept,'club_id',o.from_club);
end $function$;

CREATE OR REPLACE FUNCTION public.career_world_status()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
#variable_conflict use_column
declare car public.careers;own text;w public.cw_world;
begin
 car:=public.cw_read_career();select * into w from public.cw_world where career_id=car.id;select club_id into own from public.mgr_coach where career_id=car.id and status='employed';
 return to_jsonb(w)-'career_id'||jsonb_build_object('coach',(select to_jsonb(c)-'career_id' from public.cw_coach c where career_id=car.id),
 'club',(select to_jsonb(c)-'career_id'||jsonb_build_object('payroll',public.cw_payroll(car.id,own),'reserved',public.cw_reserved(car.id,own),'available',public.cw_available_budget(car.id,own),'window_open',public.cw_window_open(public.cw_region(own),w.today),'next_window',public.cw_next_window(public.cw_region(own),w.today)) from public.cw_clubs c where career_id=car.id and club_id=own),
 'seasons',(select coalesce(jsonb_agg(to_jsonb(x)),'[]') from(select ws.region,ws.year,s.status,ws.season_id,ws.starts_on,ws.ends_on from public.cw_seasons ws join public.career_seasons s on s.id=ws.season_id where ws.career_id=car.id order by ws.starts_on desc limit 8)x),
 'due_matches',(select count(*) from public.cw_fixture_dates fd join public.season_fixtures f on f.id=fd.fixture_id where fd.career_id=car.id and (not public.cw_runtime_enabled(car.id) or f.season_id=w.primary_season) and fd.due_on<=w.today and f.status='pending' and not(f.season_id=w.primary_season and own is not null and own in(f.home_club,f.away_club))),
 'news_unread',(select count(*) from public.cw_news where career_id=car.id and not read));
end $function$;

create or replace function public.career_hub_read()
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare c public.careers;h jsonb;
begin
 c:=public.cw_read_career();
 if not exists(select 1 from public.cw_world where career_id=c.id) then return jsonb_build_object('initialization_required',true);end if;
 h:=public.mgr_hub();
 return h||jsonb_build_object('attention',case when public.cw_runtime_enabled(c.id) then public.cw_attention(c.id) end,
 'runtime_version',coalesce((select version from public.cw_runtime where career_id=c.id),0),
 'calendar_versions',(select coalesce(jsonb_object_agg(competition_id,v),'{}') from(
 select competition_id,count(*)::text||':'||count(*) filter(where status='played')||':'||coalesce(max(played_at)::text,'')||':'||max(id)::text v
 from public.season_fixtures where season_id=(h#>>'{season,id}')::uuid group by competition_id)x));
end $$;
create or replace function public.career_runtime_initialize()
returns jsonb language plpgsql security definer set search_path=public as $$
declare c public.careers;begin c:=public.mgr_lock();return public.career_hub_read();end $$;


CREATE OR REPLACE FUNCTION public.mgr_hub_before_v33()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
#variable_conflict use_column
declare h jsonb;w jsonb;d date;car uuid;
begin
 h:=public.mgr_hub_before_world();w:=public.career_world_status();car:=(h#>>'{career,id}')::uuid;
 if h#>>'{next_event,fixture_id}' is not null then
  select due_on into d from public.cw_fixture_dates where fixture_id=(h#>>'{next_event,fixture_id}')::bigint;
  h:=jsonb_set(h,'{next_event}',h->'next_event'||jsonb_build_object('scheduled_on',d,'days_until',d-(w->>'today')::date));
 end if;
 h:=jsonb_set(h,'{offers}',(select coalesce(jsonb_agg(jsonb_build_object('id',o.id,'club_id',o.from_club,'pitch',o.pitch,'context',o.context,'bonus_coins',o.bonus_coins,'salary',o.salary,'contract_years',o.contract_years,'budget_guarantee',o.budget_guarantee,'expires_on',o.expires_on,'days_left',o.expires_on-(w->>'today')::date,'negotiation_round',o.negotiation_round)),'[]') from public.season_offers o where career_id=car and kind='coach' and status='pending' and expires_on>=(w->>'today')::date));
 return h||jsonb_build_object('career_world_version',1,'world',w);
end $function$;

CREATE OR REPLACE FUNCTION public.mgr_hub()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare h jsonb;car uuid;
begin
 car:=(public.cw_read_career()).id;
 if not exists(select 1 from public.cw_world where career_id=car) then perform public.mgr_lock();end if;
 h:=public.mgr_hub_before_v33();
 return h||jsonb_build_object(
  'messages',(select coalesce(jsonb_agg(m.j order by m.id desc),'[]') from(
    select mm.id,jsonb_build_object('id',mm.id,'kind',mm.kind,'category',mm.category,'title',mm.title,'body',mm.body,'club_id',mm.club_id,
     'player_id',mm.player_id,'negotiation_id',mm.negotiation_id,'action',mm.action,'day_no',mm.day_no,'read',mm.read,'created_at',mm.created_at) j
    from public.mgr_messages mm where mm.career_id=car order by mm.id desc limit 80) m),
  'unread_by_category',(select coalesce(jsonb_object_agg(category,n),'{}') from(select category,count(*) n from public.mgr_messages where career_id=car and not read group by category) x));
end $function$;

CREATE OR REPLACE FUNCTION public.sim_lock_career()
 RETURNS careers
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_c public.careers;
  v_k int;
begin
  select * into v_c from public.careers where user_id = auth.uid() and status = 'active' for update;
  if not found then raise exception 'Carreira ativa não encontrada'; end if;

  if now() >= v_c.energy_reset_at + interval '5 hours' then
    v_k := floor(extract(epoch from (now() - v_c.energy_reset_at)) / 18000)::int;
    update public.careers
       set energy = greatest(energy, 10),
           energy_reset_at = energy_reset_at + (v_k * interval '5 hours')
     where id = v_c.id
    returning * into v_c;
  end if;

  -- proposta que passou do prazo some (e o clube "esfria": ver sim_club_weight)
  update public.season_offers set status = 'expired', responded_at = now()
   where career_id = v_c.id and status = 'pending' and kind<>'coach' and expires_at is not null and expires_at <= now();

  return v_c;
end;
$function$;

CREATE OR REPLACE FUNCTION public.cw_market_tick_before_v37(p_career uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
#variable_conflict use_column
declare d date;own text;n public.cw_negotiations;ct public.cw_contracts;threshold numeric;interest numeric;buyer public.cw_clubs;seller public.cw_clubs;
 r record;c public.cw_clubs;p record;id uuid;value bigint;cnt int;expected numeric;apps int;games int;new_morale numeric;paid bigint;user_region text;depth jsonb;style text;
begin
 select today into d from public.cw_world where career_id=p_career;
 if extract(doy from d)=1 then update public.cw_players set market_value=public.cw_player_value(p_career,player_id) where career_id=p_career and (not (select public.cw_runtime_enabled(p_career)) or player_id in(select player_id from public.mgr_players where career_id=p_career and club_id in (select public.cw_domestic_clubs(p_career))));end if;
 select club_id into own from public.mgr_coach where career_id=p_career;
 for n in select * from public.cw_negotiations where career_id=p_career and status in('seller_review','club_pending','club_counter','player_pending','player_counter','agreed','precontract') order by created_on,id for update loop
  if n.status in('agreed','precontract') then perform public.cw_register_transfer(n.id);continue;end if;
  if n.expires_on<d then perform public.cw_neg_close(n.id,'expired','Prazo da proposta encerrado.');continue;end if;
  if n.reply_on>d or n.status in('seller_review','club_counter','player_counter') then continue;end if;
  select * into ct from public.cw_contracts where career_id=p_career and player_id=n.player_id and status='active';
  select * into buyer from public.cw_clubs where career_id=p_career and club_id=n.buyer_club;
  select * into seller from public.cw_clubs where career_id=p_career and club_id=n.seller_club;
  if n.status='club_pending' then
   select count(*) into cnt from public.mgr_players where career_id=p_career and club_id=n.seller_club;
   threshold:=n.valuation*(case when seller.financial_risk>=50 then .85 else 1.05 end)+n.valuation*case when ct.role='key' then .35 else .05 end;
   threshold:=threshold*(.9+n.decision_roll*.3)*case when ct.expires_on<d+180 then .65 else 1 end;
   if exists(select 1 from public.cw_rivalries rv where rv.club_a=least(n.buyer_club,n.seller_club) and rv.club_b=greatest(n.buyer_club,n.seller_club)) then threshold:=threshold*1.12;end if;
   threshold:=threshold*(1+least(.20,.04*(select count(*) from public.cw_negotiations z where z.career_id=p_career and z.player_id=n.player_id and z.id<>n.id and z.status in('club_pending','player_pending','seller_review'))));
   if n.seller_club is null or n.register_on>coalesce(ct.expires_on,d+999) then threshold:=0;end if;
   if (cnt<=18 and threshold>0) or n.decision_roll<.04 then
    perform public.cw_neg_close(n.id,'rejected','O clube considera o atleta indispensável ou não tem reposição.');
   elsif n.fee+n.performance_bonus*.5<threshold then
    if n.round_no>=2 or n.fee<threshold*.55 then perform public.cw_neg_close(n.id,'rejected','Os valores não atendem à avaliação do clube.');
    else
     update public.cw_negotiations set status='club_counter',fee=ceil(threshold),round_no=round_no+1,expires_on=public.cw_deadline(d),response='O clube pede uma revisão do valor.' where id=n.id;
     if n.initiator='ai' then perform public.cw_neg_close(n.id,'rejected','O comprador desistiu da contraproposta.');else perform public.cw_neg_history(n.id,'seller','Contraproposta do clube vendedor.');end if;
    end if;
   else
    update public.cw_negotiations set status='player_counter',response='Clube de acordo. Apresente salário, duração, luvas e papel ao atleta.',expires_on=public.cw_deadline(d) where id=n.id;
    if n.initiator='ai' then
     update public.cw_negotiations set status='player_pending',monthly_salary=greatest(40,ceil(coalesce(ct.monthly_salary,n.valuation*.0065)*1.15)),contract_years=3,signing_bonus=ceil(n.valuation*.02),reply_on=d+2 where id=n.id;
    end if;
    perform public.cw_neg_history(n.id,'seller','Condições entre clubes aprovadas.');
   end if;
  elsif n.status='player_pending' then
   interest:=coalesce(public.cw_contract_cost(ct.player_id,ct.monthly_salary,ct.appearance_bonus,ct.goal_bonus,ct.role),greatest(40,n.valuation*.0065))*case when buyer.prestige>=coalesce(seller.prestige,0)+5 then 1.02 else 1.12 end;
   interest:=interest*(1+greatest(0,coalesce(seller.prestige,0)-buyer.prestige)*.015);
   interest:=interest*case when (select morale from public.cw_players where career_id=p_career and player_id=n.player_id)<35 and n.initiator='renewal' then 1.35 else 1 end;
   interest:=interest*case when n.role='prospect' and coalesce(ct.role,'rotation') in('key','starter') then 1.35 else 1 end;
   if n.decision_roll<.06 and buyer.prestige<coalesce(seller.prestige,0) then
    perform public.cw_neg_close(n.id,'rejected','O atleta recusou o projeto esportivo, independentemente da remuneração.');continue;
   end if;
   if (public.cw_contract_cost(n.player_id,n.monthly_salary,n.appearance_bonus,n.goal_bonus,n.role)+n.signing_bonus/greatest(12*n.contract_years,1))<interest then
    if n.round_no>=3 or n.monthly_salary<interest*.65 then perform public.cw_neg_close(n.id,'rejected','O atleta recusou salário, papel ou projeto esportivo.');
    else update public.cw_negotiations set status='player_counter',monthly_salary=ceil(interest),round_no=round_no+1,expires_on=public.cw_deadline(d),response='O atleta pede melhores condições salariais.' where id=n.id;perform public.cw_neg_history(n.id,'player','Contraproposta salarial do atleta.');end if;
   elsif exists(select 1 from public.cw_negotiations where career_id=p_career and player_id=n.player_id and id<>n.id and status in('agreed','precontract')) then
    perform public.cw_neg_close(n.id,'rejected','O atleta já assinou um acordo.');
   else
    begin
     perform public.cw_reserve_offer(n.id);
     update public.cw_negotiations set status=case when n.register_on is not null then 'precontract' else 'agreed' end,response='Ambas as partes aprovaram. Aguardando registro.',register_on=coalesce(n.register_on,case when n.seller_club is not null and n.initiator<>'renewal' and not public.cw_window_open(public.cw_region(n.buyer_club),d) then public.cw_next_window(public.cw_region(n.buyer_club),d) else d end) where id=n.id;
     perform public.cw_neg_history(n.id,'player','Condições do atleta aprovadas.');perform public.cw_register_transfer(n.id);
    exception when raise_exception then perform public.cw_neg_close(n.id,'failed_funds',sqlerrm);end;
   end if;
  end if;
 end loop;
 -- Scheduled transfer liabilities are paid once; performance clauses require ten actual appearances.
 for r in select cm.*,n.player_id,n.seller_club,n.register_on from public.cw_commitments cm join public.cw_negotiations n on n.id=cm.negotiation_id
  where cm.career_id=p_career and cm.status='reserved' and n.status='completed' and cm.kind in('installment','performance') order by cm.due_on,cm.id loop
  if r.kind='performance' then
   select count(*) into apps from public.cw_appearances mp where mp.career_id=p_career and mp.player_id=r.player_id and mp.club_id=r.club_id and mp.minutes>0 and mp.on_date>=r.register_on;
   if apps<10 and d<r.due_on then continue;end if;
   if apps<10 then update public.cw_commitments set status='released' where id=r.id;continue;end if;
  elsif r.due_on>d then continue;end if;
  perform public.cw_cash(p_career,r.club_id,-r.amount,'transfer_clause',r.id::text,'Parcela ou bônus da contratação',true);
  if r.seller_club is not null then perform public.cw_cash(p_career,r.seller_club,r.amount,'player_sale_clause',r.id::text,'Recebimento de parcela ou bônus');end if;
  update public.cw_commitments set status='paid' where id=r.id;
 end loop;
 -- Satisfação semanal pelos minutos reais x papel prometido e pelos salários em dia (evolução 34).
 -- Reservas e promessas aceitam o papel (não caem abaixo de 40 só por minutos); quem cobra espaço é o titular encostado.
 for p in select cp.*,mp.club_id,ct.arrears,ct.starts_on,ct.role from public.cw_players cp join public.mgr_players mp using(career_id,player_id)
  join public.cw_contracts ct on ct.career_id=cp.career_id and ct.player_id=cp.player_id and ct.status='active'
  where cp.career_id=p_career and (not (select public.cw_runtime_enabled(p_career)) or mp.club_id in (select public.cw_domestic_clubs(p_career)) or mp.club_id=own) and (cp.last_morale_on is null or cp.last_morale_on<=d-7) loop
  if d-p.starts_on<28 then update public.cw_players set last_morale_on=d where career_id=p_career and player_id=p.player_id;continue;end if;
  select count(*) into games from public.cw_club_dates fd join public.season_fixtures f on f.id=fd.fixture_id where fd.career_id=p_career and fd.club_id=p.club_id and f.status='played' and fd.due_on between d-28 and d;
  select count(*) into apps from public.cw_appearances mp where mp.career_id=p_career and mp.player_id=p.player_id and mp.club_id=p.club_id and mp.minutes>=30 and mp.on_date between d-28 and d;
  expected:=case p.promised_role when 'key' then .70 when 'starter' then .50 when 'rotation' then .20 else 0 end;
  -- Clubes da IA conversam com quem não tem espaço: o papel prometido passa a ser de reserva (o seu clube decide sozinho).
  if p.club_id is distinct from own and games>=3 and expected>.2 and apps::numeric/games<expected*.4 and random()<.5 then
   update public.cw_players set promised_role='rotation' where career_id=p_career and player_id=p.player_id;
   update public.cw_contracts set role='rotation' where career_id=p_career and player_id=p.player_id and status='active';
   expected:=.20;
  end if;
  if games<3 or expected=0 or apps::numeric/games>=expected then
   -- Papel cumprido (ou sem jogos suficientes): recupera, mais rápido quando estava insatisfeito; perto do topo sobe devagar.
   new_morale:=p.morale+case when p.morale<50 then 6 when p.morale<80 then 3 else 1 end;
  else
   new_morale:=greatest(least(p.morale,case p.promised_role when 'key' then 5 when 'starter' then 15 else 40 end),
    p.morale-round(2+4*(expected-apps::numeric/games)/expected));
  end if;
  new_morale:=greatest(0,least(100,new_morale-case when p.arrears>0 then 12 else 0 end));
  update public.cw_players set morale=new_morale,last_morale_on=d,transfer_requested=new_morale<30,
   last_warning_on=case when new_morale<45 then coalesce(last_warning_on,d) else null end where career_id=p_career and player_id=p.player_id;
  if new_morale<45 and p.morale>=45 and p.club_id=own then perform public.cw_news_add(p_career,'morale:'||p.player_id||':'||to_char(d,'IYYY-IW'),'squad',public.mgr_player_name(p.player_id)||' cobra espaço no time',
   'O papel prometido, os minutos recentes e os pagamentos estão afetando a satisfação. Reveja as oportunidades ou o papel no contrato.',90,own,p.player_id);
  elsif new_morale<30 and p.morale>=30 and p.club_id=own then perform public.cw_news_add(p_career,'morale-out:'||p.player_id||':'||to_char(d,'IYYY-IW'),'squad',public.mgr_player_name(p.player_id)||' pede para sair',
   'Muito insatisfeito, o atleta quer ser negociado e rende menos em campo. Dê minutos, ajuste o papel ou negocie a saída.',95,own,p.player_id);
  elsif new_morale>=45 and p.morale<45 and p.club_id=own then perform public.cw_news_add(p_career,'morale-up:'||p.player_id||':'||to_char(d,'IYYY-IW'),'squad',public.mgr_player_name(p.player_id)||' volta a ficar satisfeito',
   'Com mais oportunidades, o atleta voltou a se dedicar e esquece a ideia de sair.',60,own,p.player_id);
  end if;
 end loop;
 -- Alvos realistas (evolução 40): pilares (3 melhores de cada clube) não são alvo, e atletas com menos de 32 anos
 -- não são procurados por clubes de divisão inferior à deles. Calculado uma vez por dia.
 create temp table if not exists _cw_pillars(player_id text primary key) on commit drop;
 create temp table if not exists _cw_levels(club_id text primary key,lvl int not null) on commit drop;
 truncate _cw_pillars;truncate _cw_levels;
 insert into _cw_pillars select x.player_id from(select mp.player_id,row_number() over(partition by mp.club_id order by r.rating desc,mp.player_id) rk
  from public.mgr_players mp join public.sim_players sp on sp.id=mp.player_id join public.sim_player_pos_ratings r on r.player_id=sp.id and r.pos=sp.position
  where mp.career_id=p_career and mp.club_id is not null) x where x.rk<=3 on conflict do nothing;
 insert into _cw_levels select c.id,public.cw_club_level(c.id) from public.sim_clubs c on conflict do nothing;
 -- One AI decision per club/date, with budgets and squad needs. User sales always await explicit approval.
 for c in select * from public.cw_clubs where career_id=p_career and club_id is distinct from own and (not (select public.cw_runtime_enabled(p_career)) or club_id in (select public.cw_domestic_clubs(p_career))) order by club_id loop
  insert into public.cw_ai_days values(p_career,c.club_id,d) on conflict do nothing;if not found then continue;end if;
  -- Janela fechada: só atletas livres (como na vida real). Elenco acima do limite + 6 não compra.
  if c.financial_risk>=75 or random()>public.cw_tick_probability((select ai_bid_chance from public.cw_rules))*(case when public.cw_window_open(public.cw_region(c.club_id),d) then 1 else .35 end)
     or public.cw_squad_count(p_career,c.club_id)>=public.cw_squad_limit()+6 then continue;end if;
  paid:=public.cw_available_budget(p_career,c.club_id);
  select coalesce(jsonb_object_agg(position,n),'{}') into depth from(select sp2.position,count(*) as n from public.mgr_players t join public.sim_players sp2 on sp2.id=t.player_id where t.career_id=p_career and t.club_id=c.club_id group by sp2.position)x;
  select a.style into style from public.mgr_ai_clubs a where a.career_id=p_career and a.club_id=c.club_id;
  select sp.id,mp.club_id,sp.position,coalesce(cp.potential,70) as potential into p from public.mgr_players mp join public.sim_players sp on sp.id=mp.player_id join public.cw_players cp on cp.career_id=mp.career_id and cp.player_id=mp.player_id
   join public.sim_player_pos_ratings pr on pr.player_id=sp.id and pr.pos=sp.position
   where mp.career_id=p_career and mp.club_id is distinct from c.club_id and sp.active and (not (select public.cw_runtime_enabled(p_career)) or mp.club_id is null or mp.club_id in (select public.cw_domestic_clubs(p_career)))
    and (mp.club_id is null or public.cw_window_open(public.cw_region(c.club_id),d))
    and cp.market_value<paid*.65
    and not exists(select 1 from public.cw_negotiations x where x.career_id=p_career and x.player_id=sp.id and x.buyer_club=c.club_id and x.status in('seller_review','club_pending','club_counter','player_pending','player_counter','agreed','precontract'))
    and pr.rating>=c.prestige-12
    and (mp.club_id is null or not exists(select 1 from _cw_pillars pl where pl.player_id=sp.id))
    and (mp.club_id is null or cp.age_at_start+floor((d-(select started_on from public.cw_world where career_id=p_career))/365.25)>=32
     or (select lvl from _cw_levels where club_id=c.club_id)<=(select lvl from _cw_levels where club_id=mp.club_id))
   order by (pr.rating+case when c.strategy='youth' then cp.potential-pr.rating else 0 end)
    /greatest(1,coalesce((depth->>sp.position)::int,0))*random() +case when (style='wide' and sp.position in('PD','PE','LD','LE')) or(style='counter' and sp.position in('ATA','PD','PE')) or(style='possession' and sp.position in('MC','MEI','VOL')) then 5 else 0 end
    +case when public.cw_region(mp.club_id)<>public.cw_region(c.club_id) then 20*(select ai_foreign_preference from public.cw_rules) else 0 end desc limit 1;
  if p.id is null then continue;end if;
  select * into ct from public.cw_contracts where career_id=p_career and player_id=p.id and status='active';
  value:=public.cw_player_value(p_career,p.id);
  insert into public.cw_negotiations(career_id,player_id,seller_club,buyer_club,initiator,status,fee,monthly_salary,contract_years,signing_bonus,created_on,reply_on,expires_on,valuation,agreed_owner_contract)
   values(p_career,p.id,p.club_id,c.club_id,'ai',case when p.club_id=own then 'seller_review' else 'club_pending' end,case when p.club_id is null then 0 else round(value*(1.1+random()*.35)) end,
    greatest(40,ceil(coalesce(ct.monthly_salary,value*.0065)*1.15)),3,ceil(value*.02),d,d+2,public.cw_deadline(d),value,ct.id) returning id into id;
  begin perform public.cw_reserve_offer(id);exception when raise_exception then perform public.cw_neg_close(id,'failed_funds',sqlerrm);continue;end;
  perform public.cw_neg_history(id,'buyer','Proposta enviada pelo clube interessado.');
  if p.club_id=own then perform public.cw_news_add(p_career,'incoming:'||id,'transfer',public.mgr_club_name(c.club_id)||' faz proposta por '||public.mgr_player_name(p.id),'A venda depende da sua decisão. Abra Negociações para aceitar, recusar ou apresentar uma contraproposta.',95,own,p.id);end if;
 end loop;
 -- AI contract management: renew affordable contributors before expiry; release surplus players without deleting them.
 if extract(day from d)=15 then
  for ct in select x.* from public.cw_contracts x where x.career_id=p_career and x.status='active' and x.club_id is distinct from own and (not (select public.cw_runtime_enabled(p_career)) or x.club_id in (select public.cw_domestic_clubs(p_career))) and x.expires_on between d and d+120
   and not exists(select 1 from public.cw_negotiations n where n.career_id=p_career and n.player_id=x.player_id and n.status in('agreed','precontract')) loop
   if public.cw_available_budget(p_career,ct.club_id)>ct.monthly_salary*3 and (select morale from public.cw_players where career_id=p_career and player_id=ct.player_id)>=35 then
    update public.cw_contracts set status='ended',ended_on=d-1 where id=ct.id;
    insert into public.cw_contracts(career_id,player_id,club_id,starts_on,expires_on,monthly_salary,role)
     values(p_career,ct.player_id,ct.club_id,d,(d+interval '2years')::date,ceil(ct.monthly_salary*1.06),ct.role);
    perform public.cw_news_add(p_career,'ai-renew:'||ct.id,'contract',public.mgr_player_name(ct.player_id)||' renova contrato','Vínculo renovado por duas temporadas.',25,ct.club_id,ct.player_id);
   end if;
  end loop;
 end if;
end $function$;

CREATE OR REPLACE FUNCTION public.cw_v32_tick(p_career uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
#variable_conflict use_column
declare d date;own text;p record;buyer text;value bigint;nid uuid;ct public.cw_contracts;club public.cw_clubs;spell_start date;lim int:=public.cw_squad_limit();
begin
 select today into d from public.cw_world where career_id=p_career;
 select club_id into own from public.mgr_coach where career_id=p_career and status='employed';
 -- 1) venda dos listados
 if own is not null and public.cw_window_open(public.cw_region(own),d) then
  for p in select cp.player_id,cp.transfer_listed,ct.id as contract_id,ct.monthly_salary from public.cw_players cp join public.mgr_players mp using(career_id,player_id)
    join public.cw_contracts ct on ct.career_id=cp.career_id and ct.player_id=cp.player_id and ct.status='active'
    where cp.career_id=p_career and mp.club_id=own and (cp.transfer_listed or cp.transfer_requested)
     and not exists(select 1 from public.cw_negotiations n where n.career_id=p_career and n.player_id=cp.player_id and n.status in('seller_review','club_pending','club_counter','player_pending','player_counter','agreed','precontract'))
     and random()<public.cw_tick_probability(case when cp.transfer_listed then .12 else .05 end) loop
   value:=public.cw_player_value(p_career,p.player_id);
   -- amostra de clubes com caixa (o orçamento livre completo só é calculado para a amostra)
   select c.club_id into buyer from (select z.* from public.cw_clubs z where z.career_id=p_career and (not (select public.cw_runtime_enabled(p_career)) or z.club_id in (select public.cw_domestic_clubs(p_career))) and z.club_id<>own and z.financial_risk<75 and z.cash-z.debt>value*1.3
     order by random() limit 30) c
    where public.cw_available_budget(p_career,c.club_id)>value*1.1 and public.cw_squad_count(p_career,c.club_id)<lim+6
    order by (public.cw_region(c.club_id)=public.cw_region(own)) desc,random() limit 1;
   if buyer is null then continue;end if;
   insert into public.cw_negotiations(career_id,player_id,seller_club,buyer_club,initiator,status,fee,monthly_salary,contract_years,signing_bonus,created_on,reply_on,expires_on,valuation,agreed_owner_contract)
    values(p_career,p.player_id,own,buyer,'ai','seller_review',round(value*(case when p.transfer_listed then .85 else .95 end+random()*.25)),
     greatest(40,ceil(p.monthly_salary*1.1)),3,ceil(value*.02),d,d+2,public.cw_deadline(d),value,p.contract_id) returning id into nid;
   begin perform public.cw_reserve_offer(nid);exception when raise_exception then perform public.cw_neg_close(nid,'failed_funds',sqlerrm);continue;end;
   perform public.cw_neg_history(nid,'buyer','Proposta por atleta disponível para venda.');
   perform public.cw_news_add(p_career,'incoming:'||nid,'transfer',public.mgr_club_name(buyer)||' faz proposta por '||public.mgr_player_name(p.player_id),
    'A venda depende da sua decisão. Abra Negociações para aceitar, recusar ou apresentar uma contraproposta.',95,own,p.player_id);
  end loop;
 end if;
 -- 2) pré-contratos (dias 1 e 15): o atleta sem renovação assina com outro clube e sai de graça no fim do vínculo
 if extract(day from d) in(1,15) then
  for ct in select x.* from public.cw_contracts x where x.career_id=p_career and x.status='active' and (not (select public.cw_runtime_enabled(p_career)) or x.club_id=own or x.club_id in (select public.cw_domestic_clubs(p_career))) and x.expires_on between d and d+180
   and not exists(select 1 from public.cw_negotiations n where n.career_id=p_career and n.player_id=x.player_id and n.status in('seller_review','club_pending','club_counter','player_pending','player_counter','agreed','precontract'))
   and random()<case when x.club_id=own then .35 else .12 end
   order by (x.club_id=own) desc,random() limit 25 loop
   value:=public.cw_player_value(p_career,ct.player_id);
   select c.club_id into buyer from (select z.* from public.cw_clubs z where z.career_id=p_career and (not (select public.cw_runtime_enabled(p_career)) or z.club_id in (select public.cw_domestic_clubs(p_career))) and z.club_id is distinct from ct.club_id and z.club_id is distinct from own
     and z.financial_risk<75 and z.cash-z.debt>ct.monthly_salary*8 order by random() limit 30) c
    order by abs(c.prestige-coalesce((select prestige from public.cw_clubs z where z.career_id=p_career and z.club_id=ct.club_id),c.prestige)) limit 1;
   if buyer is null or public.cw_squad_count(p_career,buyer)>=lim+6 then continue;end if;
   -- Atleta satisfeito tende a esperar a renovação do clube atual.
   if (select morale from public.cw_players where career_id=p_career and player_id=ct.player_id)>=70 and random()<.6 then continue;end if;
   insert into public.cw_negotiations(career_id,player_id,seller_club,buyer_club,initiator,status,fee,monthly_salary,contract_years,signing_bonus,created_on,reply_on,expires_on,register_on,valuation,agreed_owner_contract,response)
    values(p_career,ct.player_id,ct.club_id,buyer,'ai','precontract',0,greatest(40,ceil(ct.monthly_salary*1.12)),2+floor(random()*3)::int,0,d,d,greatest(public.cw_deadline(d),ct.expires_on+1),ct.expires_on+1,value,ct.id,
     'Pré-contrato assinado: o atleta chega sem custo ao fim do vínculo atual.') returning id into nid;
   perform public.cw_neg_history(nid,'player','Pré-contrato assinado com o novo clube.');
   perform public.cw_news_add(p_career,'precontract:'||nid,'transfer',public.mgr_player_name(ct.player_id)||' assina pré-contrato com '||public.mgr_club_name(buyer),
    'Sem renovação com '||coalesce(public.mgr_club_name(ct.club_id),'o clube')||', o atleta sai de graça em '||to_char(ct.expires_on+1,'DD/MM/YYYY')||'.',case when ct.club_id=own then 95 else 35 end,ct.club_id,ct.player_id);
  end loop;
  -- aviso mensal dos vínculos do seu elenco que terminam em até seis meses
  if extract(day from d)=1 and own is not null then
   for ct in select x.* from public.cw_contracts x where x.career_id=p_career and x.club_id=own and x.status='active' and x.expires_on between d and d+180
    and not exists(select 1 from public.cw_negotiations n where n.career_id=p_career and n.player_id=x.player_id and n.status in('agreed','precontract')) loop
    perform public.cw_news_add(p_career,'expiring:'||ct.id||':'||to_char(d,'YYYY-MM'),'contract','Contrato de '||public.mgr_player_name(ct.player_id)||' termina em '||to_char(ct.expires_on,'DD/MM/YYYY'),
     'Sem renovação, o atleta pode assinar pré-contrato com outro clube e sair de graça. Negocie em Time ou em Mundo → Contratos.',80,own,ct.player_id);
   end loop;
  end if;
 end if;
 -- 3) falência iminente: risco ≥ 90 por 21 dias (com o treinador há pelo menos 45 dias no cargo)
 if own is not null then
  select * into club from public.cw_clubs where career_id=p_career and club_id=own;
  select min(starts_on) into spell_start from public.cw_coach_contracts where career_id=p_career and club_id=own and ended_on is null;
  if club.financial_risk>=90 and club.distress_since is not null then
   if d-club.distress_since>=21 and d-coalesce(spell_start,d-999)>=45 then
    perform public.mgr_fire(p_career,'irresponsabilidade financeira: o clube está à beira da falência');
   else
    perform public.cw_news_add(p_career,'bankrupt-warning:'||own||':'||to_char(d,'IYYY-IW'),'board','Último aviso: clube à beira da falência',
     'O risco financeiro chegou a '||round(club.financial_risk)||'%. Sem vender atletas, cortar a folha ou investir recursos, você será demitido por irresponsabilidade financeira.',100,own);
   end if;
  end if;
 end if;
end $function$;

CREATE OR REPLACE FUNCTION public.cw_jobs_tick(p_career uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
#variable_conflict use_column
declare w public.cw_world;c public.mgr_coach;off jsonb;wait_days int;
begin
 -- Empregado: outros clubes procuram com mais frequência, principalmente quando a diretoria está satisfeita (evolução 34).
 select * into w from public.cw_world where career_id=p_career;select * into c from public.mgr_coach where career_id=p_career;
 update public.season_offers set status='expired',responded_at=now() where career_id=p_career and kind='coach' and status='pending' and expires_on<w.today;
 wait_days:=w.elapsed_days-coalesce(c.unemployed_day,w.elapsed_days);
 if (select count(*) from public.season_offers where career_id=p_career and kind='coach' and status='pending')<3 and
 ((c.status='unemployed' and (random()<public.cw_tick_probability(.10+c.reputation*.003) or wait_days>=10)) or (c.status='employed' and random()<public.cw_tick_probability((.006+c.reputation*.0004)*(case when c.board_confidence>=65 then 1.4 else 1 end)))) then
  off:=public.mgr_make_offer(p_career,w.primary_season,w.elapsed_days,c.status='unemployed' and wait_days>=10,true);
 end if;
 if c.status='employed' and (select contract_until from public.cw_coach where career_id=p_career)<w.today then
  perform public.mgr_end_spell(p_career,'expired');
  perform public.cw_news_add(p_career,'coach-expired:'||c.spell_id,'job','Contrato do treinador encerrado','O vínculo com '||public.mgr_club_name(c.club_id)||' chegou ao fim. Você está disponível para novas propostas.',100,c.club_id);
 end if;
 if c.status='employed' and (select contract_until from public.cw_coach where career_id=p_career) between w.today and w.today+60 then
  perform public.cw_news_add(p_career,'coach-renew:'||c.spell_id,'contract','Seu contrato entra nos meses finais','Negocie a renovação em Carreira antes do encerramento do vínculo.',95,c.club_id);
 end if;
end $function$;

CREATE OR REPLACE FUNCTION public.mgr_make_offer_before_world(p_career uuid, p_season uuid, p_day integer, p_force_weak boolean DEFAULT false, p_any_region boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_coach public.mgr_coach;
  v_s     public.career_seasons;
  v_reach numeric;
  v_cur   int;
  v_cand  record;
  v_pos   int;
  v_bonus int;
  v_pitch text;
  v_id    uuid;
  v_band  jsonb;
  v_obj   text;
  v_rank  int;
  v_lname text;
  v_rules jsonb;
begin
  select * into v_coach from public.mgr_coach where career_id = p_career;
  select * into v_s from public.career_seasons where id = p_season;
  v_reach := 56 + v_coach.reputation * 0.32;
  select strength into v_cur from public.sim_clubs where id = v_coach.club_id;

  with st as (   -- classificação atual das ligas da temporada (calculada uma vez só)
    select sc.competition_id as league, s.club_id, s.pos
      from public.season_competitions sc
      join public.sim_competitions c on c.id = sc.competition_id and c.kind = 'league'
      cross join lateral public.sim_standings(p_season, sc.competition_id, null) s
     where sc.season_id = p_season
  )
  select x.club_id as id, x.strength, x.name, x.league, x.other, t.pos, public.sim_club_weight(p_career, x.club_id) as w
    into v_cand
    from (
      select l.o_club as club_id, l.o_league as league, c.strength, c.name, false as other
        from public.mgr_region_league_clubs(p_career, v_s.region) l join public.sim_clubs c on c.id = l.o_club
      union all
      select l.o_club, l.o_league, c.strength, c.name, true
        from (select distinct region from public.sim_competitions where active and kind = 'league' and region <> v_s.region) r
        cross join lateral public.mgr_region_league_clubs(p_career, r.region) l
        join public.sim_clubs c on c.id = l.o_club
       where p_any_region and (not (select public.cw_runtime_enabled(p_career)) or (v_coach.reputation>=(select foreign_reputation from public.cw_runtime_rules) and coalesce((select credibility from public.cw_coach where career_id=p_career),65)>=(select foreign_credibility from public.cw_runtime_rules)))
    ) x
    left join st t on t.club_id = x.club_id and t.league = x.league and not x.other
   where x.club_id is distinct from v_coach.club_id
     and exists (select 1 from public.sim_players p where p.club_id = x.club_id and p.active)
     and x.strength <= v_reach + 2
     and (p_force_weak or x.strength >= v_reach - 14)
     and (v_coach.status = 'unemployed' or x.strength >= coalesce(v_cur, 0) - 1)
     and x.club_id not in (select o.from_club from public.season_offers o where o.career_id = p_career and o.status = 'pending')
     and x.club_id not in (select sp.club_id from public.mgr_spells sp where sp.career_id = p_career and sp.end_reason = 'fired'
                            and sp.ended_season = v_s.season_no)
   order by power(random(), 1.0 / greatest(public.sim_club_weight(p_career, x.club_id) * (1 + coalesce(t.pos, 10) / 20.0)
                                           * case when p_force_weak then 1 + (80 - x.strength) / 10.0 else 1 end
                                           * case when x.other then 0.6 else 1 end, 0.05)) desc
   limit 1;
  if v_cand.id is null then return null; end if;
  if not p_force_weak and random() > v_cand.w then return null; end if;

  -- meta que a diretoria vai cobrar (força do clube entre os rivais da mesma liga)
  select rules, name into v_rules, v_lname from public.sim_competitions where id = v_cand.league;
  select count(*) + 1 into v_rank
    from public.mgr_region_league_clubs(p_career, (select region from public.sim_competitions where id = v_cand.league)) l
    join public.sim_clubs c2 on c2.id = l.o_club
   where l.o_league = v_cand.league and c2.strength > v_cand.strength;
  select b into v_band from jsonb_array_elements(coalesce(v_rules -> 'objectives', '[]'::jsonb)) b
   where (b ->> 'rank_max')::int >= v_rank order by (b ->> 'rank_max')::int limit 1;
  v_obj := lower(left(coalesce(v_band ->> 'label', 'fazer uma boa campanha'), 1)) || substr(coalesce(v_band ->> 'label', 'fazer uma boa campanha'), 2);
  v_pos := v_cand.pos;
  v_bonus := (round((200 + v_cand.strength * 6) / 50.0) * 50)::int;
  v_pitch := case
    when v_cand.other then format('%s, da %s, quer você no comando na próxima temporada. Meta: %s.', public.mgr_club_o(v_cand.id, true), v_lname, v_obj)
    when v_pos is not null and v_pos > 14 then format('%s está em %sº e precisa de um treinador. Meta: %s.', public.mgr_club_o(v_cand.id, true), v_pos, v_obj)
    when v_pos is not null then format('%s (%sº na %s) quer você no comando. Meta: %s.', public.mgr_club_o(v_cand.id, true), v_pos, v_lname, v_obj)
    else format('%s quer você no comando. Meta: %s.', public.mgr_club_o(v_cand.id, true), v_obj) end;

  insert into public.season_offers (career_id, season_id, from_club, bonus_coins, pitch, kind, expires_day, context)
  values (p_career, p_season, v_cand.id, v_bonus, v_pitch, 'coach', p_day + 5,
          jsonb_build_object('position', v_pos, 'objective', v_obj, 'strength', v_cand.strength, 'league', v_cand.league,
                             'region', (select region from public.sim_competitions where id = v_cand.league), 'abroad', v_cand.other))
  returning id into v_id;
  perform public.mgr_msg(p_career, p_season, p_day, 'offer', 'Proposta: ' || v_cand.name, v_pitch, v_cand.id);
  return jsonb_build_object('id', v_id, 'club_id', v_cand.id, 'bonus_coins', v_bonus, 'pitch', v_pitch, 'expires_day', p_day + 5,
                            'context', jsonb_build_object('position', v_pos, 'objective', v_obj, 'league', v_cand.league, 'abroad', v_cand.other));
end;
$function$;

CREATE OR REPLACE FUNCTION public.cw_finance_tick(p_career uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
#variable_conflict use_column
declare w public.cw_world;club public.cw_clubs;coach public.mgr_coach;risk numeric;rescue bigint;ref text;ct public.cw_contracts;staff public.cw_coach_contracts;paid bigint;balance bigint;
begin
 select * into w from public.cw_world where career_id=p_career;
 if extract(day from w.today)=1 then perform public.cw_settle_month(p_career,(date_trunc('month',w.today)-interval '1month')::date);end if;
 perform public.cw_repay_arrears(p_career);
 select * into coach from public.mgr_coach where career_id=p_career;
 for club in select * from public.cw_clubs where career_id=p_career and (not (select public.cw_runtime_enabled(p_career)) or club_id in (select public.cw_domestic_clubs(p_career)) or club_id=coach.club_id) order by club_id loop
  risk:=least(100,round(100.0*club.debt/greatest(club.monthly_revenue*6,1)+case when club.cash<public.cw_payroll(p_career,club.club_id) then 25 else 0 end,2));
  update public.cw_clubs set financial_risk=risk,distress_since=case when risk>=75 then coalesce(distress_since,w.today) else null end where career_id=p_career and club_id=club.club_id and (financial_risk is distinct from risk or (risk>=75 and distress_since is null) or (risk<75 and distress_since is not null));
  if risk>=75 and club.rescue_year is distinct from extract(year from w.today)::int then
   rescue:=round(club.initial_budget*(select annual_rescue_fraction from public.cw_rules));
   perform public.cw_cash(p_career,club.club_id,rescue,'recovery',extract(year from w.today)::text,'Plano limitado de recuperação financeira');
   update public.cw_clubs set debt=debt+rescue,rescue_year=extract(year from w.today)::int where career_id=p_career and club_id=club.club_id;
   perform public.cw_news_add(p_career,'recovery:'||club.club_id||':'||extract(year from w.today),'finance',public.mgr_club_name(club.club_id)||' adota recuperação financeira',
    'A diretoria limita novas contratações e oferece um plano de recuperação. O clube segue disputando suas competições.',case when coach.club_id=club.club_id then 95 else 45 end,club.club_id);
  end if;
  if coach.club_id=club.club_id and risk>=75 then
   perform public.cw_news_add(p_career,'finance-warning:'||club.club_id||':'||to_char(w.today,'IYYY-IW'),'board','A diretoria cobra responsabilidade financeira',
    'A dívida ameaça a folha salarial. Venda atletas por negociação, reduza gastos ou invista recursos. Persistir nesta situação coloca seu emprego em risco.',95,club.club_id);
   if club.distress_since is not null and w.today-club.distress_since>=45 then
    update public.mgr_coach set board_confidence=greatest(0,board_confidence-3) where career_id=p_career;
    if w.today-club.distress_since>=60 then perform public.mgr_fire(p_career,'má gestão financeira persistente');end if;
   end if;
  end if;
 end loop;
 -- Expiry is a real release; pre-contracts are registered by the market service.
 for ct in select * from public.cw_contracts where career_id=p_career and status='active' and expires_on<w.today for update loop
  update public.cw_contracts set status='expired',ended_on=expires_on where id=ct.id;
  update public.mgr_players set club_id=null where career_id=p_career and player_id=ct.player_id and club_id=ct.club_id;
  perform public.cw_prune_lineups(p_career,ct.player_id);
  perform public.cw_news_add(p_career,'expiry:'||ct.id,'contract',public.mgr_player_name(ct.player_id)||' encerra seu contrato',
   'O atleta está livre após o encerramento do vínculo com '||public.mgr_club_name(ct.club_id)||'.',case when ct.club_id=coach.club_id then 85 else 30 end,ct.club_id,ct.player_id);
 end loop;
end $function$;

do $$ begin if to_regprocedure('public.cw_settle_month_before_v38_before_v45(uuid,date)') is null then alter function public.cw_settle_month_before_v38(uuid,date) rename to cw_settle_month_before_v38_before_v45;end if;end $$;

CREATE OR REPLACE FUNCTION public.cw_settle_month_before_v38(p_career uuid, p_month date)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
#variable_conflict use_column
declare month_end date:=(p_month+interval '1 month - 1 day')::date;month_days int;ct public.cw_contracts;staff public.cw_coach_contracts;club public.cw_clubs;
 due bigint;paid bigint;before_cash bigint;overlap int;ref text;apps int;goals int;revenue bigint;surplus bigint;debt_paid bigint;
begin
 perform 1 from public.careers where id=p_career for update;
 month_days:=month_end-p_month+1;
 for club in select * from public.cw_clubs where career_id=p_career and (not (select public.cw_runtime_enabled(p_career)) or club_id in (select public.cw_domestic_clubs(p_career)) or exists(select 1 from public.cw_coach_contracts cc where cc.career_id=p_career and cc.club_id=cw_clubs.club_id)) order by club_id loop
  ref:=to_char(p_month,'YYYY-MM');
  select count(*) into apps from public.season_fixtures f join public.cw_fixture_dates d on d.fixture_id=f.id
   where d.career_id=p_career and f.status='played' and f.home_club=club.club_id and d.due_on between p_month and month_end;
  revenue:=club.monthly_revenue+apps*(300+club.prestige::int*12);
  perform public.cw_cash(p_career,club.club_id,revenue,'commercial',ref,'Receitas comerciais, torcida e bilheteria');
  perform public.cw_cash(p_career,club.club_id,-round(revenue*.12)::bigint,'operations',ref,'Comissão técnica e operação do clube',true);
 end loop;
 for ct in select * from public.cw_contracts where career_id=p_career and starts_on<=month_end and coalesce(ended_on,expires_on)>=p_month and (not (select public.cw_runtime_enabled(p_career)) or exists(select 1 from public.cw_coach_contracts cc where cc.career_id=p_career and cc.club_id=cw_contracts.club_id)) order by club_id,id loop
  ref:=ct.id::text||':'||to_char(p_month,'YYYY-MM');
  if exists(select 1 from public.cw_finance where career_id=p_career and club_id=ct.club_id and kind='wages' and reference=ref) then continue;end if;
  overlap:=greatest(0,least(month_end,ct.expires_on,coalesce(ct.ended_on,ct.expires_on))-greatest(p_month,ct.starts_on)+1);
  select count(*),coalesce(sum(mp.goals),0) into apps,goals from public.cw_appearances mp
   where mp.career_id=p_career and mp.player_id=ct.player_id and mp.club_id=ct.club_id and mp.minutes>0 and mp.on_date between greatest(p_month,ct.starts_on) and least(month_end,ct.expires_on,coalesce(ct.ended_on,ct.expires_on));
  due:=round(ct.monthly_salary*overlap::numeric/month_days)+apps*ct.appearance_bonus+goals*ct.goal_bonus;
  if due<=0 then continue;end if;
  select cash into before_cash from public.cw_clubs where career_id=p_career and club_id=ct.club_id;
  paid:=least(before_cash,due);
  perform public.cw_cash(p_career,ct.club_id,-due,'wages',ref,'Salário de '||public.mgr_player_name(ct.player_id),true,jsonb_build_object('contract_id',ct.id,'paid',paid,'owed',due-paid));
  update public.cw_contracts set arrears=arrears+due-paid where id=ct.id;
 end loop;

 if public.cw_runtime_enabled(p_career) then
 for club in select * from public.cw_clubs z where z.career_id=p_career and z.club_id in (select public.cw_domestic_clubs(p_career))
 and not exists(select 1 from public.cw_coach_contracts cc where cc.career_id=p_career and cc.club_id=z.club_id) order by z.club_id loop
  with amounts as(
   select x.id,x.monthly_salary,x.arrears,
   round(x.monthly_salary*greatest(0,least(month_end,x.expires_on,coalesce(x.ended_on,x.expires_on))-greatest(p_month,x.starts_on)+1)::numeric/month_days)
   +coalesce((select count(*)*x.appearance_bonus+coalesce(sum(a.goals),0)*x.goal_bonus from public.cw_appearances a where a.career_id=p_career and a.player_id=x.player_id and a.club_id=x.club_id and a.minutes>0 and a.on_date between greatest(p_month,x.starts_on) and least(month_end,x.expires_on,coalesce(x.ended_on,x.expires_on))),0) amount
   from public.cw_contracts x where x.career_id=p_career and x.club_id=club.club_id and x.starts_on<=month_end and coalesce(x.ended_on,x.expires_on)>=p_month
  ),running as(select *,coalesce(sum(amount) over(order by id rows between unbounded preceding and 1 preceding),0) before_due from amounts),
  arrears as(update public.cw_contracts x set arrears=x.arrears+greatest(0,r.amount-greatest(0,club.cash-r.before_due)) from running r
   where x.id=r.id and r.amount>greatest(0,club.cash-r.before_due) returning x.id)
  select coalesce(sum(amount),0) into due from running;
  if due>0 then perform public.cw_cash(p_career,club.club_id,-due,'wages','club:'||to_char(p_month,'YYYY-MM'),'Folha salarial do mês',true,jsonb_build_object('compacted',true,'paid',least(club.cash,due),'owed',greatest(0,due-club.cash)));end if;
 end loop;
 end if;
 for staff in select * from public.cw_coach_contracts where career_id=p_career and starts_on<=month_end and coalesce(ended_on,expires_on)>=p_month order by id loop
  ref:=staff.id::text||':'||to_char(p_month,'YYYY-MM');
  if exists(select 1 from public.cw_finance where career_id=p_career and club_id=staff.club_id and kind='coach_salary' and reference=ref) then continue;end if;
  overlap:=greatest(0,least(month_end,staff.expires_on,coalesce(staff.ended_on,staff.expires_on))-greatest(p_month,staff.starts_on)+1);
  due:=round(staff.monthly_salary*overlap::numeric/month_days);
  if due<=0 then continue;end if;
  select cash into before_cash from public.cw_clubs where career_id=p_career and club_id=staff.club_id;
  paid:=least(before_cash,due);
  perform public.cw_cash(p_career,staff.club_id,-due,'coach_salary',ref,'Salário do treinador',true,jsonb_build_object('paid',paid,'owed',due-paid));
  if paid>0 then perform public.econ_apply(p_career,'coins',paid::int,'coach_salary',ref);end if;
  update public.cw_coach_contracts set arrears=arrears+due-paid where id=staff.id;
 end loop;
 for club in select * from public.cw_clubs where career_id=p_career and (not (select public.cw_runtime_enabled(p_career)) or club_id in (select public.cw_domestic_clubs(p_career)) or exists(select 1 from public.cw_coach_contracts cc where cc.career_id=p_career and cc.club_id=cw_clubs.club_id)) order by club_id loop
  -- Retained surpluses are recorded as club infrastructure, not unlimited cash for players.
  -- Seu clube pode juntar até 10× o orçamento inicial para contratar; os da IA seguem com 3×.
  -- O caixa do seu clube é seu: nunca vira "patrimônio". Só os clubes da IA guardam o excedente acima de 3× o orçamento.
  surplus:=case when club.club_id=(select mc.club_id from public.mgr_coach mc where mc.career_id=p_career and mc.status='employed') then 0
   else greatest(0,club.cash-3*club.initial_budget) end;
  if surplus>0 and club.debt=0 and not exists(select 1 from public.cw_finance where career_id=p_career and club_id=club.club_id and kind='infrastructure' and reference=to_char(p_month,'YYYY-MM')) then
   perform public.cw_cash(p_career,club.club_id,-surplus,'infrastructure',to_char(p_month,'YYYY-MM'),'Investimento patrimonial da diretoria');
   update public.cw_clubs set infrastructure=infrastructure+surplus where career_id=p_career and club_id=club.club_id;
  end if;
 end loop;
end $function$;

CREATE OR REPLACE FUNCTION public.mgr_init_world(p_career uuid)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_n int;
begin
insert into public.mgr_players (career_id, player_id, club_id, rhythm)
select p_career, p.id, p.club_id, case when p.is_youth then 50 else 70 end
from public.sim_players p where p.active and p.club_id is not null and (p.club_id=(select club_id from public.mgr_coach where career_id=p_career) or exists(select 1 from public.career_seasons s join public.sim_clubs c on c.id=p.club_id and c.region=s.region where s.career_id=p_career and s.mode='coach' and s.status='active'))
on conflict (career_id, player_id) do nothing;
get diagnostics v_n = row_count;
return v_n;
end;
$function$;

CREATE OR REPLACE FUNCTION public.cw_initialize_finances(p_career uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
#variable_conflict use_column
declare w public.cw_world;r record;fresh boolean;
begin
 select * into w from public.cw_world where career_id=p_career;
 if not w.stats_initialized then
  insert into public.cw_stats_opening(career_id,season_id,player_id,competition_id,club_id,apps,minutes,goals,assists,rating_sum)
   select p_career,st.season_id,st.player_id,st.competition_id,st.club_id,st.apps,st.minutes,st.goals,st.assists,st.rating_sum
   from public.mgr_player_stats st join public.career_seasons cs on cs.id=st.season_id where cs.career_id=p_career on conflict do nothing;
  update public.cw_world set stats_initialized=true where career_id=p_career;
 end if;
 insert into public.cw_clubs(career_id,club_id,cash,initial_budget,monthly_revenue,prestige,strategy,fanbase)
 select p_career,c.id,round((5000+power(greatest(5,c.strength-40),3)*3)*case when public.cw_region(c.id)='ENG' then 1.8 else 1 end),
 round((5000+power(greatest(5,c.strength-40),3)*3)*case when public.cw_region(c.id)='ENG' then 1.8 else 1 end),
 round((2000+power(greatest(5,c.strength-40),2)*25)*case when public.cw_region(c.id)='ENG' then 1.5 else 1 end),
 c.strength,case abs(hashtext(c.id)::bigint)%4 when 0 then 'youth' when 1 then 'balanced' when 2 then 'ambitious' else 'sustainable' end,
 greatest(1000,(c.strength-30)*(c.strength-30)*150)
 from public.sim_clubs c where exists(select 1 from public.mgr_players mp where mp.career_id=p_career and mp.club_id=c.id) on conflict do nothing;
 insert into public.cw_players(career_id,player_id,age_at_start,age_estimated,potential)
 select p_career,p.id,coalesce(p.age,case when p.is_youth then 19 else 26 end),p.age is null,
 least(99,round(r.rating)+case when coalesce(p.age,case when p.is_youth then 19 else 26 end)<23 then 12 else 3 end)
 from public.mgr_players mp join public.sim_players p on p.id=mp.player_id join public.sim_player_pos_ratings r on r.player_id=p.id and r.pos=p.position
 where mp.career_id=p_career on conflict do nothing;
 update public.cw_players set market_value=public.cw_player_value(p_career,player_id) where career_id=p_career and market_value=0;
 fresh:=not exists(select 1 from public.cw_contracts where career_id=p_career);
 insert into public.cw_contracts(career_id,player_id,club_id,starts_on,expires_on,monthly_salary,role)
 select p_career,mp.player_id,mp.club_id,w.today,(w.today+make_interval(years=>1+(abs(hashtext(mp.player_id)::bigint)%4)::int))::date,
 greatest(40,round(public.cw_player_value(p_career,mp.player_id)*.0065)),case when p.is_youth then 'prospect' when r.rating>=82 then 'key' when r.rating>=74 then 'starter' else 'rotation' end
 from public.mgr_players mp join public.sim_players p on p.id=mp.player_id join public.sim_player_pos_ratings r on r.player_id=p.id and r.pos=p.position
 where mp.career_id=p_career and mp.club_id is not null and (fresh or not exists(select 1 from public.cw_contracts ct where ct.career_id=p_career and ct.player_id=mp.player_id));
 -- Papel prometido = papel do contrato ativo. Atualiza atleta a atleta pela chave primária: numa carreira
 -- recém-criada as estatísticas das tabelas não existem e um join cruzava todos os atletas com todos os contratos.
 for r in select ct.player_id,ct.role from public.cw_contracts ct where ct.career_id=p_career and ct.status='active' and not exists(select 1 from public.cw_runtime where career_id=p_career) loop
  update public.cw_players set promised_role=r.role where career_id=p_career and player_id=r.player_id and promised_role is distinct from r.role;
 end loop;
 insert into public.cw_finance(career_id,club_id,on_date,kind,amount,cash_after,reference,description)
 select p_career,c.club_id,w.today,'opening',c.cash,c.cash,'opening','Orçamento inicial estimado do clube' from public.cw_clubs c where c.career_id=p_career on conflict do nothing;
 insert into public.cw_coach_contracts(career_id,spell_id,club_id,starts_on,expires_on,monthly_salary)
 select p_career,c.spell_id,c.club_id,w.today,(w.today+interval '2years')::date,p.monthly_salary from public.mgr_coach c join public.cw_coach p on p.career_id=c.career_id
 where c.career_id=p_career and c.status='employed' and c.spell_id is not null on conflict do nothing;
end $function$;

create or replace function public.cw_materialize_club(p_career uuid,p_club text)
returns void language plpgsql security definer set search_path=public as $$
begin
 insert into public.mgr_players(career_id,player_id,club_id,rhythm)
 select p_career,p.id,p.club_id,case when p.is_youth then 50 else 70 end from public.sim_players p
 where p.club_id=p_club and p.active and not exists(select 1 from public.mgr_players mp where mp.career_id=p_career and mp.player_id=p.id)
 on conflict do nothing;
 if exists(select 1 from public.cw_world where career_id=p_career) and exists(select 1 from public.mgr_players p left join public.cw_players cp using(career_id,player_id) where p.career_id=p_career and p.club_id=p_club and cp.player_id is null) then
 perform public.cw_initialize_finances(p_career);end if;
end $$;


do $$ begin if to_regprocedure('public.mgr_match_create_before_v45(bigint,uuid,character,jsonb)') is null then alter function public.mgr_match_create(bigint,uuid,character,jsonb) rename to mgr_match_create_before_v45;end if;end $$;

CREATE OR REPLACE FUNCTION public.mgr_match_create(p_fixture bigint, p_career uuid, p_user_side character, p_user_lineup jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
#variable_conflict use_column
declare v_side text;factor numeric;club text;due date;previous_day date;recovery int;
begin
 if public.cw_runtime_enabled(p_career) then
 perform public.cw_materialize_club(p_career,(select home_club from public.season_fixtures where id=p_fixture));
 perform public.cw_materialize_club(p_career,(select away_club from public.season_fixtures where id=p_fixture));
 perform public.cw_recover_club(p_career,(select home_club from public.season_fixtures where id=p_fixture));
 perform public.cw_recover_club(p_career,(select away_club from public.season_fixtures where id=p_fixture));
 end if;
 if exists(select 1 from public.mgr_matches where fixture_id=p_fixture) then return;end if;
 if p_user_side is null and exists(select 1 from public.cw_world where career_id=p_career) then
  select due_on into due from public.cw_fixture_dates where fixture_id=p_fixture;
  if due<(select started_on from public.cw_world where career_id=p_career) then
  for club in select home_club from public.season_fixtures where id=p_fixture union all select away_club from public.season_fixtures where id=p_fixture loop
   select max(fd.due_on) into previous_day from public.cw_fixture_dates fd join public.season_fixtures fx on fx.id=fd.fixture_id where fd.career_id=p_career and fx.status='played' and club in(fx.home_club,fx.away_club) and fd.due_on<due;
   recovery:=greatest(0,least(14,coalesce(due-previous_day,3)));
   update public.mgr_players set condition=least(100,condition+recovery*4.3),
    injury=case when injured_until-recovery<=(select elapsed_days from public.cw_world where career_id=p_career) then null else injury end,
    injured_until=case when injured_until-recovery<=(select elapsed_days from public.cw_world where career_id=p_career) then null else injured_until-recovery end
    where career_id=p_career and club_id=club;
  end loop;
  end if;
 end if;
 perform public.mgr_match_create_before_world(p_fixture,p_career,p_user_side,p_user_lineup);
 if exists(select 1 from public.cw_world where career_id=p_career) then
  foreach v_side in array array['h','a'] loop
   select .90+coalesce(avg(cp.morale),65)/1000 into factor from public.mgr_match_players mp join public.cw_players cp on cp.career_id=p_career and cp.player_id=mp.player_id where mp.fixture_id=p_fixture and mp.side=v_side and mp.status='on';
   update public.mgr_matches set state=jsonb_set(state,array['form',case when v_side='h' then '0' else '1' end],to_jsonb(round((state->'form'->>case when v_side='h' then 0 else 1 end)::numeric*factor,3))) where fixture_id=p_fixture;
  end loop;
 end if;
end $function$;

do $$ begin if to_regprocedure('public.mgr_player_detail_before_v45(text,bigint)') is null then alter function public.mgr_player_detail(text,bigint) rename to mgr_player_detail_before_v45;end if;end $$;

create or replace function public.mgr_player_detail(p_player text,p_fixture bigint default null)
returns jsonb language plpgsql security definer set search_path=public as $$
declare c public.careers;club text;begin c:=public.mgr_lock();select coalesce(mp.club_id,p.club_id) into club from public.sim_players p left join public.mgr_players mp on mp.player_id=p.id and mp.career_id=c.id where p.id=p_player;
perform public.cw_materialize_club(c.id,club);perform public.cw_recover_club(c.id,club);return public.mgr_player_detail_before_v45(p_player,p_fixture);end $$;

do $$ begin if to_regprocedure('public.mgr_squad_before_v45(text)') is null then alter function public.mgr_squad(text) rename to mgr_squad_before_v45;end if;end $$;

create or replace function public.mgr_squad(p_club text default null)
returns jsonb language plpgsql security definer set search_path=public as $$
declare c public.careers;club text;begin c:=public.mgr_lock();club:=coalesce(p_club,(select club_id from public.mgr_coach where career_id=c.id));
perform public.cw_materialize_club(c.id,club);perform public.cw_recover_club(c.id,club);return public.mgr_squad_before_v45(p_club);end $$;

revoke all on function public.career_hub_read(),public.career_runtime_initialize() from public,anon;
grant execute on function public.career_hub_read(),public.career_runtime_initialize() to authenticated;
revoke all on function public.cw_materialize_club(uuid,text) from public,anon,authenticated;
insert into public.cw_runtime(career_id,catalog_version,enabled,last_recovery_day,deferred_live)
select w.career_id,r.catalog_version,not exists(select 1 from public.mgr_matches m where m.career_id=w.career_id and m.status='live' and m.user_side is not null),w.elapsed_days,exists(select 1 from public.mgr_matches m where m.career_id=w.career_id and m.status='live' and m.user_side is not null)
from public.cw_world w cross join public.cw_runtime_rules r on conflict do nothing;
notify pgrst,'reload schema';
commit;