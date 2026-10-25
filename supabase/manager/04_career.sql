-- =====================================================================
-- MODO CARREIRA (TREINADOR) — 4/5: CARREIRA, CALENDÁRIO E FUNÇÕES DO APP
--   - o calendário/campeonatos do modo Temporadas passam a usar o motor de partidas nas temporadas de treinador
--   - diretoria, torcida, reputação, objetivos, DEMISSÃO e propostas que chegam com o passar dos dias
--   - histórico por passagem de clube (trocar de clube no meio da temporada NÃO reinicia os campeonatos)
-- Funções chamadas pelo app: mgr_hub, mgr_status, mgr_squad, mgr_lineup_save, mgr_lineup_auto, mgr_match_start,
--   mgr_match_step, mgr_advance, mgr_offer_respond, mgr_resign, mgr_season_next, mgr_history, mgr_match_report,
--   mgr_top_scorers, mgr_messages_read
-- =====================================================================

-- ---------------------------------------------------------------------
-- 0) Utilidades
-- ---------------------------------------------------------------------
create or replace function public.mgr_msg(p_career uuid, p_season uuid, p_day int, p_kind text, p_title text, p_body text, p_club text default null)
returns void language sql security definer set search_path = public as $$
  insert into public.mgr_messages (career_id, season_id, day_no, kind, title, body, club_id)
  values (p_career, p_season, p_day, p_kind, p_title, p_body, p_club);
$$;

create or replace function public.mgr_club_name(p_club text)
returns text language sql stable as $$ select coalesce((select name from public.sim_clubs where id = p_club), p_club) $$;

-- "o Flamengo" / "a Chapecoense", "do Flamengo" / "da Chapecoense"
create or replace function public.mgr_club_o(p_club text, p_cap boolean default false)
returns text language sql stable as $$
  select case when p_cap then upper(coalesce(c.article, 'o')) else coalesce(c.article, 'o') end || ' ' || coalesce(c.name, p_club)
    from (select 1) x left join public.sim_clubs c on c.id = p_club
$$;
create or replace function public.mgr_club_do(p_club text)
returns text language sql stable as $$
  select case coalesce(c.article, 'o') when 'a' then 'da ' else 'do ' end || coalesce(c.name, p_club)
    from (select 1) x left join public.sim_clubs c on c.id = p_club
$$;
create or replace function public.mgr_comp_do(p_comp text)
returns text language sql stable as $$
  select case when p_comp = 'brasileirao' then 'do ' else 'da ' end || coalesce((select name from public.sim_competitions where id = p_comp), p_comp)
$$;

create or replace function public.mgr_player_name(p_player text)
returns text language sql stable as $$ select coalesce((select short_name from public.sim_players where id = p_player), '?') $$;

-- fase -> número (para objetivos): 1 grupos/liga, 2 oitavas, 3 quartas, 4 semi, 5 final, 6 campeão
create or replace function public.mgr_stage_rank(p_stage text)
returns int language sql immutable as $$
  select case p_stage when 'league' then 1 when 'group' then 1 when 'r16' then 2 when 'qf' then 3 when 'sf' then 4
                      when 'final' then 5 when 'champion' then 6 else 0 end
$$;

create or replace function public.mgr_stage_label(p_rank int)
returns text language sql immutable as $$
  select case p_rank when 1 then 'fase de grupos' when 2 then 'oitavas' when 3 then 'quartas' when 4 then 'semifinal'
                     when 5 then 'final' when 6 then 'título' else '-' end
$$;

-- melhor fase alcançada por um clube numa competição da temporada (6 = campeão)
create or replace function public.mgr_best_stage(p_season uuid, p_comp text, p_club text)
returns int language sql stable as $$
  select greatest(
    coalesce((select max(public.mgr_stage_rank(f.stage)) from public.season_fixtures f
               where f.season_id = p_season and f.competition_id = p_comp and (f.home_club = p_club or f.away_club = p_club)), 0),
    coalesce((select 6 from public.season_competitions sc where sc.season_id = p_season and sc.competition_id = p_comp
               and sc.status = 'finished' and sc.champion_club = p_club), 0))
$$;

-- ---------------------------------------------------------------------
-- 1) CALENDÁRIO: as funções do modo Temporadas passam a usar o motor nas temporadas de treinador
-- ---------------------------------------------------------------------
-- Rodada: temporada de treinador usa o motor (atributos, escalação, táticas); a antiga continua no sorteio simples
create or replace function public.sim_play_round(p_season uuid, p_comp text, p_stage text, p_round int)
returns int language plpgsql security definer set search_path = public as $$
declare
  r      record;
  v_sc   int[];
  v_sh   int;
  v_sa   int;
  v_n    int := 0;
  v_s    public.career_seasons;
begin
  select * into v_s from public.career_seasons where id = p_season;
  for r in
    select id, home_club, away_club from public.season_fixtures
    where season_id = p_season and competition_id = p_comp and stage = p_stage
      and round_no = p_round and status = 'pending'
    order by id
  loop
    if v_s.mode = 'coach' then
      perform public.mgr_sim_fixture(r.id, v_s.career_id);
    else
      select strength into v_sh from public.sim_clubs where id = r.home_club;
      select strength into v_sa from public.sim_clubs where id = r.away_club;
      v_sc := public.sim_score(v_sh, v_sa, p_stage = 'final');
      update public.season_fixtures
         set home_goals = v_sc[1], away_goals = v_sc[2], status = 'played', played_at = now()
       where id = r.id;
    end if;
    v_n := v_n + 1;
  end loop;
  return v_n;
end;
$$;

-- Eliminatórias: se o motor já decidiu (pênaltis/agregado no próprio jogo), respeita o vencedor gravado
create or replace function public.sim_resolve_ties(p_season uuid, p_comp text, p_stage text)
returns text[] language plpgsql security definer set search_path = public as $$
declare
  v_t       record;
  v_c1      text;
  v_c2      text;
  v_g1      int;
  v_g2      int;
  v_last    bigint;
  v_lasthome text;
  v_lastwin text;
  v_w       text;
  v_wp      int;
  v_lp      int;
  v_out     text[] := '{}';
begin
  for v_t in
    select distinct tie_no from public.season_fixtures
    where season_id = p_season and competition_id = p_comp and stage = p_stage order by tie_no
  loop
    select home_club, away_club into v_c1, v_c2 from public.season_fixtures
     where season_id = p_season and competition_id = p_comp and stage = p_stage and tie_no = v_t.tie_no and leg = 1;
    select id, home_club, tie_winner into v_last, v_lasthome, v_lastwin from public.season_fixtures
     where season_id = p_season and competition_id = p_comp and stage = p_stage and tie_no = v_t.tie_no
     order by leg desc limit 1;

    if v_lastwin is not null then
      v_w := v_lastwin;
    else
      select coalesce(sum(case when home_club = v_c1 then home_goals else away_goals end), 0),
             coalesce(sum(case when home_club = v_c2 then home_goals else away_goals end), 0)
        into v_g1, v_g2
        from public.season_fixtures
       where season_id = p_season and competition_id = p_comp and stage = p_stage and tie_no = v_t.tie_no;
      if v_g1 > v_g2 then v_w := v_c1;
      elsif v_g2 > v_g1 then v_w := v_c2;
      else
        v_w  := public.sim_pens_winner(v_c1, v_c2);
        v_wp := 3 + floor(random() * 3)::int;
        v_lp := greatest(0, v_wp - 1 - floor(random() * 2)::int);
        update public.season_fixtures
           set home_pens = case when v_lasthome = v_w then v_wp else v_lp end,
               away_pens = case when v_lasthome = v_w then v_lp else v_wp end
         where id = v_last;
      end if;
      update public.season_fixtures set tie_winner = v_w where id = v_last;
    end if;
    v_out := v_out || v_w;
  end loop;
  return v_out;
end;
$$;

-- Classificação com os critérios de desempate de CADA competição (sim_competitions.rules.tiebreakers)
--   points, wins, gd, gf, away_gf, h2h_pts, h2h_gd, h2h_gf (confronto direto entre empatados em pontos),
--   reds / yellows (menos é melhor), fairplay (cartões ponderados)
drop function if exists public.sim_standings(uuid, text, text);
create or replace function public.sim_standings(p_season uuid, p_comp text, p_group text default null)
returns table (pos int, club_id text, played int, wins int, draws int, losses int, gf int, ga int, gd int, points int)
language sql stable as $$
  with x_members as (
    select distinct m.c as x_club from (
      select cc.club_id as c from public.sim_competition_clubs cc
       where cc.competition_id = p_comp and (p_group is null or cc.group_label = p_group)
         and not exists (select 1 from public.season_fixtures f0 where f0.season_id = p_season and f0.competition_id = p_comp
                          and f0.stage in ('league', 'group') and (p_group is null or f0.group_label = p_group))
      union all
      select f.home_club from public.season_fixtures f
       where f.season_id = p_season and f.competition_id = p_comp and f.stage in ('league', 'group') and (p_group is null or f.group_label = p_group)
      union all
      select f.away_club from public.season_fixtures f
       where f.season_id = p_season and f.competition_id = p_comp and f.stage in ('league', 'group') and (p_group is null or f.group_label = p_group)
    ) m
  ),
  x_res as (
    select f.id as fid, f.home_club as x_c, f.away_club as x_o, f.home_goals as x_for, f.away_goals as x_against, false as x_away
      from public.season_fixtures f
     where f.season_id = p_season and f.competition_id = p_comp and f.status = 'played'
       and f.stage in ('league', 'group') and (p_group is null or f.group_label = p_group)
    union all
    select f.id, f.away_club, f.home_club, f.away_goals, f.home_goals, true
      from public.season_fixtures f
     where f.season_id = p_season and f.competition_id = p_comp and f.status = 'played'
       and f.stage in ('league', 'group') and (p_group is null or f.group_label = p_group)
  ),
  x_cards as (
    select case when e.side = 'h' then f.home_club else f.away_club end as x_c,
           count(*) filter (where e.kind = 'yellow') as x_y,
           count(*) filter (where e.kind in ('red', 'second_yellow')) as x_r
      from public.mgr_match_events e join public.season_fixtures f on f.id = e.fixture_id
     where f.season_id = p_season and f.competition_id = p_comp and f.stage in ('league', 'group')
       and (p_group is null or f.group_label = p_group) and e.kind in ('yellow', 'red', 'second_yellow')
     group by 1
  ),
  x_agg as (
    select m.x_club,
           count(r.x_c)::int as x_p,
           (count(*) filter (where r.x_for > r.x_against))::int as x_w,
           (count(*) filter (where r.x_for = r.x_against))::int as x_d,
           (count(*) filter (where r.x_for < r.x_against))::int as x_l,
           coalesce(sum(r.x_for), 0)::int as x_gf,
           coalesce(sum(r.x_against), 0)::int as x_ga,
           coalesce(sum(r.x_for) filter (where r.x_away), 0)::int as x_agf
      from x_members m left join x_res r on r.x_c = m.x_club
     group by m.x_club
  ),
  x_pts as (select a.*, a.x_w * 3 + a.x_d as x_pt from x_agg a),
  x_h2h as (
    select r.x_c,
           sum(case when r.x_for > r.x_against then 3 when r.x_for = r.x_against then 1 else 0 end)::int as h_pt,
           sum(r.x_for - r.x_against)::int as h_gd,
           sum(r.x_for)::int as h_gf
      from x_res r
      join x_pts a1 on a1.x_club = r.x_c
      join x_pts a2 on a2.x_club = r.x_o
     where a1.x_pt = a2.x_pt
     group by r.x_c
  ),
  x_full as (
    select p.*, coalesce(h.h_pt, 0) as h_pt, coalesce(h.h_gd, 0) as h_gd, coalesce(h.h_gf, 0) as h_gf,
           coalesce(c.x_y, 0) as x_y, coalesce(c.x_r, 0) as x_r,
           (select array_agg(case t when 'points' then p.x_pt when 'wins' then p.x_w when 'gd' then p.x_gf - p.x_ga
                                    when 'gf' then p.x_gf when 'away_gf' then p.x_agf when 'h2h_pts' then coalesce(h.h_pt, 0)
                                    when 'h2h_gd' then coalesce(h.h_gd, 0) when 'h2h_gf' then coalesce(h.h_gf, 0)
                                    when 'reds' then -coalesce(c.x_r, 0) when 'yellows' then -coalesce(c.x_y, 0)
                                    when 'fairplay' then -(coalesce(c.x_y, 0) + 3 * coalesce(c.x_r, 0)) else 0 end order by o)
              from jsonb_array_elements_text(coalesce((select sc.rules -> 'tiebreakers' from public.sim_competitions sc where sc.id = p_comp),
                                                      '["points","wins","gd","gf"]'::jsonb)) with ordinality as t(t, o)) as x_key
      from x_pts p
      left join x_h2h h on h.x_c = p.x_club
      left join x_cards c on c.x_c = p.x_club
  )
  select (row_number() over (order by f.x_key desc, f.x_club))::int as pos,
         f.x_club as club_id, f.x_p as played, f.x_w as wins, f.x_d as draws, f.x_l as losses,
         f.x_gf as gf, f.x_ga as ga, (f.x_gf - f.x_ga) as gd, f.x_pt as points
    from x_full f
   order by 1;
