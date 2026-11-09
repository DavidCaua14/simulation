-- Leituras do modo carreira sem a trava da carreira.
-- Antes, telas de leitura chamavam mgr_lock(): cada uma esperava na fila atrás de qualquer outra chamada da mesma
-- carreira (um treino de 2 ms ficava em média 750 ms parado). Agora usam mgr_read(), que só identifica a carreira.
-- Nenhum dado de save muda: as funções abaixo são as mesmas, só a primeira linha trocou.
-- mgr_read() cai no caminho antigo (mgr_lock) quando a carreira ainda precisa ser preparada, para a criação do
-- mundo continuar protegida pela trava.
CREATE OR REPLACE FUNCTION public.mgr_read()
 RETURNS public.careers
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare c public.careers;
begin
 c:=public.cw_read_career();
 if not exists(select 1 from public.mgr_coach where career_id=c.id)
  or not exists(select 1 from public.cw_world where career_id=c.id and stats_initialized)
  or not exists(select 1 from public.cw_runtime where career_id=c.id and (enabled or not deferred_live)) then
  return public.mgr_lock();
 end if;
 perform public.cw_set_ctx(c.id);
 return c;
end $function$;

REVOKE ALL ON FUNCTION public.mgr_read() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.mgr_read() TO service_role;

CREATE OR REPLACE FUNCTION public.career_club_dev_read()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare car public.careers;own text;w public.cw_world;
begin
 car:=public.mgr_read();
 select club_id into own from public.mgr_coach where career_id=car.id and status='employed';
 select * into w from public.cw_world where career_id=car.id;
 if own is null then return jsonb_build_object('enabled',public.cw_dev_on(),'employed',false);end if;
 perform public.cw_dev_ensure_club(car.id,own);
 return jsonb_build_object('enabled',public.cw_dev_on(),'employed',true,'club_id',own,'today',w.today,
  'difficulty',(select jsonb_build_object('id',lv.id,'label',lv.label,'description',lv.description,'profile',c.difficulty,
    'profile_label',(select label from public.sim_difficulty_profiles where id=c.difficulty),'can_change',c.difficulty_season is distinct from w.primary_season)
   from public.careers c join public.career_difficulty_levels lv on lv.id=coalesce(c.difficulty_level,'normal') where c.id=car.id),
  'difficulty_levels',(select jsonb_agg(jsonb_build_object('id',id,'label',label,'description',description) order by sort_order) from public.career_difficulty_levels),
  'window_open',public.cw_window_open(public.cw_region(own),w.today),
  'budget',public.cw_available_budget(car.id,own),
  'infrastructure',(select infrastructure from public.cw_clubs where career_id=car.id and club_id=own),
  'training',(select to_jsonb(t)-'career_id' from public.cw_training t where career_id=car.id and club_id=own),
  'facilities',(select jsonb_agg(jsonb_build_object('kind',f.kind,'level',f.level,'initial_level',f.initial_level,'target_level',f.target_level,
    'building_until',f.building_until,'started_on',f.started_on,
    'next_cost',case when f.level<5 then public.cw_facility_cost(f.kind,f.level+1,own) end,
    'next_months',case when f.level<5 then public.cw_facility_months(f.kind,f.level+1) end) order by case f.kind when 'training' then 1 when 'youth' then 2 when 'medical' then 3 else 4 end)
    from public.cw_facilities f where f.career_id=car.id and f.club_id=own),
  'staff',(select jsonb_agg(jsonb_build_object('role',s.role,'level',s.level,'initial_level',s.initial_level,'monthly_salary',s.monthly_salary,'hired_on',s.hired_on,
    'next_salary',case when s.level<5 then public.cw_staff_salary(s.level+1) end) order by s.role)
    from public.cw_staff s where s.career_id=car.id and s.club_id=own),
  'set_pieces',(select jsonb_build_object('penalty',sp.penalty,'free_kick',sp.free_kick,'corner',sp.corner,'captain',sp.captain) from public.cw_set_pieces sp where sp.career_id=car.id and sp.club_id=own),
  'familiarity',(select jsonb_agg(jsonb_build_object('formation',f.id,'value',round(public.cw_familiarity_value(car.id,own,f.id))) order by f.sort)
    from public.sim_formations f),
  'energy',jsonb_build_object('energy',car.energy,'bonus',car.bonus_energy),
  'loans',(select coalesce(jsonb_agg(jsonb_build_object('id',l.id,'player_id',l.player_id,'player',public.mgr_player_name(l.player_id),'parent_club',l.parent_club,
    'borrower_club',l.borrower_club,'status',l.status,'origin',l.origin,'wage_share',l.wage_share,'fee',l.fee,'role',l.role,'starts_on',l.starts_on,'ends_on',l.ends_on,
    'expires_on',l.expires_on,'response',l.response) order by l.created_on desc),'[]')
    from public.cw_loans l where l.career_id=car.id and own in(l.parent_club,l.borrower_club) and (l.status in('offered','active') or l.created_on>w.today-60)),
  'scouting',(select coalesce(jsonb_agg(jsonb_build_object('player_id',s.player_id,'player',public.mgr_player_name(s.player_id),'requested_on',s.requested_on,'ready_on',s.ready_on,
    'ready',s.ready_on<=w.today)||case when s.ready_on<=w.today then public.cw_scout_report(car.id,s.player_id,w.today) else '{}'::jsonb end
    order by s.ready_on<=w.today desc,s.requested_on desc),'[]')
    from public.cw_scouting s where s.career_id=car.id and s.requested_on>w.today-120),
  'youth',(select coalesce(jsonb_agg(jsonb_build_object('player_id',p.id,'name',p.short_name,'position',p.position,'club_id',mp.club_id) order by p.imported_at desc),'[]')
    from public.sim_players p join public.mgr_players mp on mp.career_id=car.id and mp.player_id=p.id where p.career_id=car.id and mp.club_id=own),
  'reputation',(select jsonb_build_object('reputation',c.reputation,'credibility',cc.credibility,'titles',c.titles,'seasons',c.seasons)
    from public.mgr_coach c left join public.cw_coach cc on cc.career_id=c.career_id where c.career_id=car.id));
