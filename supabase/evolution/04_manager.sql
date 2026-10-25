-- =====================================================================
-- EVOLUÇÃO 04 — CARREIRA DO TREINADOR NO MOTOR CONFIGURÁVEL
-- Objetivos, propostas, hub e partida passam a valer para qualquer competição/região (Brasil e Inglaterra).
-- Funções reescritas (create or replace) a partir de supabase/manager/03_engine.sql e 04_career.sql.
-- Rode depois de evolution/03_engine.sql. Idempotente.
-- =====================================================================

-- ---------------------------------------------------------------------
-- A) Ligas de uma região para a carreira (última divisão conhecida de cada clube; senão, a referência oficial)
-- ---------------------------------------------------------------------
create or replace function public.mgr_region_league_clubs(p_career uuid, p_region text)
returns table (o_club text, o_league text)
language plpgsql stable security definer set search_path = public as $$
declare
  v_res jsonb;
begin
  -- temporada ativa da região: participantes atuais
  if exists (select 1 from public.career_seasons s where s.career_id = p_career and s.region = p_region and s.status = 'active') then
    return query
      select sp.club_id, sp.competition_id from public.season_participants sp
        join public.career_seasons s on s.id = sp.season_id
       where s.career_id = p_career and s.region = p_region and s.status = 'active' and sp.division_key is not null;
    return;
  end if;
  -- última transição da região (quem subiu/caiu no fim da última temporada jogada lá)
  select t.result into v_res from public.season_transitions t
   where t.career_id = p_career and t.region = p_region order by t.year desc, t.id desc limit 1;
  if v_res is not null then
    return query
      select x.value #>> '{}', l.key from jsonb_each(v_res -> 'leagues') l cross join lateral jsonb_array_elements(l.value) x;
    return;
  end if;
  return query
    select cc.club_id, cc.competition_id from public.sim_competition_clubs cc
      join public.sim_competitions c on c.id = cc.competition_id
     where c.region = p_region and c.kind = 'league' and c.active;
end;
$$;

-- ---------------------------------------------------------------------
-- B) Objetivos da diretoria (configuráveis em sim_competitions.rules.objectives / cup_objectives)
--    Liga: meta pela força do clube entre os participantes. Copas: só se o clube ainda estiver vivo.
-- ---------------------------------------------------------------------
create or replace function public.mgr_create_objectives(p_career uuid, p_season uuid, p_spell uuid, p_club text)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_str  int;
  v_rank int;
  c      record;
  v_band jsonb;
begin
  select strength into v_str from public.sim_clubs where id = p_club;
  for c in
    select comp.* from public.season_participants sp join public.sim_competitions comp on comp.id = sp.competition_id
     where sp.season_id = p_season and sp.club_id = p_club order by comp.sort_order
  loop
    if c.kind = 'league' then
      select count(*) + 1 into v_rank from public.season_participants sp2 join public.sim_clubs x on x.id = sp2.club_id
       where sp2.season_id = p_season and sp2.competition_id = c.id and x.strength > v_str;
      select b into v_band from jsonb_array_elements(coalesce(c.rules -> 'objectives', '[]'::jsonb)) b
       where (b ->> 'rank_max')::int >= v_rank order by (b ->> 'rank_max')::int limit 1;
      continue when v_band is null;
      insert into public.mgr_objectives (career_id, season_id, spell_id, club_id, competition_id, kind, target, label, priority)
      values (p_career, p_season, p_spell, p_club, c.id, 'league_pos', (v_band ->> 'target')::int, v_band ->> 'label',
              coalesce((v_band ->> 'priority')::int, 3))
      on conflict do nothing;
    elsif public.sim_club_alive(p_season, c.id, p_club) then
      select b into v_band from jsonb_array_elements(coalesce(c.rules -> 'cup_objectives', '[]'::jsonb)) b
       where v_str >= (b ->> 'min_strength')::int order by (b ->> 'min_strength')::int desc limit 1;
      continue when v_band is null;
      insert into public.mgr_objectives (career_id, season_id, spell_id, club_id, competition_id, kind, target, label, priority)
      values (p_career, p_season, p_spell, p_club, c.id, 'reach_stage', (v_band ->> 'target')::int, v_band ->> 'label',
              coalesce((v_band ->> 'priority')::int, 1))
      on conflict do nothing;
    end if;
  end loop;