$$;

-- Fim de campeonato: mantém o que já existia e avisa a carreira do treinador (título, vice...)
create or replace function public.sim_finish_competition(p_season uuid, p_comp text)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_s      public.career_seasons;
  v_ff     public.season_fixtures;
  v_champ  text;
  v_runner text;
  v_has    int;
  v_played int;
  v_pos    int;
  v_last   text;
  v_code   text;
  v_label  text;
  v_xp     int := 0;
  v_coins  int := 0;
  v_lib    boolean := (p_comp = 'libertadores');
  v_club   text;
begin
  select * into v_s from public.career_seasons where id = p_season;
  v_club := v_s.club_id;

  if p_comp = 'brasileirao' then
    select t.club_id into v_champ  from public.sim_standings(p_season, p_comp, null) t where t.pos = 1;
    select t.club_id into v_runner from public.sim_standings(p_season, p_comp, null) t where t.pos = 2;
  else
    select * into v_ff from public.season_fixtures
     where season_id = p_season and competition_id = p_comp and stage = 'final' limit 1;
    v_champ  := v_ff.tie_winner;
    v_runner := case when v_ff.home_club = v_champ then v_ff.away_club else v_ff.home_club end;
  end if;

  select count(*) into v_has from public.season_fixtures
   where season_id = p_season and competition_id = p_comp and v_club is not null and (home_club = v_club or away_club = v_club);
  -- jogos comandados pelo usuário NESTE clube (no modo treinador, quem trocou de clube não leva o título do antigo)
  select count(*) into v_played from public.season_fixtures
   where season_id = p_season and competition_id = p_comp and player_match
     and (v_s.mode = 'player' or coach_club = v_club);

  if v_has > 0 then
    if p_comp = 'brasileirao' then
      select t.pos into v_pos from public.sim_standings(p_season, p_comp, null) t where t.club_id = v_club;
      v_label := case when v_pos = 1 then 'Campeão' else v_pos::text || 'º lugar' end;
      v_code  := case when v_pos = 1 then 'p1' when v_pos <= 4 then 'p2_4' when v_pos <= 8 then 'p5_8' else 'pother' end;
    elsif v_champ = v_club then
      v_label := 'Campeão';       v_code := 'champion';
    elsif v_runner = v_club then
      v_label := 'Vice-campeão';  v_code := 'runner_up';
    else
      select f.stage into v_last from public.season_fixtures f
       where f.season_id = p_season and f.competition_id = p_comp and (f.home_club = v_club or f.away_club = v_club)
       order by case f.stage when 'group' then 1 when 'r16' then 2 when 'qf' then 3 when 'sf' then 4 else 5 end desc limit 1;
      v_code  := case v_last when 'sf' then 'sf' when 'qf' then 'qf' when 'r16' then 'r16' else 'group' end;
      v_label := 'Eliminado ' || case v_last when 'group' then 'na fase de grupos' when 'r16' then 'nas oitavas'
                                             when 'qf' then 'nas quartas' else 'na semifinal' end;
    end if;

    if v_played > 0 then
      v_xp := case v_code
        when 'p1' then 500 when 'p2_4' then 250 when 'p5_8' then 120 when 'pother' then 50
        when 'champion'   then case when v_lib then 600 else 400 end
        when 'runner_up'  then case when v_lib then 300 else 200 end
        when 'sf'         then case when v_lib then 150 else 100 end
        when 'qf'         then case when v_lib then 80  else 50  end
        when 'r16'        then case when v_lib then 40  else 0   end
        when 'group'      then 20 else 0 end;
      v_coins := case v_code
        when 'p1' then 3000 when 'p2_4' then 1500 when 'p5_8' then 700 when 'pother' then 250
        when 'champion'   then case when v_lib then 4000 else 2500 end
        when 'runner_up'  then case when v_lib then 2000 else 1200 end
        when 'sf'         then case when v_lib then 800  else 500  end
        when 'qf'         then case when v_lib then 400  else 250  end
        when 'r16'        then case when v_lib then 200  else 0    end
        when 'group'      then 100 else 0 end;

      if v_xp > 0 or v_coins > 0 then
        update public.careers set xp = xp + v_xp, coins = coins + v_coins where id = v_s.career_id;
        update public.career_seasons set xp_earned = xp_earned + v_xp, coins_earned = coins_earned + v_coins where id = p_season;
      end if;
      if v_s.mode = 'player' then
        if v_code in ('champion', 'p1') then
          update public.career_stats set titles = titles + 1, popularity = least(1000, popularity + 100), updated_at = now()
           where career_id = v_s.career_id;
        elsif v_code in ('runner_up', 'p2_4') then
          update public.career_stats set popularity = least(1000, popularity + 30), updated_at = now()
           where career_id = v_s.career_id;
        end if;
      end if;
    end if;
  end if;

  update public.season_competitions
     set status = 'finished', champion_club = v_champ, runner_up_club = v_runner,
         player_club = case when v_has > 0 then v_club end,
         player_result = v_label,
         player_bonus_xp = case when v_played > 0 then v_xp end,
         player_bonus_coins = case when v_played > 0 then v_coins end
   where season_id = p_season and competition_id = p_comp;

  if v_s.mode = 'coach' then
    perform public.mgr_on_comp_finished(p_season, p_comp, v_champ, v_runner, v_played > 0);
  end if;
end;
$$;

-- ---------------------------------------------------------------------
-- 2) Mundo, temporada, passagem por clube e objetivos
-- ---------------------------------------------------------------------
create or replace function public.mgr_init_world(p_career uuid)
returns int language plpgsql security definer set search_path = public as $$
declare v_n int;
begin
  insert into public.mgr_players (career_id, player_id, club_id, rhythm)
  select p_career, p.id, p.club_id, case when p.is_youth then 50 else 70 end
    from public.sim_players p where p.active and p.club_id is not null
  on conflict (career_id, player_id) do nothing;
  get diagnostics v_n = row_count;
  return v_n;
end;
$$;

create or replace function public.mgr_create_objectives(p_career uuid, p_season uuid, p_spell uuid, p_club text)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_str  int;
  v_rank int;
  v_t    int;
  v_open boolean;
begin
  select strength into v_str from public.sim_clubs where id = p_club;

  -- Brasileirão: posição alvo conforme o tamanho do clube (ranking de força entre os 20)
  if exists (select 1 from public.season_fixtures where season_id = p_season and competition_id = 'brasileirao' and (home_club = p_club or away_club = p_club)) then
    select count(*) + 1 into v_rank from public.sim_clubs c
     where c.id in (select club_id from public.sim_competition_clubs where competition_id = 'brasileirao') and c.strength > v_str;
    v_t := case when v_rank <= 2 then 3 when v_rank <= 5 then 4 when v_rank <= 9 then 8 when v_rank <= 14 then 12 else 16 end;
    insert into public.mgr_objectives (career_id, season_id, spell_id, club_id, competition_id, kind, target, label, priority)
    values (p_career, p_season, p_spell, p_club, 'brasileirao', 'league_pos', v_t,
            case v_t when 3 then 'Brigar pelo título: terminar entre os 3 primeiros' when 4 then 'Terminar no G4'
                     when 8 then 'Terminar entre os 8 primeiros' when 12 then 'Terminar até o 12º lugar'
                     else 'Escapar do rebaixamento (fora do Z4)' end, 3)
    on conflict do nothing;
  end if;

  -- Copas: só se o clube ainda estiver vivo (quem chega no meio do ano não é cobrado pelo que já passou)
  select exists (select 1 from public.season_fixtures where season_id = p_season and competition_id = 'copa_brasil'
                  and status = 'pending' and (home_club = p_club or away_club = p_club)) into v_open;
  if v_open then
    v_t := case when v_str >= 76 then 4 else 3 end;
    insert into public.mgr_objectives (career_id, season_id, spell_id, club_id, competition_id, kind, target, label, priority)
    values (p_career, p_season, p_spell, p_club, 'copa_brasil', 'reach_stage', v_t,
            case v_t when 4 then 'Copa do Brasil: chegar à semifinal' else 'Copa do Brasil: chegar às quartas' end,
            case when v_str >= 76 then 2 else 1 end)
    on conflict do nothing;
  end if;

  select exists (select 1 from public.season_fixtures where season_id = p_season and competition_id = 'libertadores'
                  and status = 'pending' and (home_club = p_club or away_club = p_club)) into v_open;
  if v_open then
    v_t := case when v_str >= 76 then 4 else 2 end;
    insert into public.mgr_objectives (career_id, season_id, spell_id, club_id, competition_id, kind, target, label, priority)
    values (p_career, p_season, p_spell, p_club, 'libertadores', 'reach_stage', v_t,
            case v_t when 4 then 'Libertadores: chegar à semifinal' else 'Libertadores: passar da fase de grupos' end, 2)
    on conflict do nothing;
  end if;
end;
$$;

-- escalação padrão do clube (se ainda não existir)
create or replace function public.mgr_lineup_default(p_career uuid, p_club text, p_force boolean default false)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_l    jsonb;
  v_day  int;
begin
  if not p_force and exists (select 1 from public.mgr_lineups where career_id = p_career and club_id = p_club) then return; end if;
  select coalesce(max(day_no), 0) into v_day from public.career_seasons where career_id = p_career and status = 'active';
  v_l := public.mgr_auto_lineup(p_career, p_club, public.mgr_ai_formation(p_career, p_club), '-', v_day);
  insert into public.mgr_lineups (career_id, club_id, formation, slots, bench, tactics)
  values (p_career, p_club, v_l ->> 'formation', v_l -> 'slots',
          array(select jsonb_array_elements_text(v_l -> 'bench')),
          public.mgr_tactics_clean('{}'::jsonb))
  on conflict (career_id, club_id) do update set formation = excluded.formation, slots = excluded.slots, bench = excluded.bench,
    formation_games = 0, updated_at = now();
end;
$$;

-- nova temporada de treinador (anos seguem: 2026, 2027...)
create or replace function public.mgr_new_season(p_career uuid)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_id    uuid;
  v_n     int;
  v_coach public.mgr_coach;
