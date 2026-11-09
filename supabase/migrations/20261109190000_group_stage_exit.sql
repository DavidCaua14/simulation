-- Queda na fase de grupos (2026-11-09): mais grave que cair no mata-mata.
-- Detectada depois de sim_advance: a fase de grupos acabou e o clube do treinador não está na fase seguinte.
-- Soma-se ao que a derrota/empate do último jogo já cobrou. Ajustes em public.mgr_failure_rules.

alter table public.mgr_failure_rules
  add column if not exists group_exit_board numeric not null default 22,       -- mata-mata: 14
  add column if not exists group_exit_fans numeric not null default 26,        -- mata-mata: 16
  add column if not exists group_exit_reputation numeric not null default 3,   -- mata-mata: 1,5
  add column if not exists group_exit_morale numeric not null default 20,      -- mata-mata: 12
  add column if not exists group_exit_rank_points int not null default 80;     -- mata-mata: 40

create or replace function public.mgr_group_exit(p_fixture bigint, p_club text, p_car jsonb)
 returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare f public.season_fixtures; sc public.season_competitions; c public.mgr_coach; rr public.mgr_failure_rules;
 dp record; db numeric; df numeric; s public.career_seasons; nm text;
begin
 select * into f from public.season_fixtures where id = p_fixture;
 select * into sc from public.season_competitions where season_id = f.season_id and competition_id = f.competition_id;
 select * into c from public.mgr_coach where career_id = (select career_id from public.mgr_matches where fixture_id = p_fixture);
 if f.stage <> 'group' or sc.stage = 'group' or c.status <> 'employed' or c.club_id is distinct from p_club then return p_car; end if;
 -- ainda vivo: tem jogo na fase seguinte (ou foi campeão de uma competição só de grupos)
 if exists (select 1 from public.season_fixtures x where x.season_id = f.season_id and x.competition_id = f.competition_id
             and x.stage <> 'group' and (x.home_club = p_club or x.away_club = p_club))
    or sc.champion_club = p_club then return p_car; end if;
 select * into rr from public.mgr_failure_rules;
 dp := public.mgr_difficulty(c.career_id);
 db := rr.group_exit_board * dp.board_loss_mult; df := rr.group_exit_fans * dp.fan_loss_mult;
 update public.mgr_coach
    set board_confidence = round(greatest(0, board_confidence - db), 2),
        fan_mood = round(greatest(0, fan_mood - df), 2),
        reputation = round(greatest(0, reputation - rr.group_exit_reputation), 2),
        rank_penalty = rank_penalty + rr.group_exit_rank_points
  where career_id = c.career_id returning * into c;
 perform public.mgr_squad_morale_hit(c.career_id, p_club, rr.group_exit_morale);
 select * into s from public.career_seasons where id = f.season_id;
 select name into nm from public.sim_competitions where id = f.competition_id;
 perform public.mgr_msg(c.career_id, s.id, s.day_no, 'board', 'Vexame na fase de grupos',
   format('Cair na fase de grupos %s é inadmissível. A diretoria exige reação imediata.', public.mgr_comp_do(f.competition_id)), p_club);
 perform public.mgr_msg(c.career_id, s.id, s.day_no, 'fans', 'Torcida revoltada',
   'Vaias, faixas de protesto e cobrança no aeroporto: a eliminação ainda nos grupos revoltou a torcida.', p_club);
 return p_car || jsonb_build_object(
   'eliminated', true, 'group_exit', true,
   'board', jsonb_build_object('before', p_car #> '{board,before}', 'after', round(c.board_confidence),
            'delta', round(c.board_confidence - (p_car #>> '{board,before}')::numeric, 1)),
   'fans', jsonb_build_object('before', p_car #> '{fans,before}', 'after', round(c.fan_mood),
           'delta', round(c.fan_mood - (p_car #>> '{fans,before}')::numeric, 1)),
   'reputation', jsonb_build_object('before', p_car #> '{reputation,before}', 'after', round(c.reputation, 1),
                 'delta', round(c.reputation - (p_car #>> '{reputation,before}')::numeric, 2)),
   'ranking', jsonb_build_object('delta', coalesce((p_car #>> '{ranking,delta}')::int, 0) - rr.group_exit_rank_points),
   'squad_morale', jsonb_build_object('delta', coalesce((p_car #>> '{squad_morale,delta}')::numeric, 0) - rr.group_exit_morale));
end $$;
revoke all on function public.mgr_group_exit(bigint, text, jsonb) from public, anon, authenticated;

CREATE OR REPLACE FUNCTION public.mgr_user_match_finished(p_fixture bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
v_m     public.mgr_matches;
v_f     public.season_fixtures;
v_s     public.career_seasons;
v_fin   jsonb;
v_car   jsonb;
v_round jsonb;
v_sc    public.season_competitions;
v_pos0  int;
v_pos1  int;
v_offer jsonb;
v_season jsonb;
v_fired text;
v_c     public.mgr_coach;
v_lvl0  int;
v_lvl1  int;
v_club  text;
v_grp   text;
v_sum   jsonb;
v_motm  jsonb;
begin
select * into v_m from public.mgr_matches where fixture_id = p_fixture;
if v_m.summary is not null then return v_m.summary; end if;
select * into v_f from public.season_fixtures where id = p_fixture;
select * into v_s from public.career_seasons where id = v_f.season_id;
select * into v_c from public.mgr_coach where career_id = v_m.career_id;
select level into v_lvl0 from public.careers where id = v_m.career_id;
v_club := v_c.club_id;
v_grp := v_f.group_label;
if v_f.stage in ('league', 'group') then
select t.pos into v_pos0 from public.sim_standings(v_s.id, v_f.competition_id, v_grp) t where t.club_id = v_club;
end if;
v_fin := public.mgr_match_finish(p_fixture);
v_car := public.mgr_after_user_match(p_fixture);
perform public.sim_play_round(v_s.id, v_f.competition_id, v_f.stage, v_f.round_no);
select jsonb_agg(jsonb_build_object('id', o.id, 'home', o.home_club, 'away', o.away_club, 'hg', o.home_goals, 'ag', o.away_goals,
'hp', o.home_pens, 'ap', o.away_pens, 'group', o.group_label) order by o.id)
into v_round from public.season_fixtures o
where o.season_id = v_s.id and o.competition_id = v_f.competition_id and o.stage = v_f.stage and o.round_no = v_f.round_no and o.id <> v_f.id;
if v_f.stage in ('league', 'group') then
select t.pos into v_pos1 from public.sim_standings(v_s.id, v_f.competition_id, v_grp) t where t.club_id = v_club;
end if;
perform public.sim_advance(v_s.id, v_f.competition_id);
select * into v_sc from public.season_competitions where season_id = v_s.id and competition_id = v_f.competition_id;
-- queda na fase de grupos: punição maior que a do mata-mata (2026-11-09)
if v_f.stage = 'group' and v_sc.stage is distinct from 'group' then
v_car := public.mgr_group_exit(p_fixture, v_club, v_car);
end if;
v_fired := v_car ->> 'fire_reason';
if v_fired is not null then
perform public.mgr_fire(v_m.career_id, v_fired);
else
select * into v_c from public.mgr_coach where career_id = v_m.career_id;
if (select count(*) from public.season_offers where career_id = v_m.career_id and status = 'pending' and kind = 'coach') < 2
and random() < 0.004 + v_c.reputation * 0.0007 + (case when v_car ->> 'result' = 'win' then 0.004 else 0 end) then
v_offer := public.mgr_make_offer(v_m.career_id, v_s.id, v_s.day_no, false);
end if;
end if;
perform public.mgr_day_tick(v_m.career_id, v_s.id);
if not exists (select 1 from public.season_fixtures where season_id = v_s.id and status = 'pending') then
v_season := public.mgr_season_end(v_s.id);
end if;
select level into v_lvl1 from public.careers where id = v_m.career_id;
select jsonb_build_object('id', mp.player_id, 'name', p.short_name, 'side', mp.side, 'rating', mp.rating, 'goals', mp.goals, 'assists', mp.assists)
into v_motm from public.mgr_match_players mp join public.sim_players p on p.id = mp.player_id
where mp.fixture_id = p_fixture and mp.player_id = v_fin -> 'stats' ->> 'motm';
v_sum := v_car || jsonb_build_object(
'fixture_id', p_fixture, 'competition', v_f.competition_id, 'stage', v_f.stage, 'round', v_f.round_no, 'leg', v_f.leg, 'group', v_grp,
'home', v_f.home_club, 'away', v_f.away_club, 'home_goals', v_fin -> 'home_goals', 'away_goals', v_fin -> 'away_goals',
'pens', v_fin -> 'pens', 'tie_winner', v_fin -> 'winner', 'venue', case when v_m.user_side = 'h' then 'home' else 'away' end,
'my_club', v_club, 'stats', v_fin -> 'stats', 'motm', v_motm,
'table', case when v_pos1 is not null then jsonb_build_object('before', v_pos0, 'after', v_pos1) end,
'round_results', coalesce(v_round, '[]'::jsonb),
'competition_finished', v_sc.status = 'finished',
'competition_result', case when v_sc.status = 'finished' then v_sc.player_result end,
'champion', case when v_sc.status = 'finished' then v_sc.champion_club end,
'competition_bonus', case when v_sc.status = 'finished' and coalesce(v_sc.player_bonus_xp, 0) + coalesce(v_sc.player_bonus_coins, 0) > 0
then jsonb_build_object('xp', v_sc.player_bonus_xp, 'coins', v_sc.player_bonus_coins) end,
'fired', v_fired is not null, 'offer', v_offer,
'season_finished', v_season is not null, 'level_up', v_lvl1 > v_lvl0, 'new_level', v_lvl1);
update public.mgr_matches set summary = v_sum where fixture_id = p_fixture;
return v_sum;
end;
$function$;