end;
$$;

-- ---------------------------------------------------------------------
-- C) Propostas de clubes: no meio da temporada só da mesma região (o calendário é da região);
--    na janela do fim da temporada (p_any_region) também de outro país.
-- ---------------------------------------------------------------------
drop function if exists public.mgr_make_offer(uuid, uuid, int, boolean);
create or replace function public.mgr_make_offer(p_career uuid, p_season uuid, p_day int, p_force_weak boolean default false,
                                                  p_any_region boolean default false)
returns jsonb language plpgsql security definer set search_path = public as $$
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
       where p_any_region
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
$$;

-- ---------------------------------------------------------------------
-- D) Situação do clube em cada competição da temporada (para o hub) — vale para qualquer região
-- ---------------------------------------------------------------------
create or replace function public.mgr_comp_items(p_season uuid, p_club text)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  r        record;
  v_nf     public.season_fixtures;
  v_total  int;
  v_played int;
  v_pending int;
  v_status text;
  v_grp    text;
  v_pos    int;
  v_pts    int;
  v_pl     int;
  v_in     boolean;
  v_item   jsonb;
  v_ph     jsonb;
  v_out    jsonb := '[]'::jsonb;
begin
  for r in
    select c.id, c.name, c.short_name, c.kind, c.division, c.theme, c.region, c.rules, sc.status as sc_status, sc.stage, sc.champion_club,
           sc.runner_up_club, sc.player_result, sc.player_bonus_xp, sc.player_bonus_coins
      from public.season_competitions sc join public.sim_competitions c on c.id = sc.competition_id
     where sc.season_id = p_season order by c.sort_order
  loop
    select count(*), count(*) filter (where status = 'played'), count(*) filter (where status = 'pending')
      into v_total, v_played, v_pending
      from public.season_fixtures
     where season_id = p_season and competition_id = r.id and p_club is not null and (home_club = p_club or away_club = p_club);
    v_in := p_club is not null and exists (select 1 from public.season_participants where season_id = p_season and competition_id = r.id and club_id = p_club);
    v_status := case when r.sc_status = 'finished' then 'finished'
                     when not v_in and v_total = 0 then 'not_in'
                     when v_pending > 0 then 'active'
                     when r.kind = 'league' and r.stage <> 'league' then 'league_done'     -- liga acabou; playoff em andamento sem o seu clube
                     when public.sim_club_alive(p_season, r.id, p_club) then 'active'
                     else 'out' end;
    v_ph := public.sim_phase(r.id, r.stage);
    v_item := jsonb_build_object('id', r.id, 'name', r.name, 'short_name', r.short_name, 'kind', r.kind, 'division', r.division,
      'theme', r.theme, 'status', v_status, 'stage', r.stage, 'stage_label', v_ph ->> 'label', 'phase_type', v_ph ->> 'type',
      'played', v_played, 'total', v_total, 'champion', r.champion_club, 'runner_up', r.runner_up_club,
      'player_result', r.player_result, 'bonus_xp', r.player_bonus_xp, 'bonus_coins', r.player_bonus_coins);
    if v_status = 'active' and v_pending > 0 then
      select * into v_nf from public.season_fixtures
       where season_id = p_season and competition_id = r.id and status = 'pending' and (home_club = p_club or away_club = p_club)
       order by public.sim_phase_index(r.id, stage), round_no, id limit 1;
      v_item := v_item || jsonb_build_object('next', jsonb_build_object('home', v_nf.home_club, 'away', v_nf.away_club, 'round', v_nf.round_no,
        'stage', v_nf.stage, 'stage_label', public.sim_phase(r.id, v_nf.stage) ->> 'label', 'leg', v_nf.leg, 'group', v_nf.group_label,
        'venue', case when v_nf.home_club = p_club then 'home' else 'away' end,
        'neutral', coalesce((public.sim_phase(r.id, v_nf.stage) ->> 'neutral')::boolean, false)));
    end if;
    -- posição na tabela (liga, fase de liga ou grupos)
    if v_in and exists (select 1 from public.season_fixtures where season_id = p_season and competition_id = r.id and stage in ('league', 'group')
                         and (home_club = p_club or away_club = p_club)) then
      v_grp := null;
      select group_label into v_grp from public.season_fixtures
       where season_id = p_season and competition_id = r.id and stage = 'group' and (home_club = p_club or away_club = p_club) limit 1;
      select t.pos, t.points, t.played into v_pos, v_pts, v_pl from public.sim_standings(p_season, r.id, v_grp) t where t.club_id = p_club;
      v_item := v_item || jsonb_build_object('table', jsonb_build_object('group', v_grp, 'pos', v_pos, 'points', v_pts, 'played', v_pl,
                  'size', (select count(*) from public.season_participants where season_id = p_season and competition_id = r.id
                             and (v_grp is null or group_label = v_grp))));
    end if;
    v_out := v_out || jsonb_build_array(v_item);
  end loop;
  return v_out;