begin
  select * into v_coach from public.mgr_coach where career_id = p_career;
  select count(*) into v_n from public.career_seasons where career_id = p_career and mode = 'coach';
  v_id := public.sim_create_season(p_career);
  update public.career_seasons set mode = 'coach', year = 2026 + v_n, club_id = v_coach.club_id, day_no = 0 where id = v_id;
  -- pré-temporada: todo mundo zerado
  update public.mgr_players set condition = 100, injured_until = null, injury = null, susp = '{}'::jsonb, yellows = '{}'::jsonb,
         rhythm = greatest(rhythm, 60)
   where career_id = p_career;
  if v_coach.status = 'employed' and v_coach.spell_id is not null then
    perform public.mgr_create_objectives(p_career, v_id, v_coach.spell_id, v_coach.club_id);
    update public.mgr_coach set board_confidence = round(board_confidence + (62 - board_confidence) * 0.5, 2),
                                fan_mood = round(fan_mood + (60 - fan_mood) * 0.5, 2), warned = 0, fan_warned = 0
     where career_id = p_career;
  end if;
  return v_id;
end;
$$;

-- assume um clube (início da carreira, proposta aceita): abre uma passagem nova; a temporada CONTINUA
create or replace function public.mgr_start_spell(p_career uuid, p_club text)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_s     public.career_seasons;
  v_spell uuid;
begin
  select * into v_s from public.career_seasons where career_id = p_career and mode = 'coach' order by season_no desc limit 1;
  insert into public.mgr_spells (career_id, club_id, started_season, started_year, started_day)
  values (p_career, p_club, v_s.season_no, v_s.year, v_s.day_no) returning id into v_spell;
  update public.mgr_coach set status = 'employed', club_id = p_club, spell_id = v_spell, unemployed_day = null, unemployed_season_no = null,
         board_confidence = 62, fan_mood = 60, warned = 0, fan_warned = 0
   where career_id = p_career;
  update public.careers set club_id = p_club where id = p_career;
  if v_s.status = 'active' then
    update public.career_seasons set club_id = p_club where id = v_s.id;
    perform public.mgr_create_objectives(p_career, v_s.id, v_spell, p_club);
  end if;
  perform public.mgr_lineup_default(p_career, p_club);
  return v_spell;
end;
$$;

-- encerra a passagem atual (demissão, saída para outro clube ou pedido de demissão)
create or replace function public.mgr_end_spell(p_career uuid, p_reason text)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_c public.mgr_coach;
  v_s public.career_seasons;
begin
  select * into v_c from public.mgr_coach where career_id = p_career for update;
  if v_c.spell_id is null then return; end if;
  select * into v_s from public.career_seasons where career_id = p_career and mode = 'coach' order by season_no desc limit 1;
  update public.mgr_spells
     set ended_season = v_s.season_no, ended_year = v_s.year, ended_day = v_s.day_no, end_reason = p_reason, ended_at = now()
   where id = v_c.spell_id;
  update public.mgr_objectives set status = case when p_reason = 'fired' then 'failed' else 'void' end
   where spell_id = v_c.spell_id and status = 'open';
  update public.mgr_coach set status = 'unemployed', club_id = null, spell_id = null,
         unemployed_day = v_s.day_no, unemployed_season_no = v_s.season_no
   where career_id = p_career;
  if v_s.status = 'active' then update public.career_seasons set club_id = null where id = v_s.id; end if;
end;
$$;

-- garante a carreira de treinador (migra quem vinha do modo jogador sem apagar nada)
create or replace function public.mgr_ensure(p_c public.careers)
returns public.mgr_coach language plpgsql security definer set search_path = public as $$
declare
  v_coach public.mgr_coach;
  v_sid   uuid;
begin
  select * into v_coach from public.mgr_coach where career_id = p_c.id;
  if found then return v_coach; end if;
  if p_c.club_id is null then raise exception 'Escolha um clube antes de começar a carreira.'; end if;

  insert into public.mgr_coach (career_id, status, club_id) values (p_c.id, 'employed', p_c.club_id);
  perform public.mgr_init_world(p_c.id);
  -- a temporada antiga (de jogador) fica guardada como arquivo
  update public.career_seasons set status = 'archived' where career_id = p_c.id and status = 'active' and mode = 'player';
  v_sid := public.mgr_new_season(p_c.id);
  perform public.mgr_start_spell(p_c.id, p_c.club_id);
  perform public.mgr_msg(p_c.id, v_sid, 0, 'board', 'Bem-vindo, professor!',
    format('A diretoria %s confia no seu trabalho. Monte o time, defina a tática e confira os objetivos da temporada.',
           public.mgr_club_do(p_c.club_id)), p_c.club_id);
  perform public.mgr_msg(p_c.id, v_sid, 0, 'system', 'Como funciona',
    'Antes de cada jogo, prepare a escalação e as táticas. Durante a partida você pode fazer substituições e mudar a postura do time. '
    || 'Resultados ruins derrubam a confiança da diretoria e o humor da torcida — e o técnico pode ser demitido.', p_c.club_id);
  select * into v_coach from public.mgr_coach where career_id = p_c.id;
  return v_coach;
end;
$$;

-- trava a carreira do usuário + garante o treinador + expira propostas pelo calendário
create or replace function public.mgr_lock()
returns public.careers language plpgsql security definer set search_path = public as $$
declare
  v_c   public.careers;
  v_day int;
  v_sid uuid;
begin
  v_c := public.sim_lock_career();
  perform public.mgr_ensure(v_c);
  select id, day_no into v_sid, v_day from public.career_seasons
   where career_id = v_c.id and mode = 'coach' order by season_no desc limit 1;
  update public.season_offers set status = 'expired', responded_at = now()
   where career_id = v_c.id and kind = 'coach' and status = 'pending' and expires_day is not null
     and (season_id is distinct from v_sid or expires_day < v_day);
  select * into v_c from public.careers where id = v_c.id;
  return v_c;
end;
$$;

-- ---------------------------------------------------------------------
-- 3) Escalação: validação
-- ---------------------------------------------------------------------
-- problemas de uma escalação: [{level:'error'|'warn', code, slot, player, text}]
create or replace function public.mgr_lineup_issues(p_career uuid, p_club text, p_lineup jsonb, p_comp text, p_day int)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  v_out   jsonb := '[]'::jsonb;
  v_form  public.sim_formations;
  r       record;
  v_seen  text[] := '{}';
  v_bench int;
begin
  select * into v_form from public.sim_formations where id = p_lineup ->> 'formation';
  if not found then return jsonb_build_array(jsonb_build_object('level', 'error', 'code', 'formation', 'text', 'Formação inválida.')); end if;
  select coalesce(max((rules ->> 'bench')::int), 12) into v_bench from public.sim_competitions where id = p_comp or p_comp = '-';

  for r in
    select s ->> 'slot' as slot, s ->> 'pos' as pos, p_lineup -> 'slots' ->> (s ->> 'slot') as pid
      from jsonb_array_elements(v_form.slots) s
  loop
    if r.pid is null then
      v_out := v_out || jsonb_build_object('level', 'error', 'code', 'missing', 'slot', r.slot, 'text', 'Vaga sem jogador: ' || r.slot);
      continue;
    end if;
    if r.pid = any (v_seen) then
      v_out := v_out || jsonb_build_object('level', 'error', 'code', 'duplicate', 'slot', r.slot, 'player', r.pid,
                                           'text', public.mgr_player_name(r.pid) || ' está escalado duas vezes.');
      continue;
    end if;
    v_seen := v_seen || r.pid;
    perform 1 from public.mgr_players mp where mp.career_id = p_career and mp.player_id = r.pid and mp.club_id = p_club;
    if not found then
      v_out := v_out || jsonb_build_object('level', 'error', 'code', 'not_in_club', 'slot', r.slot, 'player', r.pid,
                                           'text', public.mgr_player_name(r.pid) || ' não é do seu elenco.');
      continue;
    end if;
    if exists (select 1 from public.mgr_players mp where mp.career_id = p_career and mp.player_id = r.pid
                and mp.injured_until is not null and mp.injured_until > p_day) then
      v_out := v_out || jsonb_build_object('level', 'error', 'code', 'injured', 'slot', r.slot, 'player', r.pid,
                                           'text', public.mgr_player_name(r.pid) || ' está lesionado.');
    elsif exists (select 1 from public.mgr_players mp where mp.career_id = p_career and mp.player_id = r.pid
                   and coalesce((mp.susp ->> p_comp)::int, 0) > 0) then
      v_out := v_out || jsonb_build_object('level', 'error', 'code', 'suspended', 'slot', r.slot, 'player', r.pid,
                                           'text', public.mgr_player_name(r.pid) || ' está suspenso.');
    end if;
    if public.mgr_fit(r.pid, r.pos) < 0.86 then
      v_out := v_out || jsonb_build_object('level', 'warn', 'code', 'position', 'slot', r.slot, 'player', r.pid,
                                           'text', public.mgr_player_name(r.pid) || ' está fora de posição (' || r.pos || ').');
    end if;
    if exists (select 1 from public.mgr_players mp where mp.career_id = p_career and mp.player_id = r.pid and mp.condition < 70) then
      v_out := v_out || jsonb_build_object('level', 'warn', 'code', 'tired', 'slot', r.slot, 'player', r.pid,
                                           'text', public.mgr_player_name(r.pid) || ' está cansado.');
    end if;
  end loop;

  if jsonb_array_length(coalesce(p_lineup -> 'bench', '[]'::jsonb)) > v_bench then
    v_out := v_out || jsonb_build_object('level', 'error', 'code', 'bench', 'text', format('O banco tem no máximo %s jogadores.', v_bench));
  end if;
  for r in select b as pid from jsonb_array_elements_text(coalesce(p_lineup -> 'bench', '[]'::jsonb)) b loop
    if r.pid = any (v_seen) then
      v_out := v_out || jsonb_build_object('level', 'error', 'code', 'duplicate', 'player', r.pid,
                                           'text', public.mgr_player_name(r.pid) || ' está no time e no banco.');
    elsif not exists (select 1 from public.mgr_players mp where mp.career_id = p_career and mp.player_id = r.pid and mp.club_id = p_club) then
      v_out := v_out || jsonb_build_object('level', 'error', 'code', 'not_in_club', 'player', r.pid, 'text', public.mgr_player_name(r.pid) || ' não é do seu elenco.');
    elsif exists (select 1 from public.mgr_players mp where mp.career_id = p_career and mp.player_id = r.pid
                   and not public.mgr_available(mp.injured_until, mp.susp, p_comp, p_day)) then
      v_out := v_out || jsonb_build_object('level', 'warn', 'code', 'bench_unavailable', 'player', r.pid,
                                           'text', public.mgr_player_name(r.pid) || ' está indisponível e não irá para o banco.');
    end if;
    v_seen := v_seen || r.pid;
  end loop;
  return v_out;
end;
$$;

-- ---------------------------------------------------------------------
-- 4) Diretoria, torcida, demissão e propostas
-- ---------------------------------------------------------------------
create or replace function public.mgr_make_offer(p_career uuid, p_season uuid, p_day int, p_force_weak boolean default false)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_coach public.mgr_coach;
  v_reach numeric;
  v_cur   int;
  v_cand  record;
  v_pos   int;
  v_bonus int;
  v_pitch text;
  v_id    uuid;
  v_obj   text;
  v_rank  int;
