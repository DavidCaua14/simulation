-- EVOLUÇÃO 18: análise do rival sem expor dados de outras carreiras.
begin;
create or replace function public.mgr_opponent_report(p_fixture bigint)
returns jsonb language plpgsql security definer set search_path=public as $$
declare
 car public.careers;coach public.mgr_coach;f public.season_fixtures;s public.career_seasons;m public.mgr_matches;
 opp text;form text;lineup jsonb;tactics jsonb;strength numeric;mine numeric;side text;is_home boolean;
begin
 car:=public.mgr_lock();
 select * into coach from public.mgr_coach where career_id=car.id;
 select fx.* into f from public.season_fixtures fx join public.career_seasons cs on cs.id=fx.season_id
  where fx.id=p_fixture and cs.career_id=car.id;
 if not found or coach.club_id is null or coach.club_id not in(f.home_club,f.away_club) then raise exception 'Partida não encontrada nesta carreira';end if;
 select * into s from public.career_seasons where id=f.season_id;
 opp:=case when f.home_club=coach.club_id then f.away_club else f.home_club end;
 side:=case when f.home_club=opp then 'h' else 'a' end;
 select * into m from public.mgr_matches where fixture_id=f.id and career_id=car.id;
 if found then
  form:=m.state->'formation'->>(case when side='h' then 0 else 1 end);
  tactics:=m.state->'tactics'->side;
  strength:=public.mgr_side_strength(f.id,side::char);
 else
  form:=public.mgr_ai_formation(car.id,opp);
  lineup:=public.mgr_auto_lineup(car.id,opp,form,f.competition_id,s.day_no);
  strength:=public.mgr_lineup_score(lineup,form)/11;
  mine:=coalesce((select public.mgr_lineup_score(jsonb_build_object('slots',l.slots),l.formation)/11 from public.mgr_lineups l where l.career_id=car.id and l.club_id=coach.club_id),(select cl.strength from public.sim_clubs cl where cl.id=coach.club_id),60);
  is_home:=f.home_club=opp and not coalesce((public.sim_phase(f.competition_id,f.stage)->>'neutral')::boolean,false);
  tactics:=public.mgr_ai_plan(car.id,opp,strength-mine,is_home);
 end if;
 return jsonb_build_object('fixture_id',f.id,'club_id',opp,'formation',form,'tactics',tactics,
   'style',(select c.style from public.mgr_ai_clubs c where c.career_id=car.id and c.club_id=opp),
   'live',m.status='live','strength',round(strength,1));
end $$;
revoke all on function public.mgr_opponent_report(bigint) from public,anon;
grant execute on function public.mgr_opponent_report(bigint) to authenticated;
create or replace function public.mgr_history()
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_car public.careers;
  v_c   public.mgr_coach;
begin
  v_car := public.mgr_lock();
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
        from public.career_seasons s where s.career_id = v_car.id and s.mode = 'coach'));