end;
$$;

-- ---------------------------------------------------------------------
-- E) Nova temporada do treinador: região do clube atual (ou da última temporada, se estiver sem clube)
-- ---------------------------------------------------------------------
create or replace function public.mgr_new_season(p_career uuid)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_id     uuid;
  v_n      int;
  v_coach  public.mgr_coach;
  v_region text;
begin
  select * into v_coach from public.mgr_coach where career_id = p_career;
  select count(*) into v_n from public.career_seasons where career_id = p_career and mode = 'coach';
  v_region := coalesce(
    case when v_coach.status = 'employed' then public.sim_club_region(v_coach.club_id) end,
    (select region from public.career_seasons where career_id = p_career and mode = 'coach' order by season_no desc limit 1),
    public.sim_club_region((select club_id from public.careers where id = p_career)),
    'BRA');
  perform public.mgr_init_world(p_career);                    -- jogadores de clubes adicionados depois (idempotente)
  v_id := public.sim_create_season(p_career, v_region);
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

-- ---------------------------------------------------------------------
-- F) Aceitar proposta no meio da temporada: só da mesma região (o calendário da temporada é de um país)
--    Na janela do fim da temporada (temporada encerrada) pode trocar de país.
-- ---------------------------------------------------------------------
create or replace function public.mgr_offer_region_ok(p_career uuid, p_club text)
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((select s.status <> 'active' or s.region = public.sim_club_region(p_club)
                     from public.career_seasons s where s.career_id = p_career and s.mode = 'coach' order by s.season_no desc limit 1), true)
$$;

-- ---------------------------------------------------------------------
-- G) Funções do modo carreira ajustadas (mesmo código de antes + os pontos marcados)
-- ---------------------------------------------------------------------
-- Partida: mando, prorrogação, critério de empate e tamanho do banco vêm da configuração da fase
create or replace function public.mgr_match_create(p_fixture bigint, p_career uuid, p_user_side char, p_user_lineup jsonb)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_f     public.season_fixtures;
  v_s     public.career_seasons;
  v_rules jsonb;
  v_lh    jsonb;
  v_la    jsonb;
  v_sh    numeric;
  v_sa    numeric;
  v_th    jsonb;
  v_ta    jsonb;
  v_neut  boolean;
  v_dec   boolean;
  v_agg_h int := 0;
  v_agg_a int := 0;
  v_first public.season_fixtures;
  v_ph    jsonb;
  v_bench int;