begin
  select * into v_coach from public.mgr_coach where career_id = p_career;
  v_reach := 56 + v_coach.reputation * 0.32;
  select strength into v_cur from public.sim_clubs where id = v_coach.club_id;

  select c.id, c.strength, c.name, t.pos, public.sim_club_weight(p_career, c.id) as w
    into v_cand
    from public.sim_clubs c
    left join public.sim_standings(p_season, 'brasileirao', null) t on t.club_id = c.id
   where c.tier = 'serie_a'
     and c.id is distinct from v_coach.club_id
     and c.strength <= v_reach + 2
     and (p_force_weak or c.strength >= v_reach - 14)
     and (v_coach.status = 'unemployed' or c.strength >= coalesce(v_cur, 0) - 1)
     and c.id not in (select o.from_club from public.season_offers o where o.career_id = p_career and o.status = 'pending')
     and c.id not in (select sp.club_id from public.mgr_spells sp where sp.career_id = p_career and sp.end_reason = 'fired'
                       and sp.ended_season = (select season_no from public.career_seasons where id = p_season))
   order by power(random(), 1.0 / greatest(public.sim_club_weight(p_career, c.id) * (1 + coalesce(t.pos, 10) / 20.0)
                                           * case when p_force_weak then 1 + (80 - c.strength) / 10.0 else 1 end, 0.05)) desc
   limit 1;
  if v_cand.id is null then return null; end if;
  if not p_force_weak and random() > v_cand.w then return null; end if;

  select count(*) + 1 into v_rank from public.sim_clubs c2
   where c2.id in (select club_id from public.sim_competition_clubs where competition_id = 'brasileirao') and c2.strength > v_cand.strength;
  v_obj := case when v_rank <= 2 then 'brigar pelo título' when v_rank <= 5 then 'terminar no G4' when v_rank <= 9 then 'ficar entre os 8 primeiros'
                when v_rank <= 14 then 'fazer uma campanha segura' else 'escapar do rebaixamento' end;
  v_pos := v_cand.pos;
  v_bonus := (round((200 + v_cand.strength * 6) / 50.0) * 50)::int;
  v_pitch := case
    when v_pos is not null and v_pos >= 15 then format('%s está em %sº e precisa de um treinador para %s.', public.mgr_club_o(v_cand.id, true), v_pos, v_obj)
    when v_pos is not null then format('%s (%sº na tabela) quer você no comando para %s.', public.mgr_club_o(v_cand.id, true), v_pos, v_obj)
    else format('%s quer você no comando para %s.', public.mgr_club_o(v_cand.id, true), v_obj) end;

  insert into public.season_offers (career_id, season_id, from_club, bonus_coins, pitch, kind, expires_day, context)
  values (p_career, p_season, v_cand.id, v_bonus, v_pitch, 'coach', p_day + 5,
          jsonb_build_object('position', v_pos, 'objective', v_obj, 'strength', v_cand.strength))
  returning id into v_id;
  perform public.mgr_msg(p_career, p_season, p_day, 'offer', 'Proposta: ' || v_cand.name, v_pitch, v_cand.id);
  return jsonb_build_object('id', v_id, 'club_id', v_cand.id, 'bonus_coins', v_bonus, 'pitch', v_pitch, 'expires_day', p_day + 5,
                            'context', jsonb_build_object('position', v_pos, 'objective', v_obj));
end;
$$;

create or replace function public.mgr_fire(p_career uuid, p_reason text)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_c   public.mgr_coach;
  v_s   public.career_seasons;
begin
  select * into v_c from public.mgr_coach where career_id = p_career;
  if v_c.status <> 'employed' then return; end if;
  select * into v_s from public.career_seasons where career_id = p_career and mode = 'coach' order by season_no desc limit 1;
  perform public.mgr_end_spell(p_career, 'fired');
  update public.mgr_coach set fired_count = fired_count + 1, reputation = greatest(0, reputation - 5),
         board_confidence = 50, fan_mood = 50, warned = 0, fan_warned = 0
   where career_id = p_career;
  perform public.mgr_msg(p_career, v_s.id, v_s.day_no, 'board', 'Você foi demitido',
    format('A diretoria %s decidiu encerrar o seu trabalho (%s). Agora é aguardar propostas: elas chegam com o passar dos dias.',
           public.mgr_club_do(v_c.club_id), p_reason), v_c.club_id);
end;
$$;

-- depois de cada jogo do usuário: diretoria, torcida, reputação, mensagens e demissão
create or replace function public.mgr_after_user_match(p_fixture bigint)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_f     public.season_fixtures;
  v_m     public.mgr_matches;
  v_s     public.career_seasons;
  v_c     public.mgr_coach;
  v_comp  public.sim_competitions;
  v_side  char;
  v_my    int;
  v_opp   int;
  v_res   text;
  v_home  boolean;
  v_d     numeric;
  v_es    numeric;
  v_as    numeric;
  v_db    numeric;
  v_df    numeric;
  v_dr    numeric;
  v_pos   int;
  v_obj   public.mgr_objectives;
  v_out   boolean := false;   -- eliminado neste jogo
  v_adv   boolean := false;   -- classificado neste jogo
  v_streak int;
  v_mult  numeric;
  v_xp    int;
  v_coins int;
  v_fire  text;
  v_inj   jsonb;
  v_susp  jsonb;
  v_b0    numeric;
  v_f0    numeric;
  v_r0    numeric;
  v_lvl0  int;
  v_car   public.careers;
begin
  select * into v_f from public.season_fixtures where id = p_fixture;
  select * into v_m from public.mgr_matches where fixture_id = p_fixture;
  select * into v_s from public.career_seasons where id = v_f.season_id;
  select * into v_c from public.mgr_coach where career_id = v_m.career_id for update;
  select * into v_comp from public.sim_competitions where id = v_f.competition_id;
  select * into v_car from public.careers where id = v_m.career_id;
  v_lvl0 := v_car.level;
  v_b0 := v_c.board_confidence; v_f0 := v_c.fan_mood; v_r0 := v_c.reputation;

  v_side := v_m.user_side;
  v_home := (v_side = 'h') and v_f.stage <> 'final';
  v_my  := case when v_side = 'h' then v_f.home_goals else v_f.away_goals end;
  v_opp := case when v_side = 'h' then v_f.away_goals else v_f.home_goals end;
  v_res := case when v_my > v_opp then 'win' when v_my = v_opp then 'draw' else 'loss' end;
  if v_f.tie_winner is not null then
    v_out := v_f.tie_winner <> v_c.club_id;
    v_adv := not v_out;
  end if;

  -- expectativa x resultado (força média do 11 de cada lado + mando)
  v_d := (v_m.state -> 'strength' ->> (case when v_side = 'h' then 0 else 1 end))::numeric
       - (v_m.state -> 'strength' ->> (case when v_side = 'h' then 1 else 0 end))::numeric
       + case when v_f.stage = 'final' then 0 when v_home then 3 else -3 end;
  v_es := 1 / (1 + power(10, -v_d / 25));
  v_as := case v_res when 'win' then 1 when 'draw' then 0.5 else 0 end;

  -- diretoria: resultado x expectativa | torcida: também pesa a expectativa, mas cobra um pouco mais (e mais em casa)
  v_db := 8 * (v_as - v_es);
  v_df := 8 * (v_as - (0.15 + 0.7 * v_es + case when v_home then 0.05 else 0 end));
  if v_my - v_opp >= 3 then v_df := v_df + 2; v_db := v_db + 1; end if;
  if v_opp - v_my >= 3 then v_df := v_df - 4; v_db := v_db - 2; end if;
  if v_out then v_db := v_db - 6; v_df := v_df - 6; end if;
  if v_adv then v_db := v_db + 3; v_df := v_df + 3; end if;

  -- sequência de derrotas
  select count(*) into v_streak from (
    select case when (f.home_club = v_c.club_id and f.home_goals < f.away_goals) or (f.away_club = v_c.club_id and f.away_goals < f.home_goals) then 1 else 0 end as l
      from public.season_fixtures f
     where f.season_id = v_s.id and f.player_match and f.coach_club = v_c.club_id and f.status = 'played'
     order by f.played_at desc, f.id desc limit 4) x where x.l = 1;
  if v_streak >= 4 then v_df := v_df - 3; v_db := v_db - 2; end if;

  -- pressão da tabela no Brasileirão (depois da 8ª rodada)
  select * into v_obj from public.mgr_objectives where spell_id = v_c.spell_id and season_id = v_s.id and competition_id = 'brasileirao';
  if v_obj.id is not null and v_f.competition_id = 'brasileirao' then
    select t.pos into v_pos from public.sim_standings(v_s.id, 'brasileirao', null) t where t.club_id = v_c.club_id;
    if (select count(*) from public.season_fixtures where season_id = v_s.id and competition_id = 'brasileirao' and status = 'played'
         and (home_club = v_c.club_id or away_club = v_c.club_id)) >= 8 then
      if v_pos > v_obj.target + 3 then v_db := v_db - 1.5; elsif v_pos <= v_obj.target then v_db := v_db + 0.6; end if;
      if v_pos >= 17 then v_df := v_df - 1; end if;
    end if;
  end if;

  v_dr := 1.0 * (v_as - v_es) + case when v_res = 'win' then 0.12 else 0 end + case when v_res = 'win' and v_d < -5 then 0.3 else 0 end;

  update public.mgr_coach
     set board_confidence = round(greatest(0, least(100, board_confidence + v_db + (55 - board_confidence) * 0.02)), 2),
         fan_mood = round(greatest(0, least(100, fan_mood + v_df + (55 - fan_mood) * 0.04)), 2),
         reputation = round(greatest(0, least(100, reputation + v_dr)), 2),
         matches = matches + 1, wins = wins + (v_res = 'win')::int, draws = draws + (v_res = 'draw')::int, losses = losses + (v_res = 'loss')::int,
         gf = gf + v_my, ga = ga + v_opp
   where career_id = v_c.career_id
  returning * into v_c;
  update public.mgr_spells
     set matches = matches + 1, wins = wins + (v_res = 'win')::int, draws = draws + (v_res = 'draw')::int, losses = losses + (v_res = 'loss')::int,
         gf = gf + v_my, ga = ga + v_opp
   where id = v_c.spell_id;

  -- prêmios (moedas e XP da conta)
  v_mult  := v_comp.xp_mult * (case v_f.stage when 'final' then 1.5 when 'r16' then 1.2 when 'qf' then 1.2 when 'sf' then 1.2 else 1 end);
  v_xp    := round((case v_res when 'win' then 30 when 'draw' then 15 else 8 end) * v_mult)::int;
  v_coins := round((case v_res when 'win' then 60 when 'draw' then 25 else 10 end) * v_mult)::int;
  update public.careers set xp = xp + v_xp, coins = coins + v_coins where id = v_c.career_id;
  update public.career_seasons
     set matches = matches + 1, wins = wins + (v_res = 'win')::int, draws = draws + (v_res = 'draw')::int, losses = losses + (v_res = 'loss')::int,
         xp_earned = xp_earned + v_xp, coins_earned = coins_earned + v_coins
   where id = v_s.id;

  -- departamento médico e disciplina (do seu time)
  select coalesce(jsonb_agg(jsonb_build_object('player', mp.player_id, 'name', p.short_name, 'injury', mp.injury,
                                              'days', mp.injured_until - v_s.day_no)), '[]'::jsonb)
    into v_inj
    from public.mgr_match_players x join public.mgr_players mp on mp.career_id = v_c.career_id and mp.player_id = x.player_id
    join public.sim_players p on p.id = x.player_id
   where x.fixture_id = p_fixture and x.side = v_side and x.injured;
  select coalesce(jsonb_agg(jsonb_build_object('player', mp.player_id, 'name', p.short_name, 'games', (mp.susp ->> v_f.competition_id)::int)), '[]'::jsonb)
    into v_susp
    from public.mgr_match_players x join public.mgr_players mp on mp.career_id = v_c.career_id and mp.player_id = x.player_id
    join public.sim_players p on p.id = x.player_id
   where x.fixture_id = p_fixture and x.side = v_side and coalesce((mp.susp ->> v_f.competition_id)::int, 0) > 0;
  if jsonb_array_length(v_inj) > 0 then
    perform public.mgr_msg(v_c.career_id, v_s.id, v_s.day_no, 'medical', 'Departamento médico',
      (select string_agg(format('%s: %s (%s dia%s fora)', e ->> 'name', e ->> 'injury', e ->> 'days',
                                case when (e ->> 'days')::int = 1 then '' else 's' end), ' · ') from jsonb_array_elements(v_inj) e), v_c.club_id);
  end if;
  if jsonb_array_length(v_susp) > 0 then
    perform public.mgr_msg(v_c.career_id, v_s.id, v_s.day_no, 'press', 'Suspensão',
      (select string_agg(format('%s cumpre %s jogo%s de suspensão (%s)', e ->> 'name', e ->> 'games',
                                case when (e ->> 'games')::int = 1 then '' else 's' end, v_comp.short_name), ' · ') from jsonb_array_elements(v_susp) e), v_c.club_id);
  end if;

  -- avisos da diretoria e da torcida
  if v_c.board_confidence < 22 and v_c.warned < 2 then
    perform public.mgr_msg(v_c.career_id, v_s.id, v_s.day_no, 'board', 'Ultimato da diretoria',
      'A paciência acabou. Sem resultados imediatos, o seu cargo estará em risco.', v_c.club_id);
    update public.mgr_coach set warned = 2 where career_id = v_c.career_id;
  elsif v_c.board_confidence < 35 and v_c.warned < 1 then
    perform public.mgr_msg(v_c.career_id, v_s.id, v_s.day_no, 'board', 'Diretoria preocupada',
      'Os resultados estão abaixo do esperado. A diretoria quer ver reação nos próximos jogos.', v_c.club_id);
    update public.mgr_coach set warned = 1 where career_id = v_c.career_id;
  elsif v_c.board_confidence > 45 and v_c.warned > 0 then
    update public.mgr_coach set warned = 0 where career_id = v_c.career_id;
  end if;
  if v_c.fan_mood < 25 and v_c.fan_warned = 0 then
    perform public.mgr_msg(v_c.career_id, v_s.id, v_s.day_no, 'fans', 'Protesto da torcida',
      'Faixas e vaias no estádio: a torcida pede a saída do treinador.', v_c.club_id);
    update public.mgr_coach set fan_warned = 1 where career_id = v_c.career_id;
  elsif v_c.fan_mood > 40 and v_c.fan_warned = 1 then
    update public.mgr_coach set fan_warned = 0 where career_id = v_c.career_id;
  end if;

  -- DEMISSÃO: desempenho muito ruim ou pressão da torcida (depois de pelo menos 6 jogos no clube)
  if (select matches from public.mgr_spells where id = v_c.spell_id) >= 6 then
    if v_c.board_confidence <= 12 then v_fire := 'resultados muito abaixo do esperado';
    elsif v_c.board_confidence <= 25 and v_c.fan_mood <= 15 then v_fire := 'pressão da torcida';
    end if;
  end if;

  return jsonb_build_object(
    'result', v_res, 'my_goals', v_my, 'opp_goals', v_opp, 'eliminated', v_out, 'advanced', v_adv,
    'expected', round(v_es, 2),
    'board', jsonb_build_object('before', round(v_b0), 'after', round(v_c.board_confidence), 'delta', round(v_c.board_confidence - v_b0, 1)),
    'fans', jsonb_build_object('before', round(v_f0), 'after', round(v_c.fan_mood), 'delta', round(v_c.fan_mood - v_f0, 1)),
    'reputation', jsonb_build_object('before', round(v_r0, 1), 'after', round(v_c.reputation, 1), 'delta', round(v_c.reputation - v_r0, 2)),
    'rewards', jsonb_build_object('xp', v_xp, 'coins', v_coins),
    'injuries', v_inj, 'suspensions', v_susp,
    'fire_reason', v_fire);