end $function$
;

CREATE OR REPLACE FUNCTION public.career_drills()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare car public.careers;
begin
 car:=public.mgr_read();
 return jsonb_build_object('coins',(select coins from public.careers where id=car.id),'all_price',public.cw_drill_all_price(),
  'drills',(select jsonb_agg(jsonb_build_object('kind',r.kind,'label',r.label,'description',r.description,'price',r.price,'games',r.games,
    'games_left',coalesce(b.games_left,0)) order by r.sort_order)
   from public.cw_drill_rules r left join public.cw_match_boosts b on b.career_id=car.id and b.kind=r.kind));
end $function$
;

CREATE OR REPLACE FUNCTION public.career_finance_history()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
#variable_conflict use_column
declare car public.careers;own text;
begin car:=public.mgr_read();select club_id into own from public.mgr_coach where career_id=car.id;
 return(select coalesce(jsonb_agg(to_jsonb(x) order by id desc),'[]') from(select id,on_date,kind,amount,cash_after,description,metadata from public.cw_finance where career_id=car.id and club_id=own order by id desc limit 60)x);end $function$
;

CREATE OR REPLACE FUNCTION public.career_negotiations()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
#variable_conflict use_column
declare car public.careers;own text;d date;
begin
 car:=public.mgr_read();select club_id into own from public.mgr_coach where career_id=car.id;select today into d from public.cw_world where career_id=car.id;
 return(select coalesce(jsonb_agg(to_jsonb(x)),'[]') from(select n.id,n.player_id,public.mgr_player_name(n.player_id) as player_name,n.seller_club,n.buyer_club,n.status,n.initiator,n.fee,n.installments,n.performance_bonus,n.monthly_salary,n.contract_years,n.signing_bonus,n.role,n.appearance_bonus,n.goal_bonus,n.created_on,n.reply_on,n.expires_on,n.register_on,n.round_no,n.response,n.valuation,
 case when n.buyer_club=own and n.initiator<>'renewal' then
  case when n.status='completed' and exists(select 1 from public.mgr_players mp join public.cw_contracts ct using(career_id,player_id)
    where mp.career_id=n.career_id and mp.player_id=n.player_id and mp.club_id=n.buyer_club and ct.club_id=n.buyer_club and ct.status='active' and ct.expires_on>=d) then 'registered'
   when n.status='completed' then 'left'
   when n.status in('agreed','precontract') then case when not public.cw_window_open(public.cw_region(n.buyer_club),d) then 'waiting_window' else 'waiting_registration' end
   when n.status in('player_pending','player_counter') then 'player_decision'
   when n.status in('club_pending','club_counter') then 'club_agreement'
   else 'not_registered' end end as arrival_status,
  public.cw_salary_demand(car.id,n.player_id,n.buyer_club) salary_demand,public.cw_minimum_signing(car.id,n.player_id,n.buyer_club) minimum_signing_bonus,
  public.cw_project_reason(car.id,n.player_id,n.buyer_club) project_reason,
  (select coalesce(jsonb_agg(jsonb_build_object('date',h.on_date,'actor',h.actor,'state',h.state,'explanation',h.explanation,'terms',h.terms) order by h.id),'[]') from public.cw_offer_history h where h.negotiation_id=n.id and h.career_id=car.id) as history
 from public.cw_negotiations n where n.career_id=car.id and own in(n.buyer_club,n.seller_club) order by n.created_on desc,n.id limit 60)x);