begin
  if exists (select 1 from public.mgr_matches where fixture_id = p_fixture) then return; end if;
  select * into v_f from public.season_fixtures where id = p_fixture;
  select * into v_s from public.career_seasons where id = v_f.season_id;
  select rules into v_rules from public.sim_competitions where id = v_f.competition_id;
  v_ph := public.sim_phase(v_f.competition_id, v_f.stage);
  v_bench := coalesce((v_rules ->> 'bench')::int, 12);
  if v_ph is not null then
    -- configuração da fase (evolução 03): mando neutro, jogo que decide o confronto, prorrogação e critério de empate
    v_neut := coalesce((v_ph ->> 'neutral')::boolean, false);
    v_dec  := v_ph ->> 'type' = 'knockout' and (coalesce((v_ph ->> 'legs')::int, 1) = 1 or v_f.leg = 2);
  else
    v_neut := (v_f.stage = 'final');
    v_dec  := v_f.stage in ('r16', 'qf', 'sf', 'final') and (v_f.stage = 'final' or v_f.leg = 2);
  end if;
  if v_dec and coalesce(v_f.leg, 1) = 2 then
    select * into v_first from public.season_fixtures
     where season_id = v_f.season_id and competition_id = v_f.competition_id and stage = v_f.stage and tie_no = v_f.tie_no and leg = 1;
    -- placar da ida do ponto de vista dos lados deste jogo
    v_agg_h := case when v_first.home_club = v_f.home_club then coalesce(v_first.home_goals, 0) else coalesce(v_first.away_goals, 0) end;
    v_agg_a := case when v_first.home_club = v_f.away_club then coalesce(v_first.home_goals, 0) else coalesce(v_first.away_goals, 0) end;
  end if;

  insert into public.mgr_matches (fixture_id, career_id, season_id, user_side, minute, state)
  values (p_fixture, p_career, v_f.season_id, p_user_side, 0, jsonb_build_object(
    'seq', 0, 'score', jsonb_build_array(0, 0), 'poss', jsonb_build_array(0, 0),
    'corners', jsonb_build_array(0, 0), 'offsides', jsonb_build_array(0, 0),
    'subs', jsonb_build_object('h', jsonb_build_object('used', 0, 'windows', 0), 'a', jsonb_build_object('used', 0, 'windows', 0)),
    'max_subs', coalesce((v_rules ->> 'max_subs')::int, 5), 'max_windows', coalesce((v_rules ->> 'sub_windows')::int, 3),
    'neutral', v_neut, 'decisive', v_dec, 'agg', jsonb_build_array(v_agg_h, v_agg_a),
    'extra_time_rule', (v_dec and case when v_ph is not null then coalesce((v_ph ->> 'extra_time')::boolean, false)
                                       else v_f.stage = 'final' and coalesce((v_rules ->> 'final_extra_time')::boolean, false) end),
    'tie_rule', coalesce(v_ph ->> 'tie', 'penalties'),
    'et', false, 'comp', v_f.competition_id, 'stage', v_f.stage, 'day', v_s.day_no,
    'form', jsonb_build_array(round((0.93 + random() * 0.14)::numeric, 3), round((0.93 + random() * 0.14)::numeric, 3))));

  v_lh := case when p_user_side = 'h' then p_user_lineup
               else public.mgr_auto_lineup(p_career, v_f.home_club, public.mgr_ai_formation(p_career, v_f.home_club), v_f.competition_id, v_s.day_no, v_bench) end;
  v_la := case when p_user_side = 'a' then p_user_lineup
               else public.mgr_auto_lineup(p_career, v_f.away_club, public.mgr_ai_formation(p_career, v_f.away_club), v_f.competition_id, v_s.day_no, v_bench) end;
  perform public.mgr_build_side(p_fixture, 'h', p_career, v_f.home_club, v_lh);
  perform public.mgr_build_side(p_fixture, 'a', p_career, v_f.away_club, v_la);

  v_sh := public.mgr_side_strength(p_fixture, 'h');
  v_sa := public.mgr_side_strength(p_fixture, 'a');
  v_th := case when p_user_side = 'h' then public.mgr_tactics_clean(p_user_lineup -> 'tactics') else public.mgr_ai_tactics(v_sh - v_sa, not v_neut) end;
  v_ta := case when p_user_side = 'a' then public.mgr_tactics_clean(p_user_lineup -> 'tactics') else public.mgr_ai_tactics(v_sa - v_sh, false) end;

  update public.mgr_matches
     set state = state || jsonb_build_object(
           'tactics', jsonb_build_object('h', v_th, 'a', v_ta),
           'base_mentality', jsonb_build_array((v_th ->> 'mentality')::int, (v_ta ->> 'mentality')::int),
           'formation', jsonb_build_array(v_lh ->> 'formation', v_la ->> 'formation'),
           'strength', jsonb_build_array(round(v_sh, 1), round(v_sa, 1)))
   where fixture_id = p_fixture;