end;
$$;

-- título / campanha encerrada (chamado pelo fim de campeonato)
create or replace function public.mgr_on_comp_finished(p_season uuid, p_comp text, p_champ text, p_runner text, p_played boolean)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_s    public.career_seasons;
  v_c    public.mgr_coach;
  v_name text;
begin
  select * into v_s from public.career_seasons where id = p_season;
  select * into v_c from public.mgr_coach where career_id = v_s.career_id;
  select name into v_name from public.sim_competitions where id = p_comp;
  if v_c.status = 'employed' and v_c.club_id = p_champ and p_played then
    update public.mgr_spells set titles = titles || jsonb_build_array(jsonb_build_object('competition', p_comp, 'year', v_s.year))
     where id = v_c.spell_id;
    update public.mgr_coach
       set titles = titles + 1,
           reputation = least(100, reputation + case p_comp when 'libertadores' then 15 when 'brasileirao' then 12 else 8 end),
           board_confidence = least(100, board_confidence + 20), fan_mood = least(100, fan_mood + 25)
     where career_id = v_s.career_id;
    perform public.mgr_msg(v_s.career_id, p_season, v_s.day_no, 'title', 'CAMPEÃO! ' || v_name,
      format('%s é campeão %s %s sob o seu comando!', public.mgr_club_o(p_champ, true), public.mgr_comp_do(p_comp), v_s.year), p_champ);
  elsif v_c.status = 'employed' and v_c.club_id = p_runner and p_played then
    update public.mgr_coach set reputation = least(100, reputation + 3) where career_id = v_s.career_id;
    perform public.mgr_msg(v_s.career_id, p_season, v_s.day_no, 'result', 'Vice-campeão: ' || v_name,
      format('Faltou pouco. %s ficou com o título %s.', public.mgr_club_o(p_champ, true), public.mgr_comp_do(p_comp)), p_runner);
  else
    perform public.mgr_msg(v_s.career_id, p_season, v_s.day_no, 'result', 'Fim ' || public.mgr_comp_do(p_comp),
      format('%s é campeão %s %s.', public.mgr_club_o(p_champ, true), public.mgr_comp_do(p_comp), v_s.year), p_champ);
  end if;
end;
$$;

-- ---------------------------------------------------------------------
-- 5) Dias do calendário
-- ---------------------------------------------------------------------
-- passa um dia: recuperação física, ritmo, volta de lesionados
create or replace function public.mgr_day_tick(p_career uuid, p_season uuid)
returns int language plpgsql security definer set search_path = public as $$
declare
  v_day  int;
  v_club text;
  v_back text;
begin
  update public.career_seasons set day_no = day_no + 1 where id = p_season returning day_no, club_id into v_day, v_club;
  update public.mgr_players set condition = least(100, condition + 13) where career_id = p_career and condition < 100;
  update public.mgr_players set rhythm = greatest(35, rhythm - 1.2) where career_id = p_career and rhythm > 35;
  select string_agg(p.short_name, ', ') || case when count(*) > 1 then ' estão liberados' else ' está liberado' end into v_back
    from public.mgr_players mp join public.sim_players p on p.id = mp.player_id
   where mp.career_id = p_career and mp.club_id = v_club and mp.injured_until is not null and mp.injured_until <= v_day;
  update public.mgr_players set injured_until = null, injury = null
   where career_id = p_career and injured_until is not null and injured_until <= v_day;
  if v_back is not null then
    perform public.mgr_msg(p_career, p_season, v_day, 'medical', 'Recuperados', v_back || ' pelo departamento médico.', v_club);
  end if;
  return v_day;
end;
$$;

-- joga uma rodada "livre" (sem o seu clube) e devolve o resumo
create or replace function public.mgr_process_round(p_season uuid, p_comp text, p_stage text, p_round int)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_rows jsonb;
  v_sc   public.season_competitions;
begin
  perform public.sim_play_round(p_season, p_comp, p_stage, p_round);
  select jsonb_agg(jsonb_build_object('id', f.id, 'home', f.home_club, 'away', f.away_club, 'hg', f.home_goals, 'ag', f.away_goals,
                                      'hp', f.home_pens, 'ap', f.away_pens, 'group', f.group_label) order by f.id)
    into v_rows from public.season_fixtures f
   where f.season_id = p_season and f.competition_id = p_comp and f.stage = p_stage and f.round_no = p_round;
  perform public.sim_advance(p_season, p_comp);
  select * into v_sc from public.season_competitions where season_id = p_season and competition_id = p_comp;
  return jsonb_build_object('competition', p_comp, 'stage', p_stage, 'round', p_round, 'results', coalesce(v_rows, '[]'::jsonb),
                            'finished', (v_sc.status = 'finished'),
                            'champion', case when v_sc.status = 'finished' then v_sc.champion_club end,
                            'player_result', case when v_sc.status = 'finished' then v_sc.player_result end);
end;
$$;

-- fim de temporada: objetivos, avaliação da diretoria, resumo e propostas
create or replace function public.mgr_season_end(p_season uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_s     public.career_seasons;
  v_c     public.mgr_coach;
  r       record;
  v_sum   jsonb;
  v_pos   int;
  v_best  int;
  v_met   int := 0;
  v_fail  int := 0;
  v_major boolean := false;
  v_db    numeric := 0;
  v_dr    numeric := 0;
  v_n     int;
  v_i     int;
begin
  select * into v_s from public.career_seasons where id = p_season for update;
  if v_s.status <> 'active' then return v_s.summary; end if;
  for r in select competition_id from public.season_competitions where season_id = p_season and status <> 'finished' loop
    perform public.sim_complete_competition(p_season, r.competition_id);
  end loop;
  select * into v_c from public.mgr_coach where career_id = v_s.career_id;

  -- objetivos da passagem atual
  for r in select * from public.mgr_objectives where season_id = p_season and status = 'open' loop
    if r.kind = 'league_pos' then
      select t.pos into v_pos from public.sim_standings(p_season, r.competition_id, null) t where t.club_id = r.club_id;
      if v_pos <= r.target then
        update public.mgr_objectives set status = 'met' where id = r.id; v_met := v_met + 1; v_db := v_db + 4 * r.priority; v_dr := v_dr + 1.5 * r.priority;
      else
        update public.mgr_objectives set status = 'failed' where id = r.id; v_fail := v_fail + 1;
        if v_pos <= r.target + 2 then v_db := v_db - r.priority; v_dr := v_dr - 0.3 * r.priority;      -- ficou perto
        else v_db := v_db - 4 * r.priority; v_dr := v_dr - 1.2 * r.priority;
          if r.priority >= 3 and v_pos > r.target + 3 then v_major := true; end if;
        end if;
      end if;
      -- campanha no campeonato nacional também conta para a reputação
      v_dr := v_dr + case when v_pos = 1 then 0 when v_pos <= 4 then 4 when v_pos <= 8 then 2 when v_pos >= 17 then -6 else 0 end;
    else
      v_best := public.mgr_best_stage(p_season, r.competition_id, r.club_id);
      if v_best >= r.target then
        update public.mgr_objectives set status = 'met' where id = r.id; v_met := v_met + 1; v_db := v_db + 3 * r.priority; v_dr := v_dr + r.priority;
      else
        update public.mgr_objectives set status = 'failed' where id = r.id; v_fail := v_fail + 1;
        if v_best >= r.target - 1 then v_db := v_db - r.priority; v_dr := v_dr - 0.3 * r.priority;
        else v_db := v_db - 3 * r.priority; v_dr := v_dr - 0.8 * r.priority; end if;
      end if;
    end if;
  end loop;

  select jsonb_agg(jsonb_build_object(
           'competition', sc.competition_id, 'champion', sc.champion_club, 'runner_up', sc.runner_up_club,
           'player_result', sc.player_result, 'player_club', sc.player_club,
           'bonus_xp', sc.player_bonus_xp, 'bonus_coins', sc.player_bonus_coins)
         order by sc.competition_id)
    into v_sum from public.season_competitions sc where sc.season_id = p_season;
  v_sum := jsonb_build_object('competitions', coalesce(v_sum, '[]'::jsonb), 'objectives_met', v_met, 'objectives_failed', v_fail,
                              'coach_club', v_c.club_id, 'coach_status', v_c.status);

  update public.career_seasons set status = 'finished', finished_at = now(), summary = v_sum where id = p_season;
  update public.mgr_coach set seasons = seasons + 1,
         board_confidence = round(greatest(0, least(100, board_confidence + v_db)), 2),
         reputation = round(greatest(0, least(100, reputation + v_dr)), 2)
   where career_id = v_s.career_id returning * into v_c;

  if v_c.status = 'employed' then
    if v_major and v_c.board_confidence < 35 then
      perform public.mgr_fire(v_s.career_id, 'objetivo da temporada não cumprido');
    else
      perform public.mgr_msg(v_s.career_id, p_season, v_s.day_no, 'board', 'Balanço da temporada ' || v_s.year,
        case when v_fail = 0 then 'Objetivos cumpridos. A diretoria está satisfeita e conta com você na próxima temporada.'
             when v_met > 0 then format('%s objetivo(s) cumprido(s) e %s não. A diretoria espera evolução.', v_met, v_fail)
             else 'Temporada abaixo do esperado. A cobrança vai aumentar.' end, v_c.club_id);
    end if;
  end if;

  -- janela de propostas do fim de temporada
  select * into v_c from public.mgr_coach where career_id = v_s.career_id;
  v_n := case when v_c.status = 'unemployed' then 2 else least(2, floor(v_c.reputation / 35)::int + (case when random() < 0.4 then 1 else 0 end)) end;
  for v_i in 1 .. v_n loop
    perform public.mgr_make_offer(v_s.career_id, p_season, v_s.day_no, v_c.status = 'unemployed');
  end loop;
  return v_sum;
end;
$$;

-- ---------------------------------------------------------------------
-- 6) FUNÇÕES DO APP
-- ---------------------------------------------------------------------
-- resumo leve para a tela inicial do jogo (Home)
create or replace function public.mgr_status()
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_c   public.careers;
  v_m   public.mgr_coach;