end;
$$;
create or replace function public.mgr_match_payload(p_fixture bigint, p_after_seq int)
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'engine_version',coalesce((m.state->>'engine_version')::int,1),'referee',m.state->'referee',
    'fixture_id', m.fixture_id, 'status', m.status, 'minute', m.minute, 'user_side', m.user_side,
    'score', m.state -> 'score', 'agg', m.state -> 'agg', 'decisive', m.state -> 'decisive', 'et', m.state -> 'et',
    'extra_time_rule', m.state -> 'extra_time_rule', 'pens', m.state -> 'pens',
    'competition', f.competition_id, 'stage', f.stage, 'round', f.round_no, 'leg', f.leg, 'group', f.group_label,
    'home', f.home_club, 'away', f.away_club, 'neutral', m.state -> 'neutral',
    'tactics', m.state -> 'tactics', 'formation', m.state -> 'formation',
    'subs', m.state -> 'subs', 'max_subs', m.state -> 'max_subs', 'max_windows', m.state -> 'max_windows',
    'events', (select coalesce(jsonb_agg(jsonb_build_object('seq', e.seq, 'minute', e.minute, 'side', e.side, 'kind', e.kind,
                 'player', e.player_id, 'player_name', p1.short_name, 'player2', e.player2_id, 'player2_name', p2.short_name, 'detail', e.detail)
                 order by e.seq), '[]'::jsonb)
                 from public.mgr_match_events e
                 left join public.sim_players p1 on p1.id = e.player_id left join public.sim_players p2 on p2.id = e.player2_id
                where e.fixture_id = m.fixture_id and e.seq > coalesce(p_after_seq, 0)),
    'stats', jsonb_build_object(
       'poss', jsonb_build_array(round(100.0 * (m.state -> 'poss' ->> 0)::int / greatest((m.state -> 'poss' ->> 0)::int + (m.state -> 'poss' ->> 1)::int, 1)),
                                 100 - round(100.0 * (m.state -> 'poss' ->> 0)::int / greatest((m.state -> 'poss' ->> 0)::int + (m.state -> 'poss' ->> 1)::int, 1))),
       'shots', jsonb_build_array((select coalesce(sum(shots), 0) from public.mgr_match_players where fixture_id = m.fixture_id and side = 'h'),
                                  (select coalesce(sum(shots), 0) from public.mgr_match_players where fixture_id = m.fixture_id and side = 'a')),
       'sot', jsonb_build_array((select coalesce(sum(sot), 0) from public.mgr_match_players where fixture_id = m.fixture_id and side = 'h'),
                                (select coalesce(sum(sot), 0) from public.mgr_match_players where fixture_id = m.fixture_id and side = 'a')),
       'fouls', jsonb_build_array((select coalesce(sum(fouls), 0) from public.mgr_match_players where fixture_id = m.fixture_id and side = 'h'),
                                  (select coalesce(sum(fouls), 0) from public.mgr_match_players where fixture_id = m.fixture_id and side = 'a')),
       'yellows', jsonb_build_array((select coalesce(sum(yellow), 0) from public.mgr_match_players where fixture_id = m.fixture_id and side = 'h'),
                                    (select coalesce(sum(yellow), 0) from public.mgr_match_players where fixture_id = m.fixture_id and side = 'a')),
       'reds', jsonb_build_array((select coalesce(sum(red), 0) from public.mgr_match_players where fixture_id = m.fixture_id and side = 'h'),
                                 (select coalesce(sum(red), 0) from public.mgr_match_players where fixture_id = m.fixture_id and side = 'a')),
       'saves', jsonb_build_array((select coalesce(sum(saves), 0) from public.mgr_match_players where fixture_id = m.fixture_id and side = 'h'),
                                  (select coalesce(sum(saves), 0) from public.mgr_match_players where fixture_id = m.fixture_id and side = 'a')),
       'corners', m.state -> 'corners', 'offsides', m.state -> 'offsides'),
    'players', (select coalesce(jsonb_agg(jsonb_build_object('id', mp.player_id, 'name', p.short_name, 'number', p.shirt_number, 'side', mp.side,
                 'slot', mp.slot, 'pos', mp.pos, 'natural', p.position, 'status', mp.status, 'starter', mp.starter, 'fit', mp.fit,
                 'cond', round(mp.cond), 'rating', mp.rating, 'goals', mp.goals, 'assists', mp.assists, 'yellow', mp.yellow, 'red', mp.red,
                 'injured', mp.injured, 'minutes', mp.minutes,
                 'overall', round((select r.eff from public.sim_player_pos_ratings r where r.player_id = mp.player_id and r.pos = coalesce(mp.pos, p.position))))
                 order by mp.side, (mp.status = 'on') desc, mp.slot, p.shirt_number), '[]'::jsonb)
                 from public.mgr_match_players mp join public.sim_players p on p.id = mp.player_id where mp.fixture_id = m.fixture_id),
    'summary', m.summary)
  from public.mgr_matches m join public.season_fixtures f on f.id = m.fixture_id
  where m.fixture_id = p_fixture
$$;
-- A interface só libera os controles novos depois que o backend correspondente existe.
do $$ begin
 if to_regprocedure('public.mgr_hub_before_seasons_v2()') is null then
  alter function public.mgr_hub() rename to mgr_hub_before_seasons_v2;
 end if;
end $$;
create or replace function public.mgr_hub()
returns jsonb language sql security definer set search_path=public as $$
 select public.mgr_hub_before_seasons_v2() || jsonb_build_object('simulation_version',2)
$$;
revoke all on function public.mgr_hub_before_seasons_v2(),public.mgr_hub() from public,anon,authenticated;
grant execute on function public.mgr_hub() to authenticated;
notify pgrst,'reload schema';
commit;