end;
$$;

-- Apito final: empate no agregado com critério "mais bem colocado" (playoff da Série B) não vai aos pênaltis
create or replace function public.mgr_match_finish(p_fixture bigint)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_m      public.mgr_matches;
  v_f      public.season_fixtures;
  v_s      public.career_seasons;
  v_h      int;
  v_a      int;
  v_aggh   int;
  v_agga   int;
  v_pens   int[];
  v_winner text;
  v_stats  jsonb;
  v_motm   text;
  v_lim    int;
  r        record;
  v_dur    int;
begin
  select * into v_m from public.mgr_matches where fixture_id = p_fixture for update;
  if v_m.status = 'finished' then return v_m.summary; end if;
  select * into v_f from public.season_fixtures where id = p_fixture;
  select * into v_s from public.career_seasons where id = v_f.season_id;
  v_h := (v_m.state -> 'score' ->> 0)::int;
  v_a := (v_m.state -> 'score' ->> 1)::int;

  -- eliminatória decidida neste jogo
  if (v_m.state ->> 'decisive')::boolean then
    v_aggh := v_h + (v_m.state -> 'agg' ->> 0)::int;
    v_agga := v_a + (v_m.state -> 'agg' ->> 1)::int;
    if v_aggh = v_agga and coalesce(v_m.state ->> 'tie_rule', 'penalties') = 'higher_seed' then
      v_winner := v_f.home_club;     -- empate no agregado: classifica o mais bem colocado (que decide em casa)
    elsif v_aggh = v_agga then
      v_pens := public.mgr_shootout(p_fixture, case when coalesce((v_m.state ->> 'et')::boolean, false) then 120 else 90 end);
      v_winner := case when v_pens[1] > v_pens[2] then v_f.home_club else v_f.away_club end;
    else
      v_winner := case when v_aggh > v_agga then v_f.home_club else v_f.away_club end;
    end if;
  end if;

  perform public.mgr_rate(p_fixture, true);
  perform public.mgr_event(p_fixture, case when coalesce((v_m.state ->> 'et')::boolean, false) then 120 else 90 end, null, 'ft');

  select jsonb_build_object(
           'poss', jsonb_build_array(
             round(100.0 * (v_m.state -> 'poss' ->> 0)::int / greatest((v_m.state -> 'poss' ->> 0)::int + (v_m.state -> 'poss' ->> 1)::int, 1)),
             100 - round(100.0 * (v_m.state -> 'poss' ->> 0)::int / greatest((v_m.state -> 'poss' ->> 0)::int + (v_m.state -> 'poss' ->> 1)::int, 1))),
           'shots',   jsonb_build_array(coalesce(sum(shots) filter (where side = 'h'), 0), coalesce(sum(shots) filter (where side = 'a'), 0)),
           'sot',     jsonb_build_array(coalesce(sum(sot) filter (where side = 'h'), 0), coalesce(sum(sot) filter (where side = 'a'), 0)),
           'fouls',   jsonb_build_array(coalesce(sum(fouls) filter (where side = 'h'), 0), coalesce(sum(fouls) filter (where side = 'a'), 0)),
           'yellows', jsonb_build_array(coalesce(sum(yellow) filter (where side = 'h'), 0), coalesce(sum(yellow) filter (where side = 'a'), 0)),
           'reds',    jsonb_build_array(coalesce(sum(red) filter (where side = 'h'), 0), coalesce(sum(red) filter (where side = 'a'), 0)),
           'saves',   jsonb_build_array(coalesce(sum(saves) filter (where side = 'h'), 0), coalesce(sum(saves) filter (where side = 'a'), 0)),
           'corners', v_m.state -> 'corners', 'offsides', v_m.state -> 'offsides')
    into v_stats from public.mgr_match_players where fixture_id = p_fixture;

  select player_id into v_motm from public.mgr_match_players
   where fixture_id = p_fixture and minutes > 0 order by rating desc, goals desc, assists desc limit 1;
  v_stats := v_stats || jsonb_build_object('motm', v_motm);

  update public.season_fixtures
     set home_goals = v_h, away_goals = v_a, status = 'played', played_at = now(), stats = v_stats, day_no = v_s.day_no,
         extra_time = coalesce((v_m.state ->> 'et')::boolean, false),
         home_pens = case when v_pens is not null then v_pens[1] end, away_pens = case when v_pens is not null then v_pens[2] end,
         tie_winner = coalesce(v_winner, tie_winner),
         player_match = (v_m.user_side is not null),
         coach_club = case v_m.user_side when 'h' then v_f.home_club when 'a' then v_f.away_club end
   where id = p_fixture;

  -- estatísticas da temporada de cada jogador que entrou em campo
  insert into public.mgr_player_stats as ps (season_id, player_id, competition_id, club_id, apps, starts, minutes, goals, assists, yellows, reds, rating_sum, motm)
  select v_f.season_id, mp.player_id, v_f.competition_id, mp.club_id, 1, mp.starter::int, mp.minutes, mp.goals, mp.assists,
         mp.yellow, mp.red, mp.rating, (mp.player_id = v_motm)::int
    from public.mgr_match_players mp where mp.fixture_id = p_fixture and mp.minutes > 0
  on conflict (season_id, player_id, competition_id) do update set
    apps = ps.apps + 1, starts = ps.starts + excluded.starts, minutes = ps.minutes + excluded.minutes,
    goals = ps.goals + excluded.goals, assists = ps.assists + excluded.assists, yellows = ps.yellows + excluded.yellows,
    reds = ps.reds + excluded.reds, rating_sum = ps.rating_sum + excluded.rating_sum, motm = ps.motm + excluded.motm, club_id = excluded.club_id;

  -- estado dos jogadores: condição, ritmo, lesão, cartões e suspensão
  select coalesce((rules ->> 'yellow_limit')::int, 3) into v_lim from public.sim_competitions where id = v_f.competition_id;
  -- quem estava suspenso neste campeonato cumpriu 1 jogo (os dois clubes)
  update public.mgr_players mp
     set susp = case when coalesce((mp.susp ->> v_f.competition_id)::int, 0) <= 1 then mp.susp - v_f.competition_id
                     else jsonb_set(mp.susp, array[v_f.competition_id], to_jsonb((mp.susp ->> v_f.competition_id)::int - 1)) end
   where mp.career_id = v_m.career_id and mp.club_id in (v_f.home_club, v_f.away_club)
     and coalesce((mp.susp ->> v_f.competition_id)::int, 0) > 0;
  for r in select * from public.mgr_match_players where fixture_id = p_fixture and minutes > 0 loop
    v_dur := case when r.injured then (array[1, 2, 2, 3, 3, 4, 5, 7, 10, 14])[1 + floor(random() * 10)::int] end;
    update public.mgr_players mp
       set condition = round(r.cond, 2),
           rhythm = least(100, mp.rhythm + case when r.minutes >= 45 then 9 else 5 end),
           injured_until = case when r.injured then v_s.day_no + v_dur else mp.injured_until end,
           injury = case when r.injured then (array['Lesão muscular', 'Entorse no tornozelo', 'Pancada no joelho', 'Estiramento na coxa', 'Contusão'])[1 + floor(random() * 5)::int]
                         else mp.injury end,
           yellows = case when r.red > 0 then mp.yellows - v_f.competition_id
                          when r.yellow > 0 and coalesce((mp.yellows ->> v_f.competition_id)::int, 0) + 1 >= v_lim then mp.yellows - v_f.competition_id
                          when r.yellow > 0 then jsonb_set(mp.yellows, array[v_f.competition_id], to_jsonb(coalesce((mp.yellows ->> v_f.competition_id)::int, 0) + 1))
                          else mp.yellows end,
           susp = case when r.red > 0 then jsonb_set(mp.susp, array[v_f.competition_id], to_jsonb(coalesce((mp.susp ->> v_f.competition_id)::int, 0) + case when exists (
                            select 1 from public.mgr_match_events e where e.fixture_id = p_fixture and e.player_id = r.player_id and e.kind = 'red') then 2 else 1 end))
                       when r.yellow > 0 and coalesce((mp.yellows ->> v_f.competition_id)::int, 0) + 1 >= v_lim
                         then jsonb_set(mp.susp, array[v_f.competition_id], to_jsonb(coalesce((mp.susp ->> v_f.competition_id)::int, 0) + 1))
                       else mp.susp end
     where mp.career_id = v_m.career_id and mp.player_id = r.player_id;
  end loop;

  update public.mgr_matches set status = 'finished', updated_at = now(),
         state = state || jsonb_build_object('pens', to_jsonb(v_pens), 'winner', v_winner)
   where fixture_id = p_fixture;

  -- partidas só da IA não guardam a escalação (economiza espaço); a do usuário fica para a súmula
  if v_m.user_side is null then
    delete from public.mgr_match_players where fixture_id = p_fixture;
    delete from public.mgr_match_events where fixture_id = p_fixture and kind not in ('goal', 'pen_goal', 'yellow', 'second_yellow', 'red', 'injury', 'so_goal', 'so_miss');
  end if;
  return jsonb_build_object('home_goals', v_h, 'away_goals', v_a, 'pens', to_jsonb(v_pens), 'winner', v_winner, 'stats', v_stats);