begin
  v_c := public.sim_lock_career();
  if v_c.club_id is null then return null; end if;
  select * into v_m from public.mgr_coach where career_id = v_c.id;
  if not found then return jsonb_build_object('started', false, 'club_id', v_c.club_id); end if;
  return jsonb_build_object('started', true, 'status', v_m.status, 'club_id', v_m.club_id, 'reputation', round(v_m.reputation),
                            'pending_offers', (select count(*) from public.season_offers where career_id = v_c.id and status = 'pending' and kind = 'coach'),
                            'unread', (select count(*) from public.mgr_messages where career_id = v_c.id and not read));
end;
$$;

-- situação de um clube em cada competição (para o hub)
create or replace function public.mgr_comp_items(p_season uuid, p_club text)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  r        record;
  v_sc     public.season_competitions;
  v_nf     public.season_fixtures;
  v_total  int;
  v_played int;
  v_pending int;
  v_status text;
  v_grp    text;
  v_pos    int;
  v_pts    int;
  v_pl     int;
  v_item   jsonb;
  v_out    jsonb := '[]'::jsonb;
begin
  for r in select id, name, short_name from public.sim_competitions order by sort_order loop
    select * into v_sc from public.season_competitions where season_id = p_season and competition_id = r.id;
    select count(*), count(*) filter (where status = 'played'), count(*) filter (where status = 'pending')
      into v_total, v_played, v_pending
      from public.season_fixtures
     where season_id = p_season and competition_id = r.id and p_club is not null and (home_club = p_club or away_club = p_club);
    v_status := case when v_sc.status = 'finished' then 'finished' when v_total = 0 then 'not_in' when v_pending = 0 then 'out' else 'active' end;
    v_item := jsonb_build_object('id', r.id, 'name', r.name, 'short_name', r.short_name, 'status', v_status, 'stage', v_sc.stage,
      'played', v_played, 'total', v_total, 'champion', v_sc.champion_club, 'runner_up', v_sc.runner_up_club,
      'player_result', v_sc.player_result, 'bonus_xp', v_sc.player_bonus_xp, 'bonus_coins', v_sc.player_bonus_coins);
    if v_status = 'active' then
      select * into v_nf from public.season_fixtures
       where season_id = p_season and competition_id = r.id and status = 'pending' and (home_club = p_club or away_club = p_club)
       order by round_no, id limit 1;
      v_item := v_item || jsonb_build_object('next', jsonb_build_object('home', v_nf.home_club, 'away', v_nf.away_club, 'round', v_nf.round_no,
        'stage', v_nf.stage, 'leg', v_nf.leg, 'group', v_nf.group_label,
        'venue', case when v_nf.home_club = p_club then 'home' else 'away' end, 'neutral', (v_nf.stage = 'final')));
    end if;
    if v_total > 0 and r.id <> 'copa_brasil' then
      v_grp := null;
      if r.id = 'libertadores' then
        select group_label into v_grp from public.season_fixtures
         where season_id = p_season and competition_id = r.id and stage = 'group' and (home_club = p_club or away_club = p_club) limit 1;
      end if;
      select t.pos, t.points, t.played into v_pos, v_pts, v_pl from public.sim_standings(p_season, r.id, v_grp) t where t.club_id = p_club;
      v_item := v_item || jsonb_build_object('table', jsonb_build_object('group', v_grp, 'pos', v_pos, 'points', v_pts, 'played', v_pl));
    end if;
    v_out := v_out || jsonb_build_array(v_item);
  end loop;
  return v_out;
end;
$$;