end $function$
;

CREATE OR REPLACE FUNCTION public.career_wage_demand(p_player text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare car public.careers;own text;
begin
 car:=public.mgr_read();
 select club_id into own from public.mgr_coach where career_id=car.id and status='employed';
 if own is not null then perform public.cw_renewal_ask(car.id,p_player,own);end if;
 return jsonb_build_object('weekly_demand',public.cw_weekly(public.cw_salary_demand(car.id,p_player,own)),
  'max_years',(select max_contract_years from public.cw_rules),'reason',public.cw_project_reason(car.id,p_player,own));
end $function$
;

CREATE OR REPLACE FUNCTION public.mgr_history()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
#variable_conflict use_column
declare
  v_car public.careers;
  v_c   public.mgr_coach;
begin
  v_car := public.mgr_read();
  select * into v_c from public.mgr_coach where career_id = v_car.id;
  return jsonb_build_object(
    'coach', jsonb_build_object('reputation', round(v_c.reputation, 1), 'matches', v_c.matches, 'wins', v_c.wins, 'draws', v_c.draws,
      'losses', v_c.losses, 'gf', v_c.gf, 'ga', v_c.ga, 'titles', v_c.titles, 'fired_count', v_c.fired_count, 'seasons', v_c.seasons,
      'status', v_c.status, 'club_id', v_c.club_id),
    'spells', (select coalesce(jsonb_agg(jsonb_build_object('id', sp.id, 'club_id', sp.club_id, 'current', sp.id = v_c.spell_id,
        'started_year', sp.started_year, 'started_day', sp.started_day, 'started_season', sp.started_season,
        'ended_year', sp.ended_year, 'ended_day', sp.ended_day, 'end_reason', sp.end_reason,
        'matches', sp.matches, 'wins', sp.wins, 'draws', sp.draws, 'losses', sp.losses, 'gf', sp.gf, 'ga', sp.ga, 'titles', sp.titles)
        order by sp.created_at desc), '[]'::jsonb) from public.mgr_spells sp where sp.career_id = v_car.id),
    'seasons', (select coalesce(jsonb_agg(jsonb_build_object('id', s.id, 'year', s.year, 'region', s.region, 'season_no', s.season_no, 'status', s.status,
        'club_id', s.club_id, 'matches', s.matches, 'wins', s.wins, 'draws', s.draws, 'losses', s.losses,
        'xp_earned', s.xp_earned, 'coins_earned', s.coins_earned, 'summary', s.summary,
        'final_tables', (select coalesce(jsonb_object_agg(ft.competition_id,ft.standings),'{}'::jsonb) from public.season_final_tables ft where ft.season_id=s.id),
        'clubs', (select coalesce(jsonb_agg(distinct f.coach_club), '[]'::jsonb) from public.season_fixtures f where f.season_id = s.id and f.player_match),
        'objectives', (select coalesce(jsonb_agg(jsonb_build_object('label', o.label, 'status', o.status, 'club_id', o.club_id) order by o.priority desc), '[]'::jsonb)
                         from public.mgr_objectives o where o.season_id = s.id))
        order by s.season_no desc), '[]'::jsonb)
        from public.career_seasons s where s.career_id = v_car.id and (s.mode = 'coach' or s.was_coached)));
end;
$function$
;

CREATE OR REPLACE FUNCTION public.mgr_match_report(p_fixture bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_car public.careers;
begin
v_car := public.mgr_read();
if not exists (select 1 from public.season_fixtures f join public.career_seasons s on s.id = f.season_id
where f.id = p_fixture and s.career_id = v_car.id) then
raise exception 'Partida não encontrada.';
end if;
if exists (select 1 from public.mgr_matches where fixture_id = p_fixture) then
return public.mgr_match_payload(p_fixture, 0);
end if;
return (select jsonb_build_object('fixture_id', f.id, 'status', 'finished', 'home', f.home_club, 'away', f.away_club,
'score', jsonb_build_array(f.home_goals, f.away_goals), 'competition', f.competition_id, 'stage', f.stage, 'round', f.round_no,
'stats', f.stats, 'events', (select coalesce(jsonb_agg(jsonb_build_object('seq', e.seq, 'minute', e.minute, 'side', e.side, 'kind', e.kind,
'player', e.player_id, 'player_name', p1.short_name, 'player2', e.player2_id, 'player2_name', p2.short_name, 'detail', e.detail) order by e.seq), '[]')
from public.mgr_match_events e left join public.sim_players p1 on p1.id = e.player_id left join public.sim_players p2 on p2.id = e.player2_id
where e.fixture_id = f.id), 'players', '[]'::jsonb)
from public.season_fixtures f where f.id = p_fixture);
end;
$function$
;

CREATE OR REPLACE FUNCTION public.mgr_top_scorers(p_comp text DEFAULT NULL::text, p_limit integer DEFAULT 20)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
v_car public.careers;
v_s   public.career_seasons;
begin
v_car := public.mgr_read();
select * into v_s from public.career_seasons where career_id = v_car.id and mode = 'coach' order by season_no desc limit 1;
return jsonb_build_object(
'scorers', (select coalesce(jsonb_agg(x order by x.goals desc, x.assists desc, x.apps), '[]'::jsonb) from (
select st.player_id as id, p.short_name as name, st.club_id, sum(st.goals)::int as goals, sum(st.assists)::int as assists, sum(st.apps)::int as apps
from public.mgr_player_stats st join public.sim_players p on p.id = st.player_id
where st.season_id = v_s.id and (p_comp is null or st.competition_id = p_comp)
group by st.player_id, p.short_name, st.club_id having sum(st.goals) > 0
order by 4 desc, 5 desc, 6 limit p_limit) x),
'assists', (select coalesce(jsonb_agg(x order by x.assists desc, x.goals desc), '[]'::jsonb) from (
select st.player_id as id, p.short_name as name, st.club_id, sum(st.assists)::int as assists, sum(st.goals)::int as goals
from public.mgr_player_stats st join public.sim_players p on p.id = st.player_id
where st.season_id = v_s.id and (p_comp is null or st.competition_id = p_comp)
group by st.player_id, p.short_name, st.club_id having sum(st.assists) > 0
order by 4 desc, 5 desc limit p_limit) x));
end;
$function$
;