end;
$$;

-- Escalação: banco maior que o permitido na competição vira aviso (só os primeiros entram)
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
    v_out := v_out || jsonb_build_object('level', case when p_comp = '-' then 'error' else 'warn' end, 'code', 'bench',
      'text', case when p_comp = '-' then format('O banco tem no máximo %s jogadores.', v_bench)
                   else format('Nesta competição o banco tem %s jogadores: os primeiros %s da lista ficam no banco.', v_bench, v_bench) end);
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

-- Início da partida: banco limitado ao regulamento da competição
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
  select coalesce(jsonb_agg(z.b order by z.o), '[]'::jsonb) into v_bench from (
    select u.b, u.o from unnest(v_l.bench) with ordinality as u(b, o)
     where exists (select 1 from public.mgr_players mp where mp.career_id = v_car.id and mp.player_id = u.b
                    and public.mgr_available(mp.injured_until, mp.susp, v_f.competition_id, v_s.day_no))
     order by u.o
     limit (select coalesce((rules ->> 'bench')::int, 12) from public.sim_competitions where id = v_f.competition_id)) z;

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

-- Depois do jogo do usuário: mando neutro pela fase; pressão da tabela em qualquer liga
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
  v_home := (v_side = 'h') and not coalesce((v_m.state ->> 'neutral')::boolean, false);
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
       + case when coalesce((v_m.state ->> 'neutral')::boolean, false) then 0 when v_home then 3 else -3 end;
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

  -- pressão da tabela na liga nacional (depois da 8ª rodada)
  select * into v_obj from public.mgr_objectives where spell_id = v_c.spell_id and season_id = v_s.id
     and competition_id = v_f.competition_id and kind = 'league_pos';
  if v_obj.id is not null and v_f.stage = 'league' then
    select t.pos into v_pos from public.sim_standings(v_s.id, v_f.competition_id, null) t where t.club_id = v_c.club_id;
    if (select count(*) from public.season_fixtures where season_id = v_s.id and competition_id = v_f.competition_id and stage = 'league' and status = 'played'
         and (home_club = v_c.club_id or away_club = v_c.club_id)) >= 8 then
      if v_pos > v_obj.target + 3 then v_db := v_db - 1.5; elsif v_pos <= v_obj.target then v_db := v_db + 0.6; end if;
      if v_pos > (select count(*) from public.season_participants where season_id = v_s.id and competition_id = v_f.competition_id) - 4 then
        v_df := v_df - 1;
      end if;
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
  v_mult  := v_comp.xp_mult * (case public.mgr_stage_rank(v_f.competition_id, v_f.stage) when 5 then 1.5 when 4 then 1.2 when 3 then 1.2 when 2 then 1.2 else 1 end);
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