-- TELA PRINCIPAL do modo Carreira
create or replace function public.mgr_hub()
returns jsonb language plpgsql security definer set search_path = public as $$
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
  v_car := public.mgr_lock();
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
            'neutral', (v_nf.stage = 'final')));
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
           'alive', case when o.kind = 'reach_stage' then exists (select 1 from public.season_fixtures f where f.season_id = v_s.id and f.competition_id = o.competition_id
                                                          and f.status = 'pending' and (f.home_club = o.club_id or f.away_club = o.club_id)) end)
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
    'season', jsonb_build_object('id', v_s.id, 'season_no', v_s.season_no, 'year', v_s.year, 'day_no', v_s.day_no, 'status', v_s.status,
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
$$;

-- ELENCO de um clube (o seu, por padrão) com atributos, notas por posição, condição e números da temporada
create or replace function public.mgr_squad(p_club text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_car  public.careers;
  v_c    public.mgr_coach;
  v_s    public.career_seasons;
  v_club text;
  v_l    public.mgr_lineups;
  v_comp text;
  v_ev   record;
begin
  v_car := public.mgr_lock();
  select * into v_c from public.mgr_coach where career_id = v_car.id;
  select * into v_s from public.career_seasons where career_id = v_car.id and mode = 'coach' order by season_no desc limit 1;
  v_club := coalesce(p_club, v_c.club_id);
  if v_club is null then raise exception 'Você está sem clube no momento.'; end if;
  if v_s.status = 'active' then
    select * into v_ev from public.sim_next_event(v_s.id, v_club);
    if found and v_ev.o_kind = 'mine' then v_comp := v_ev.o_comp; end if;
  end if;
  v_comp := coalesce(v_comp, '-');

  if v_club = v_c.club_id then
    perform public.mgr_lineup_default(v_car.id, v_club);
    select * into v_l from public.mgr_lineups where career_id = v_car.id and club_id = v_club;
  end if;

  return jsonb_build_object(
    'club_id', v_club, 'mine', v_club = v_c.club_id, 'next_competition', nullif(v_comp, '-'), 'day_no', v_s.day_no,
    'rules', (select jsonb_build_object('bench', coalesce((rules ->> 'bench')::int, 12), 'max_subs', coalesce((rules ->> 'max_subs')::int, 5),
                                        'sub_windows', coalesce((rules ->> 'sub_windows')::int, 3))
                from public.sim_competitions where id = case when v_comp = '-' then 'brasileirao' else v_comp end),
    'lineup', case when v_l.club_id is not null then jsonb_build_object('formation', v_l.formation, 'slots', v_l.slots, 'bench', to_jsonb(v_l.bench),
                'tactics', v_l.tactics, 'formation_games', v_l.formation_games,
                'issues', public.mgr_lineup_issues(v_car.id, v_club, jsonb_build_object('formation', v_l.formation, 'slots', v_l.slots,
                                                   'bench', to_jsonb(v_l.bench)), v_comp, v_s.day_no)) end,
    'players', (select coalesce(jsonb_agg(jsonb_build_object(
        'id', p.id, 'name', p.full_name, 'short_name', p.short_name, 'number', p.shirt_number, 'position', p.position,
        'secondary', to_jsonb(p.secondary_positions), 'position_estimated', p.position_estimated, 'nationality', p.nationality,
        'age', p.age, 'captain', p.is_captain, 'youth', p.is_youth,
        'overall', round((select r.rating from public.sim_player_pos_ratings r where r.player_id = p.id and r.pos = p.position)),
        'ratings', (select jsonb_object_agg(r.pos, round(r.eff)) from public.sim_player_pos_ratings r where r.player_id = p.id),
        'attrs', to_jsonb(a) - 'player_id' - 'method' - 'updated_at',
        'condition', round(mp.condition), 'rhythm', round(mp.rhythm),
        'injured_days', case when mp.injured_until > v_s.day_no then mp.injured_until - v_s.day_no end, 'injury', mp.injury,
        'suspended', (select coalesce(sum(value::int), 0) from jsonb_each_text(mp.susp)), 'susp', mp.susp, 'yellows', mp.yellows,
        'available', public.mgr_available(mp.injured_until, mp.susp, v_comp, v_s.day_no),
        'stats', (select jsonb_build_object('apps', coalesce(sum(st.apps), 0), 'starts', coalesce(sum(st.starts), 0), 'minutes', coalesce(sum(st.minutes), 0),
                    'goals', coalesce(sum(st.goals), 0), 'assists', coalesce(sum(st.assists), 0), 'yellows', coalesce(sum(st.yellows), 0),
                    'reds', coalesce(sum(st.reds), 0), 'motm', coalesce(sum(st.motm), 0),
                    'rating', case when sum(st.apps) > 0 then round(sum(st.rating_sum) / sum(st.apps), 2) end)
                    from public.mgr_player_stats st where st.season_id = v_s.id and st.player_id = p.id and st.club_id = v_club))
        order by sp.sort, p.shirt_number nulls last, p.short_name), '[]'::jsonb)
      from public.mgr_players mp
      join public.sim_players p on p.id = mp.player_id
      join public.sim_positions sp on sp.code = p.position
      join public.sim_player_attrs a on a.player_id = p.id
     where mp.career_id = v_car.id and mp.club_id = v_club));
end;
$$;

-- salvar escalação + táticas
create or replace function public.mgr_lineup_save(p_formation text, p_slots jsonb, p_bench jsonb, p_tactics jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_car  public.careers;
  v_c    public.mgr_coach;
  v_s    public.career_seasons;
  v_old  public.mgr_lineups;
  v_iss  jsonb;
  v_comp text := '-';
  v_ev   record;
  v_l    jsonb;
begin
  v_car := public.mgr_lock();
  select * into v_c from public.mgr_coach where career_id = v_car.id;
  if v_c.status <> 'employed' then raise exception 'Você está sem clube no momento.'; end if;
  if exists (select 1 from public.mgr_matches where career_id = v_car.id and status = 'live' and user_side is not null) then
    raise exception 'Há uma partida em andamento: faça as mudanças pela tela do jogo.';
  end if;
  select * into v_s from public.career_seasons where career_id = v_car.id and mode = 'coach' order by season_no desc limit 1;
  if v_s.status = 'active' then
    select * into v_ev from public.sim_next_event(v_s.id, v_c.club_id);
    if found and v_ev.o_kind = 'mine' then v_comp := v_ev.o_comp; end if;
  end if;
  v_l := jsonb_build_object('formation', p_formation, 'slots', coalesce(p_slots, '{}'::jsonb), 'bench', coalesce(p_bench, '[]'::jsonb));
  v_iss := public.mgr_lineup_issues(v_car.id, v_c.club_id, v_l, '-', -1);   -- estrutura (lesões/suspensões são checadas no início do jogo)
  if exists (select 1 from jsonb_array_elements(v_iss) i where i ->> 'level' = 'error' and i ->> 'code' in ('formation', 'missing', 'duplicate', 'not_in_club', 'bench')) then
    raise exception '%', (select string_agg(i ->> 'text', ' ') from jsonb_array_elements(v_iss) i where i ->> 'level' = 'error');
  end if;
  -- só as vagas da formação
  v_l := jsonb_set(v_l, '{slots}', (select coalesce(jsonb_object_agg(s ->> 'slot', p_slots ->> (s ->> 'slot')), '{}'::jsonb)
                                      from public.sim_formations f cross join lateral jsonb_array_elements(f.slots) s where f.id = p_formation));
  select * into v_old from public.mgr_lineups where career_id = v_car.id and club_id = v_c.club_id;
  insert into public.mgr_lineups (career_id, club_id, formation, slots, bench, tactics, formation_games, updated_at)
  values (v_car.id, v_c.club_id, p_formation, v_l -> 'slots', array(select jsonb_array_elements_text(coalesce(p_bench, '[]'::jsonb))),
          public.mgr_tactics_clean(coalesce(p_tactics, v_old.tactics, '{}'::jsonb)), 0, now())
  on conflict (career_id, club_id) do update set
    formation = excluded.formation, slots = excluded.slots, bench = excluded.bench, tactics = excluded.tactics, updated_at = now(),
    formation_games = case when public.mgr_lineups.formation = excluded.formation then public.mgr_lineups.formation_games else 0 end;
  return jsonb_build_object('ok', true, 'issues', public.mgr_lineup_issues(v_car.id, v_c.club_id, v_l, v_comp, v_s.day_no));
end;
$$;

-- escalação automática (sugestão do auxiliar): melhor 11 disponível na formação escolhida (mantém as táticas)
create or replace function public.mgr_lineup_auto(p_formation text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_car  public.careers;
  v_c    public.mgr_coach;
  v_s    public.career_seasons;
  v_old  public.mgr_lineups;
  v_comp text := '-';
  v_ev   record;
  v_l    jsonb;
begin
  v_car := public.mgr_lock();
  select * into v_c from public.mgr_coach where career_id = v_car.id;
  if v_c.status <> 'employed' then raise exception 'Você está sem clube no momento.'; end if;
  select * into v_s from public.career_seasons where career_id = v_car.id and mode = 'coach' order by season_no desc limit 1;
  if v_s.status = 'active' then
    select * into v_ev from public.sim_next_event(v_s.id, v_c.club_id);
    if found and v_ev.o_kind = 'mine' then v_comp := v_ev.o_comp; end if;
  end if;
  select * into v_old from public.mgr_lineups where career_id = v_car.id and club_id = v_c.club_id;
  v_l := public.mgr_auto_lineup(v_car.id, v_c.club_id, coalesce(p_formation, v_old.formation, '4-3-3'), v_comp, v_s.day_no);
  perform public.mgr_lineup_save(v_l ->> 'formation', v_l -> 'slots', v_l -> 'bench', coalesce(v_old.tactics, '{}'::jsonb));
  return public.mgr_squad(null);
end;
$$;

-- estado da partida para a tela (eventos depois de p_after_seq)
create or replace function public.mgr_match_payload(p_fixture bigint, p_after_seq int)
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
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

-- COMEÇAR a partida do seu clube (gasta 1 de energia; idempotente: retomar não cobra de novo)
create or replace function public.mgr_match_start()
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_car  public.careers;
  v_c    public.mgr_coach;
  v_s    public.career_seasons;
  v_ev   record;
  v_f    public.season_fixtures;
  v_l    public.mgr_lineups;
  v_live bigint;
  v_iss  jsonb;
  v_bench jsonb;
begin
  v_car := public.mgr_lock();
  select fixture_id into v_live from public.mgr_matches where career_id = v_car.id and status = 'live' and user_side is not null limit 1;
  if v_live is not null then return public.mgr_match_payload(v_live, 0); end if;

  select * into v_c from public.mgr_coach where career_id = v_car.id;
  if v_c.status <> 'employed' then raise exception 'Você está sem clube. Aguarde propostas.'; end if;
  select * into v_s from public.career_seasons where career_id = v_car.id and mode = 'coach' and status = 'active';
  if not found then raise exception 'A temporada terminou. Inicie a próxima.'; end if;
  select * into v_ev from public.sim_next_event(v_s.id, v_s.club_id);
  if not found then raise exception 'Não há partidas pendentes nesta temporada.'; end if;
  if v_ev.o_kind <> 'mine' then raise exception 'Hoje não é dia de jogo do seu clube. Avance o calendário.'; end if;
  if v_car.energy + v_car.bonus_energy < 1 then raise exception 'Sem energia. Espere a recarga para comandar a próxima partida.'; end if;

  select * into v_f from public.season_fixtures
   where season_id = v_s.id and competition_id = v_ev.o_comp and status = 'pending' and (home_club = v_s.club_id or away_club = v_s.club_id)
   order by round_no, id limit 1;
  perform public.mgr_lineup_default(v_car.id, v_c.club_id);
  select * into v_l from public.mgr_lineups where career_id = v_car.id and club_id = v_c.club_id;
  v_iss := public.mgr_lineup_issues(v_car.id, v_c.club_id, jsonb_build_object('formation', v_l.formation, 'slots', v_l.slots, 'bench', to_jsonb(v_l.bench)),
                                    v_f.competition_id, v_s.day_no);
  if exists (select 1 from jsonb_array_elements(v_iss) i where i ->> 'level' = 'error') then
    raise exception 'Ajuste a escalação: %', (select string_agg(i ->> 'text', ' ') from jsonb_array_elements(v_iss) i where i ->> 'level' = 'error');
  end if;
  -- banco: só quem está disponível
  select coalesce(jsonb_agg(b), '[]'::jsonb) into v_bench from unnest(v_l.bench) b
   where exists (select 1 from public.mgr_players mp where mp.career_id = v_car.id and mp.player_id = b
                  and public.mgr_available(mp.injured_until, mp.susp, v_f.competition_id, v_s.day_no));

  if v_car.energy >= 1 then update public.careers set energy = energy - 1 where id = v_car.id;
  else update public.careers set bonus_energy = bonus_energy - 1 where id = v_car.id; end if;

  perform public.mgr_match_create(v_f.id, v_car.id, case when v_f.home_club = v_c.club_id then 'h' else 'a' end,
    jsonb_build_object('formation', v_l.formation, 'slots', v_l.slots, 'bench', v_bench, 'tactics', v_l.tactics));
  -- entrosamento tático: formação recém-mudada rende um pouco menos (0 jogos -3%, 1 jogo -2%, 2 jogos -1%)
  if coalesce(v_l.formation_games, 0) < 3 then
    update public.mgr_matches
       set state = jsonb_set(state, array['form', case when v_f.home_club = v_c.club_id then '0' else '1' end],
                             to_jsonb(round(((state -> 'form' ->> (case when v_f.home_club = v_c.club_id then 0 else 1 end))::numeric
                                             * (0.97 + 0.01 * coalesce(v_l.formation_games, 0))), 3)))
     where fixture_id = v_f.id;
  end if;
  update public.season_competitions set status = 'active' where season_id = v_s.id and competition_id = v_f.competition_id and status = 'pending';
  update public.mgr_lineups set formation_games = formation_games + 1 where career_id = v_car.id and club_id = v_c.club_id;
  perform public.mgr_event(v_f.id, 0, null, 'kickoff');
  return public.mgr_match_payload(v_f.id, 0);
end;
$$;

-- mudança de formação no meio do jogo: redistribui quem está em campo nas novas vagas
create or replace function public.mgr_change_formation(p_fixture bigint, p_side char, p_form text, p_minute int)
returns text language plpgsql security definer set search_path = public as $$
declare
  v_slots jsonb;
  v_n     int;
  r       record;
  v_pid   text;
  v_used  text[] := '{}';
  v_k     int := 0;
begin
  select slots into v_slots from public.sim_formations where id = p_form;
  if v_slots is null then return 'Formação inválida.'; end if;
  select count(*) into v_n from public.mgr_match_players where fixture_id = p_fixture and side = p_side and status = 'on';
  update public.mgr_match_players set slot = null where fixture_id = p_fixture and side = p_side and status = 'on';
  for r in
    select s ->> 'slot' as slot, s ->> 'pos' as pos
      from jsonb_array_elements(v_slots) s
     order by case s ->> 'pos' when 'GOL' then 1 when 'ZAG' then 2 when 'VOL' then 3 when 'LD' then 4 when 'LE' then 4
                               when 'MC' then 5 when 'MEI' then 6 when 'ATA' then 7 else 8 end
  loop
    exit when v_k >= v_n;
    select mp.player_id into v_pid
      from public.mgr_match_players mp join public.sim_player_pos_ratings rr on rr.player_id = mp.player_id and rr.pos = r.pos
     where mp.fixture_id = p_fixture and mp.side = p_side and mp.status = 'on' and mp.player_id <> all (v_used)
     order by rr.eff desc limit 1;
    exit when v_pid is null;
    update public.mgr_match_players set slot = r.slot, pos = r.pos, fit = public.mgr_fit(v_pid, r.pos)
     where fixture_id = p_fixture and player_id = v_pid;
    v_used := v_used || v_pid;
    v_k := v_k + 1;
    v_pid := null;
  end loop;
  update public.mgr_matches set state = jsonb_set(state, array['formation', case when p_side = 'h' then '0' else '1' end], to_jsonb(p_form))
   where fixture_id = p_fixture;
  perform public.mgr_event(p_fixture, p_minute, p_side, 'tactic', null, null, 'Formação ' || p_form);
  return null;
end;
$$;

-- AVANÇAR a partida até p_to (com mudanças do treinador). Idempotente por (p_from).
--   p_changes: {"tactics":{...}, "formation":"4-4-2", "subs":[{"out":"id","in":"id"}]}
--   p_auto = true  -> "simular até o fim": o auxiliar decide pelo seu time
create or replace function public.mgr_match_step(p_fixture bigint, p_from int, p_to int, p_changes jsonb default null,
                                                 p_auto boolean default false, p_after_seq int default 0)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_car   public.careers;
  v_m     public.mgr_matches;
  v_side  char;
  v_stop  text;
  v_err   text;
  v_sub   jsonb;
  v_first boolean := true;
  v_t     jsonb;
  v_out   jsonb;
  r       record;
  v_to    int;
begin
  v_car := public.mgr_lock();
  select * into v_m from public.mgr_matches where fixture_id = p_fixture and career_id = v_car.id for update;
  if not found then raise exception 'Partida não encontrada.'; end if;
  if v_m.status = 'finished' then return public.mgr_match_payload(p_fixture, p_after_seq); end if;
  if p_from < v_m.minute then   -- pedido repetido (clique duplo / rede): devolve o que já aconteceu
    return public.mgr_match_payload(p_fixture, p_after_seq) || jsonb_build_object('stop', 'replay');
  end if;
  if p_from > v_m.minute then raise exception 'Minuto inválido.'; end if;
  v_side := v_m.user_side;

  -- mudanças do treinador (valem daqui para frente)
  if p_changes ? 'tactics' then
    v_t := public.mgr_tactics_clean(coalesce(v_m.state -> 'tactics' -> v_side, '{}'::jsonb) || (p_changes -> 'tactics'));
    update public.mgr_matches
       set state = jsonb_set(jsonb_set(state, array['tactics', v_side], v_t), array['base_mentality', case when v_side = 'h' then '0' else '1' end],
                             to_jsonb((v_t ->> 'mentality')::int))
     where fixture_id = p_fixture;
    perform public.mgr_event(p_fixture, v_m.minute, v_side, 'tactic', null, null, 'Ajuste tático');
  end if;
  if p_changes ? 'formation' and p_changes ->> 'formation' is distinct from (v_m.state -> 'formation' ->> (case when v_side = 'h' then 0 else 1 end)) then
    v_err := public.mgr_change_formation(p_fixture, v_side, p_changes ->> 'formation', v_m.minute);
    if v_err is not null then raise exception '%', v_err; end if;
  end if;
  for v_sub in select * from jsonb_array_elements(coalesce(p_changes -> 'subs', '[]'::jsonb)) loop
    v_err := public.mgr_do_sub(p_fixture, v_side, v_sub ->> 'out', v_sub ->> 'in', v_m.minute, v_first);
    if v_err is not null then raise exception '%', v_err; end if;
    v_first := false;
  end loop;
  -- lesionado sem troca escolhida: o auxiliar troca (se houver substituição disponível)
  for r in select player_id, pos from public.mgr_match_players
            where fixture_id = p_fixture and side = v_side and status = 'injured_off' and slot is not null loop
    v_err := public.mgr_do_sub(p_fixture, v_side, r.player_id, public.mgr_best_bench(p_fixture, v_side, r.pos), v_m.minute, v_first, 'troca do auxiliar');
    v_first := false;
    if v_err is not null then update public.mgr_match_players set slot = null where fixture_id = p_fixture and player_id = r.player_id; end if;
  end loop;
  perform public.mgr_rate(p_fixture);

  v_to := greatest(p_from + 1, least(p_to, 120));
  v_stop := public.mgr_engine_run(p_fixture, v_to, case when p_auto then null else v_side end);
  while p_auto and v_stop not in ('ft') loop
    v_stop := public.mgr_engine_run(p_fixture, case when coalesce((select (state ->> 'et')::boolean from public.mgr_matches where fixture_id = p_fixture), false) then 120 else 90 end, null);
  end loop;

  if v_stop = 'ft' and public.mgr_needs_extra_time(p_fixture) then
    update public.mgr_matches set state = jsonb_set(state, '{et}', 'true'::jsonb) where fixture_id = p_fixture;
    perform public.mgr_event(p_fixture, 90, null, 'et');
    if p_auto then
      v_stop := public.mgr_engine_run(p_fixture, 105, null);
      v_stop := public.mgr_engine_run(p_fixture, 120, null);
    else
      v_stop := 'et';
    end if;
  end if;
  if v_stop = 'ht' then perform public.mgr_event(p_fixture, 45, null, 'ht'); end if;
  perform public.mgr_rate(p_fixture);

  if v_stop = 'ft' then
    perform public.mgr_user_match_finished(p_fixture);
  end if;
  v_out := public.mgr_match_payload(p_fixture, p_after_seq) || jsonb_build_object('stop', v_stop);
  return v_out;
end;
$$;

-- apito final da partida do usuário: placar, resto da rodada, campeonato, carreira e fim de temporada
create or replace function public.mgr_user_match_finished(p_fixture bigint)
returns jsonb language plpgsql security definer set search_path = public as $$
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

  -- resto da rodada + avanço do campeonato
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

  -- demissão (depois do resultado da rodada) e propostas
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
$$;

-- AVANÇAR o calendário (dias sem jogo do seu clube; desempregado: um dia por vez, esperando propostas)
create or replace function public.mgr_advance(p_until_offer boolean default false)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_car   public.careers;
  v_c     public.mgr_coach;
  v_s     public.career_seasons;
  v_ev    record;
  v_out   jsonb := '[]'::jsonb;
  v_offers jsonb := '[]'::jsonb;
  v_off   jsonb;
  v_t0    timestamptz := clock_timestamp();
  v_days  int := 0;
  v_more  boolean := false;
  v_season jsonb;
  v_lvl0  int;
  v_unemp int;
begin
  v_car := public.mgr_lock();
  v_lvl0 := v_car.level;
  if exists (select 1 from public.mgr_matches where career_id = v_car.id and status = 'live' and user_side is not null) then
    raise exception 'Termine a partida em andamento primeiro.';
  end if;
  select * into v_s from public.career_seasons where career_id = v_car.id and mode = 'coach' and status = 'active' for update;
  if not found then raise exception 'A temporada terminou. Inicie a próxima.'; end if;
  select * into v_c from public.mgr_coach where career_id = v_car.id;

  loop
    select * into v_ev from public.sim_next_event(v_s.id, v_s.club_id);
    exit when not found;
    if v_ev.o_kind = 'mine' then
      if v_days = 0 then raise exception 'Hoje é dia de jogo do seu clube: toque em "Jogar".'; end if;
      exit;
    end if;
    v_out := v_out || jsonb_build_array(public.mgr_process_round(v_s.id, v_ev.o_comp, v_ev.o_stage, v_ev.o_round));
    perform public.mgr_day_tick(v_car.id, v_s.id);
    v_days := v_days + 1;
    select * into v_s from public.career_seasons where id = v_s.id;
    select * into v_c from public.mgr_coach where career_id = v_car.id;

    if v_c.status = 'unemployed' then
      -- propostas chegam com o passar dos dias (mais rápido com reputação alta); depois de 6 dias sem nada, sempre chega uma
      v_unemp := case when v_c.unemployed_season_no = v_s.season_no then v_s.day_no - coalesce(v_c.unemployed_day, 0) else v_s.day_no end;
      v_off := null;
      if (select count(*) from public.season_offers where career_id = v_car.id and status = 'pending' and kind = 'coach') < 3
         and (random() < 0.16 + v_c.reputation * 0.004
              or (v_unemp >= 6 and not exists (select 1 from public.season_offers where career_id = v_car.id and status = 'pending' and kind = 'coach'))) then
        v_off := public.mgr_make_offer(v_car.id, v_s.id, v_s.day_no, v_unemp >= 6);
      end if;
      if v_off is not null then v_offers := v_offers || jsonb_build_array(v_off); end if;
      exit when not p_until_offer or v_off is not null;
    end if;
    if clock_timestamp() - v_t0 > interval '3.5 seconds' then v_more := true; exit; end if;
  end loop;

  if not exists (select 1 from public.season_fixtures where season_id = v_s.id and status = 'pending') then
    v_season := public.mgr_season_end(v_s.id);
  end if;
  select level into v_lvl0 from public.careers where id = v_car.id;
  return jsonb_build_object('rounds', v_out, 'days', v_days, 'offers', v_offers, 'more', v_more,
                            'season_finished', v_season is not null, 'season_summary', v_season);
end;
$$;

-- aceitar / recusar proposta de clube (no meio da temporada: o campeonato CONTINUA, só muda o seu clube)
create or replace function public.mgr_offer_respond(p_offer uuid, p_accept boolean)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_car public.careers;
  v_c   public.mgr_coach;
  v_o   public.season_offers;
  v_s   public.career_seasons;
begin
  v_car := public.mgr_lock();
  if exists (select 1 from public.mgr_matches where career_id = v_car.id and status = 'live' and user_side is not null) then
    raise exception 'Termine a partida em andamento primeiro.';
  end if;
  select * into v_o from public.season_offers where id = p_offer and career_id = v_car.id and kind = 'coach' for update;
  if not found then raise exception 'Proposta não encontrada.'; end if;
  if v_o.status = 'expired' then raise exception 'Esta proposta expirou.'; end if;
  if v_o.status <> 'pending' then raise exception 'Esta proposta não está mais disponível.'; end if;
  select * into v_c from public.mgr_coach where career_id = v_car.id;
  select * into v_s from public.career_seasons where career_id = v_car.id and mode = 'coach' order by season_no desc limit 1;

  if p_accept then
    if v_c.status = 'employed' then
      perform public.mgr_msg(v_car.id, v_s.id, v_s.day_no, 'board', 'Despedida',
        format('Você deixou %s para assumir %s.', public.mgr_club_o(v_c.club_id), public.mgr_club_o(v_o.from_club)), v_c.club_id);
      perform public.mgr_end_spell(v_car.id, 'left');
    end if;
    perform public.mgr_start_spell(v_car.id, v_o.from_club);
    update public.careers set coins = coins + v_o.bonus_coins where id = v_car.id;
    update public.season_offers set status = 'accepted', responded_at = now() where id = v_o.id;
    update public.season_offers set status = 'expired', responded_at = now()
     where career_id = v_car.id and status = 'pending' and kind = 'coach' and id <> v_o.id;
    perform public.mgr_msg(v_car.id, v_s.id, v_s.day_no, 'board', 'Novo desafio: ' || public.mgr_club_name(v_o.from_club),
      'Contrato assinado! Conheça o elenco, defina a escalação e confira os objetivos da diretoria.', v_o.from_club);
  else
    update public.season_offers set status = 'declined', responded_at = now() where id = v_o.id;
  end if;
  return jsonb_build_object('ok', true, 'accepted', p_accept, 'club_id', v_o.from_club);
end;
$$;

-- pedir demissão
create or replace function public.mgr_resign()
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_car public.careers;
  v_c   public.mgr_coach;
  v_s   public.career_seasons;
begin
  v_car := public.mgr_lock();
  select * into v_c from public.mgr_coach where career_id = v_car.id;
  if v_c.status <> 'employed' then raise exception 'Você já está sem clube.'; end if;
  if exists (select 1 from public.mgr_matches where career_id = v_car.id and status = 'live' and user_side is not null) then
    raise exception 'Termine a partida em andamento primeiro.';
  end if;
  select * into v_s from public.career_seasons where career_id = v_car.id and mode = 'coach' order by season_no desc limit 1;
  perform public.mgr_end_spell(v_car.id, 'resigned');
  update public.mgr_coach set reputation = greatest(0, reputation - 2), board_confidence = 50, fan_mood = 50 where career_id = v_car.id;
  perform public.mgr_msg(v_car.id, v_s.id, v_s.day_no, 'board', 'Você pediu demissão',
    format('Você deixou %s. Avance os dias para receber propostas.', public.mgr_club_o(v_c.club_id)), v_c.club_id);
  return jsonb_build_object('ok', true);
end;
$$;

-- próxima temporada (depois que a atual terminar)
create or replace function public.mgr_season_next()
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_car public.careers;
  v_id  uuid;
begin
  v_car := public.mgr_lock();
  if exists (select 1 from public.career_seasons where career_id = v_car.id and status = 'active') then
    raise exception 'Você ainda tem uma temporada em andamento.';
  end if;
  v_id := public.mgr_new_season(v_car.id);
  perform public.mgr_msg(v_car.id, v_id, 0, 'system', 'Nova temporada',
    format('Começou a temporada %s. Os elencos estão descansados e os objetivos foram renovados.', (select year from public.career_seasons where id = v_id)), null);
  return jsonb_build_object('ok', true, 'season_id', v_id);
end;
$$;

-- HISTÓRICO da carreira: passagens por clube, temporadas e títulos
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
    'seasons', (select coalesce(jsonb_agg(jsonb_build_object('id', s.id, 'year', s.year, 'season_no', s.season_no, 'status', s.status,
        'club_id', s.club_id, 'matches', s.matches, 'wins', s.wins, 'draws', s.draws, 'losses', s.losses,
        'xp_earned', s.xp_earned, 'coins_earned', s.coins_earned, 'summary', s.summary,
        'clubs', (select coalesce(jsonb_agg(distinct f.coach_club), '[]'::jsonb) from public.season_fixtures f where f.season_id = s.id and f.player_match),
        'objectives', (select coalesce(jsonb_agg(jsonb_build_object('label', o.label, 'status', o.status, 'club_id', o.club_id) order by o.priority desc), '[]'::jsonb)
                         from public.mgr_objectives o where o.season_id = s.id))
        order by s.season_no desc), '[]'::jsonb)
        from public.career_seasons s where s.career_id = v_car.id and s.mode = 'coach'));
end;
$$;

-- súmula de uma partida (sua ou de qualquer jogo da sua temporada)
create or replace function public.mgr_match_report(p_fixture bigint)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_car public.careers;
begin
  v_car := public.mgr_lock();
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
$$;

-- artilharia / assistências da temporada
create or replace function public.mgr_top_scorers(p_comp text default null, p_limit int default 20)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_car public.careers;
  v_s   public.career_seasons;
begin
  v_car := public.mgr_lock();
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
$$;

create or replace function public.mgr_messages_read(p_ids bigint[] default null)
returns int language plpgsql security definer set search_path = public as $$
declare
  v_car public.careers;
  v_n   int;
begin
  v_car := public.sim_lock_career();
  update public.mgr_messages set read = true where career_id = v_car.id and not read and (p_ids is null or id = any (p_ids));
  get diagnostics v_n = row_count;
  return v_n;
end;
$$;
