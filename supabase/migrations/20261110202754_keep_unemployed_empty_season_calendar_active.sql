CREATE OR REPLACE FUNCTION public.mgr_season_end(p_season uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
  v_dp    record;   -- perfil de dificuldade em vigor (evolução 05: public.mgr_difficulty)
  v_dr    numeric := 0;
  v_n     int;
  v_i     int;
  v_league_fire boolean := false; -- Fase 4: a meta da liga decide a demissão
  v_coins int := 0;
  v_titles int := 0;
  v_rw    jsonb := '[]'::jsonb;
  v_rep_before numeric;
  v_rr    public.cw_season_reward_rules;
  v_releg boolean := false; -- clube do treinador rebaixado (2026-11-09)
begin
  select * into v_s from public.career_seasons where id = p_season for update;
  select * into v_rr from public.cw_season_reward_rules;
  if v_s.status <> 'active' then return v_s.summary; end if;
  -- Background-only regions have no materialized competitions while unemployed.
  -- An empty schedule is not a completed year: keep the job-search calendar active.
  if not exists (select 1 from public.season_competitions where season_id = p_season)
     and exists (select 1 from public.cw_world w where w.career_id = v_s.career_id
                 and w.today < public.cw_start(v_s.region, v_s.year + 1)) then
    return null;
  end if;
  for r in select competition_id from public.season_competitions where season_id = p_season and status <> 'finished' loop
    perform public.sim_complete_competition(p_season, r.competition_id);
  end loop;
  select * into v_c from public.mgr_coach where career_id = v_s.career_id;

  -- metas de outra passagem ou de passagem iniciada nesta temporada com menos de 10 jogos não são cobradas
  update public.mgr_objectives o set status = 'void'
   where o.season_id = p_season and o.status = 'open'
     and (o.spell_id is distinct from v_c.spell_id or v_c.status <> 'employed'
          or exists (select 1 from public.mgr_spells sp where sp.id = o.spell_id and sp.started_season = v_s.season_no and sp.matches < 10));
  -- objetivos da passagem atual
  for r in select * from public.mgr_objectives where season_id = p_season and status = 'open' loop
    if r.kind = 'league_pos' then
      select t.pos into v_pos from public.sim_standings(p_season, r.competition_id, null) t where t.club_id = r.club_id;
      if v_pos > r.target + v_rr.dismissal_tolerance then v_league_fire := true; end if;
      if v_pos <= r.target then
        v_coins := v_coins + v_rr.league_coins_per_priority * r.priority + v_rr.league_coins_per_place * greatest(0, r.target - v_pos);
        v_rw := v_rw || jsonb_build_object('kind', 'league', 'competition', r.competition_id, 'label', r.label, 'pos', v_pos, 'target', r.target,
          'coins', v_rr.league_coins_per_priority * r.priority + v_rr.league_coins_per_place * greatest(0, r.target - v_pos));
      end if;
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
        v_coins := v_coins + v_rr.cup_coins_per_priority * r.priority;
        v_rw := v_rw || jsonb_build_object('kind', 'cup', 'competition', r.competition_id, 'label', r.label, 'coins', v_rr.cup_coins_per_priority * r.priority);
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
  v_releg := v_c.status = 'employed' and exists (select 1 from jsonb_each(coalesce(v_sum #> '{transition,relegated}', '{}'::jsonb)) e
             cross join lateral jsonb_array_elements_text(case when jsonb_typeof(e.value) = 'array' then e.value else '[]'::jsonb end) x where x = v_c.club_id);
  -- Prêmio de fim de temporada (Fase 4): moedas pela meta superada e por título, uma vez por temporada;
  -- reputação da temporada com teto de +6 (cada ponto vale 15 no rank).
  if v_c.status = 'employed' then
    select count(*) into v_titles from public.season_competitions where season_id = p_season and champion_club = v_c.club_id;
    v_coins := v_coins + v_rr.title_coins * v_titles;
    v_dr := v_dr + v_rr.title_reputation * v_titles;
  end if;
  v_dr := least(v_dr, v_rr.reputation_cap);
  v_rep_before := v_c.reputation;
  v_dp := public.mgr_difficulty(v_s.career_id);   -- lido ANTES de contar a temporada (o perfil vale até o fim dela)
  if v_db < 0 then v_db := v_db * v_dp.board_loss_mult; end if;
  update public.mgr_coach set seasons = seasons + 1,
         board_confidence = round(greatest(0, least(100, board_confidence + v_db)), 2),
         reputation = round(greatest(0, least(100, reputation + v_dr)), 2)
   where career_id = v_s.career_id returning * into v_c;

  if v_c.status = 'employed' then
    insert into public.cw_season_rewards(season_id, career_id, club_id, coins, reputation, detail)
    values (p_season, v_s.career_id, v_c.club_id, v_coins, round(v_c.reputation - v_rep_before, 2),
            jsonb_build_object('items', v_rw, 'titles', v_titles, 'title_coins', v_rr.title_coins * v_titles, 'objectives_met', v_met, 'objectives_failed', v_fail, 'year', v_s.year))
    on conflict (season_id) do nothing;
    if found and v_coins > 0 then perform public.econ_apply(v_s.career_id, 'coins', v_coins, 'season_reward', p_season::text); end if;
    if v_releg then
      perform public.mgr_relegation_fallout(v_s.career_id, p_season, v_c.club_id);
    elsif v_league_fire then
      perform public.mgr_fire(v_s.career_id, 'objetivos da temporada não cumpridos');
    else
      perform public.mgr_msg(v_s.career_id, p_season, v_s.day_no, 'board', 'Balanço da temporada ' || v_s.year,
        case when v_met + v_fail = 0 then 'Você assumiu o clube na reta final da temporada, por isso as metas não foram avaliadas. A avaliação passa a valer a partir da próxima.'
             when v_fail = 0 then 'Todos os objetivos foram cumpridos. A diretoria está satisfeita e conta com você para a próxima temporada.'
             when v_met > 0 then format('%s objetivo(s) cumprido(s) e %s não cumprido(s). A diretoria espera evolução na próxima temporada.', v_met, v_fail)
             else 'A temporada ficou abaixo do planejado. A diretoria espera uma resposta já no início da próxima.' end, v_c.club_id);
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
$function$
;