-- Título: reputação pelo tipo de competição
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
           reputation = least(100, reputation + coalesce((select case when kind = 'continental' then 15
                                                                       when kind = 'league' and coalesce(division, 1) = 1 then 12
                                                                       when kind = 'league' then 7 else 8 end
                                                              from public.sim_competitions where id = p_comp), 8)),
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

-- Fim de temporada: acesso/rebaixamento + propostas de qualquer país
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
      v_dr := v_dr + case when v_pos = 1 then 0 when v_pos <= 4 then 4 when v_pos <= 8 then 2
                          when v_pos > (select count(*) from public.season_participants where season_id = p_season and competition_id = r.competition_id) - 4 then -6
                          else 0 end;
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

  -- acesso, rebaixamento e vagas continentais da próxima temporada (aplicado uma única vez)
  v_sum := v_sum || jsonb_build_object('transition', public.sim_season_transition(p_season));
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
    perform public.mgr_make_offer(v_s.career_id, p_season, v_s.day_no, v_c.status = 'unemployed', true);
  end loop;
  return v_sum;
end;
$$;

-- Hub: mando neutro pela fase; região da temporada
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
$$;

-- Elenco: regras da liga da região
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
                from public.sim_competitions where id = case when v_comp = '-'
                  then coalesce((select id from public.sim_competitions where region = v_s.region and kind = 'league' order by division limit 1), 'brasileirao')
                  else v_comp end),
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

-- Aceitar proposta: troca de país só na janela do fim da temporada
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

  if p_accept and not public.mgr_offer_region_ok(v_car.id, v_o.from_club) then
    raise exception 'Esta proposta é para a próxima temporada: aceite quando a temporada atual terminar.';
  end if;
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

-- Histórico: região de cada temporada (Brasil 2026 / Inglaterra 2026/27)
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
        'clubs', (select coalesce(jsonb_agg(distinct f.coach_club), '[]'::jsonb) from public.season_fixtures f where f.season_id = s.id and f.player_match),
        'objectives', (select coalesce(jsonb_agg(jsonb_build_object('label', o.label, 'status', o.status, 'club_id', o.club_id) order by o.priority desc), '[]'::jsonb)
                         from public.mgr_objectives o where o.season_id = s.id))
        order by s.season_no desc), '[]'::jsonb)
        from public.career_seasons s where s.career_id = v_car.id and s.mode = 'coach'));
end;
$$;

-- ---------------------------------------------------------------------
-- H) Carreiras existentes: recebem os jogadores dos clubes novos (só insere; nada muda nos atuais)
-- ---------------------------------------------------------------------
select public.mgr_init_world(career_id) from public.mgr_coach;
