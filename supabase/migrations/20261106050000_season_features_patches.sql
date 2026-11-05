-- Fase 4: ajustes em funções existentes (gerado a partir das definições em produção).

-- mgr_season_end
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
      if v_pos > r.target + 2 then v_league_fire := true; end if;
      if v_pos <= r.target then
        v_coins := v_coins + 150 * r.priority + 75 * greatest(0, r.target - v_pos);
        v_rw := v_rw || jsonb_build_object('kind', 'league', 'competition', r.competition_id, 'label', r.label, 'pos', v_pos, 'target', r.target,
          'coins', 150 * r.priority + 75 * greatest(0, r.target - v_pos));
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
        v_coins := v_coins + 100 * r.priority;
        v_rw := v_rw || jsonb_build_object('kind', 'cup', 'competition', r.competition_id, 'label', r.label, 'coins', 100 * r.priority);
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
  -- Prêmio de fim de temporada (Fase 4): moedas pela meta superada e por título, uma vez por temporada;
  -- reputação da temporada com teto de +6 (cada ponto vale 15 no rank).
  if v_c.status = 'employed' then
    select count(*) into v_titles from public.season_competitions where season_id = p_season and champion_club = v_c.club_id;
    v_coins := v_coins + 400 * v_titles;
    v_dr := v_dr + 1.5 * v_titles;
  end if;
  v_dr := least(v_dr, 6);
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
            jsonb_build_object('items', v_rw, 'titles', v_titles, 'objectives_met', v_met, 'objectives_failed', v_fail, 'year', v_s.year))
    on conflict (season_id) do nothing;
    if found and v_coins > 0 then perform public.econ_apply(v_s.career_id, 'coins', v_coins, 'season_reward', p_season::text); end if;
    if v_league_fire then
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
$function$;

-- mgr_after_user_match
CREATE OR REPLACE FUNCTION public.mgr_after_user_match(p_fixture bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_f     public.season_fixtures;
  v_m     public.mgr_matches;
  v_s     public.career_seasons;
  v_c     public.mgr_coach;
  v_dp    record;   -- perfil de dificuldade em vigor (evolução 05: public.mgr_difficulty)
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

  -- perfil de dificuldade (evolução 05): só suaviza QUEDAS de confiança/humor e acelera a reputação; o placar não muda
  v_dp := public.mgr_difficulty(v_c.career_id);
  if v_db < 0 then v_db := v_db * v_dp.board_loss_mult; end if;
  if v_df < 0 then v_df := v_df * v_dp.fan_loss_mult; end if;
  if v_dr > 0 then v_dr := v_dr * v_dp.rep_gain_mult; end if;

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
  v_xp := 0;
  v_coins := coalesce((select coins from public.base_match_rewards where fixture_id=p_fixture),0);
  -- Account resources are credited once by base_fixture_reward.
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
  -- Fase 4: no meio da temporada só demite com a liga em zona de perigo (mais de 2 posições abaixo da meta).
  if (select matches from public.mgr_spells where id = v_c.spell_id) >= 6
     and coalesce(public.cw_league_status(v_c.career_id)->>'risk','danger')='danger' then
    if v_c.board_confidence <= v_dp.fire_threshold then v_fire := 'resultados muito abaixo do esperado';
    elsif v_c.board_confidence <= 25 and v_c.fan_mood <= 15 then v_fire := 'pressão da torcida';
    end if;
  end if;

  return jsonb_build_object(
    'result', v_res, 'my_goals', v_my, 'opp_goals', v_opp, 'eliminated', v_out, 'advanced', v_adv,
    'expected', round(v_es, 2),
    'board', jsonb_build_object('before', round(v_b0), 'after', round(v_c.board_confidence), 'delta', round(v_c.board_confidence - v_b0, 1)),
    'fans', jsonb_build_object('before', round(v_f0), 'after', round(v_c.fan_mood), 'delta', round(v_c.fan_mood - v_f0, 1)),
    'reputation', jsonb_build_object('before', round(v_r0, 1), 'after', round(v_c.reputation, 1), 'delta', round(v_c.reputation - v_r0, 2)),
    'rewards', jsonb_build_object('energy', coalesce((select energy from public.base_match_rewards where fixture_id=p_fixture),0), 'xp', v_xp, 'coins', v_coins)||jsonb_build_object('club',public.cw_fixture_income(p_fixture,coalesce((select coach_club from public.season_fixtures where id=p_fixture),(select club_id from public.career_seasons where id=(select season_id from public.season_fixtures where id=p_fixture))))),
    'injuries', v_inj, 'suspensions', v_susp,
    'fire_reason', v_fire);
end;
$function$;

-- cw_jobs_tick
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
 -- Fase 4: vagas abertas por demissões da IA e respostas das candidaturas.
 perform public.cw_vacancies_tick(p_career);
end $function$;

-- career_hub_read
CREATE OR REPLACE FUNCTION public.career_hub_read()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare c public.careers;h jsonb;
begin
 c:=public.cw_read_career();
 if not exists(select 1 from public.cw_world where career_id=c.id) then return jsonb_build_object('initialization_required',true);end if;
 h:=public.mgr_hub();
 return h||jsonb_build_object('attention',case when public.cw_runtime_enabled(c.id) then public.cw_attention(c.id) end,
 'runtime_version',coalesce((select version from public.cw_runtime where career_id=c.id),0),
 'league_status',public.cw_league_status(c.id),
 'season_reward',(select jsonb_build_object('season_id',r.season_id,'club_id',r.club_id,'coins',r.coins,'reputation',r.reputation,'detail',r.detail)
   from public.cw_season_rewards r where r.career_id=c.id and not r.seen order by r.created_at desc limit 1),
 'calendar_versions',(select coalesce(jsonb_object_agg(competition_id,v),'{}') from(
 select competition_id,count(*)::text||':'||count(*) filter(where status='played')||':'||coalesce(max(played_at)::text,'')||':'||max(id)::text v
 from public.season_fixtures where season_id=(h#>>'{season,id}')::uuid group by competition_id)x));
end $function$;

-- Dificuldade única: propostas iniciais sem perfil acessível.
update public.sim_start_rules set options=(select jsonb_agg(o||jsonb_build_object('difficulty','standard')) from jsonb_array_elements(options) o);
-- Fase 5: valores do prêmio de fim de temporada ajustáveis por tabela (calibração sem nova versão de código).
create table if not exists public.cw_season_reward_rules(
 id boolean primary key default true check(id),
 league_coins_per_priority integer not null default 150,
 league_coins_per_place integer not null default 75,
 cup_coins_per_priority integer not null default 100,
 title_coins integer not null default 400,
 title_reputation numeric not null default 1.5,
 reputation_cap numeric not null default 6,
 dismissal_tolerance integer not null default 2);
insert into public.cw_season_reward_rules default values on conflict do nothing;
alter table public.cw_season_reward_rules enable row level security;
revoke all on public.cw_season_reward_rules from anon,authenticated;

-- mgr_season_end
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
begin
  select * into v_s from public.career_seasons where id = p_season for update;
  select * into v_rr from public.cw_season_reward_rules;
  if v_s.status <> 'active' then return v_s.summary; end if;
  for r in select competition_id from public.season_competitions where season_id = p_season and status <> 'finished' loop
    perform public.sim_complete_competition(p_season, r.competition_id);
  end loop;
  select * into v_c from public.mgr_coach where career_id = v_s.career_id;

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
    if v_league_fire then
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
$function$;

-- cw_league_status
CREATE OR REPLACE FUNCTION public.cw_league_status(p_career uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare w public.cw_world;c public.mgr_coach;o public.mgr_objectives;pos int;played int;n int;tol int;
begin
 select * into w from public.cw_world where career_id=p_career;
 select * into c from public.mgr_coach where career_id=p_career;
 if w.career_id is null or c.status is distinct from 'employed' then return null;end if;
 select * into o from public.mgr_objectives where career_id=p_career and season_id=w.primary_season and club_id=c.club_id
  and kind='league_pos' order by priority desc limit 1;
 if not found then return null;end if;
 select t.pos,t.played into pos,played from public.sim_standings(w.primary_season,o.competition_id,null) t where t.club_id=c.club_id;
 select coalesce((select dismissal_tolerance from public.cw_season_reward_rules),2) into tol;
 select count(*) into n from public.season_participants where season_id=w.primary_season and competition_id=o.competition_id;
 return jsonb_build_object('competition_id',o.competition_id,'target',o.target,'label',o.label,'status',o.status,
  'pos',pos,'played',played,'teams',n,'gap',pos-o.target,'tolerance',tol,
  'risk',case when coalesce(played,0)<3 or pos<=o.target then 'ok' when pos<=o.target+tol then 'attention' else 'danger' end);
end $function$;

-- Vaga que recusou sua candidatura não aceita outra.
alter table public.cw_job_vacancies add column if not exists rejected boolean not null default false;

-- cw_vacancies_tick
CREATE OR REPLACE FUNCTION public.cw_vacancies_tick(p_career uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
#variable_conflict use_column
declare w public.cw_world;r public.cw_job_rules;own text;rep numeric;cred numeric;comp record;t record;a record;
 req numeric;pay bigint;budget bigint;oid uuid;days int;prestige numeric;
begin
 select * into w from public.cw_world where career_id=p_career;
 if w.career_id is null then return;end if;
 select * into r from public.cw_job_rules;
 select club_id into own from public.mgr_coach where career_id=p_career and status='employed';
 select reputation into rep from public.mgr_coach where career_id=p_career;
 select coalesce(credibility,65) into cred from public.cw_coach where career_id=p_career;

 -- vagas vencidas: a IA contratou outro técnico
 for a in select v.id,v.club_id,ap.id app from public.cw_job_vacancies v left join public.cw_job_applications ap on ap.vacancy_id=v.id
  where v.career_id=p_career and v.closes_on<w.today loop
  if a.app is not null then
   perform public.mgr_msg(p_career,w.primary_season,w.elapsed_days,'board','Vaga preenchida',
    public.mgr_club_name(a.club_id)||' contratou outro treinador antes de responder à sua candidatura.',a.club_id);
  end if;
  delete from public.cw_job_vacancies where id=a.id;
 end loop;

 -- respostas das candidaturas
 for a in select ap.id,ap.vacancy_id,v.club_id from public.cw_job_applications ap join public.cw_job_vacancies v on v.id=ap.vacancy_id
  where ap.career_id=p_career and ap.answer_on<=w.today loop
  req:=public.cw_required_reputation(p_career,a.club_id);
  select c.prestige into prestige from public.cw_clubs c where c.career_id=p_career and c.club_id=a.club_id;
  if rep>=req then
   pay:=greatest(70,round(coalesce(prestige,50)*2.5+cred));
   budget:=greatest(0,public.cw_available_budget(p_career,a.club_id)-2*pay);
   insert into public.season_offers(career_id,season_id,from_club,kind,status,pitch,salary,contract_years,budget_guarantee,expires_on,expires_day,bonus_coins,context)
   values(p_career,w.primary_season,a.club_id,'coach','pending',
    'Sua candidatura convenceu a diretoria. Queremos você no comando.',pay,2,budget,public.cw_deadline(w.today),
    w.elapsed_days+(select max_negotiation_days from public.cw_rules),0,jsonb_build_object('source','application'))
   returning id into oid;
   perform public.mgr_msg(p_career,w.primary_season,w.elapsed_days,'board','Candidatura aceita: '||public.mgr_club_name(a.club_id),
    format('A diretoria aprovou seu nome: sua reputação (%s) atende ao porte do clube (pede %s). A proposta está em Carreira > Propostas.',round(rep),round(req)),a.club_id);
   delete from public.cw_job_vacancies where id=a.vacancy_id;
  else
   perform public.mgr_msg(p_career,w.primary_season,w.elapsed_days,'board','Candidatura recusada: '||public.mgr_club_name(a.club_id),
    format('A diretoria preferiu um nome mais experiente. Para o porte do clube, ela pede reputação %s; a sua é %s (credibilidade %s também pesa).',
     round(req),round(rep),round(cred)),a.club_id);
   delete from public.cw_job_applications where id=a.id;
   update public.cw_job_vacancies set rejected=true where id=a.vacancy_id;
  end if;
 end loop;

 -- demissões da IA: clube muito abaixo da posição esperada pela força
 for comp in select sc.competition_id from public.season_competitions sc join public.sim_competitions co on co.id=sc.competition_id
  where sc.season_id=w.primary_season and co.kind='league' loop
  for t in select s.club_id,s.pos,s.played,
    rank() over(order by c.prestige desc,s.club_id) expected
   from public.sim_standings(w.primary_season,comp.competition_id,null) s join public.cw_clubs c on c.career_id=p_career and c.club_id=s.club_id loop
   continue when t.club_id is not distinct from own or t.played<r.min_played or t.pos-t.expected<r.fire_gap;
   continue when exists(select 1 from public.cw_job_vacancies v where v.career_id=p_career and v.club_id=t.club_id);
   continue when public.cw_random(p_career::text||':fire:'||t.club_id||':'||w.today)>=r.fire_daily_chance;
   days:=r.vacancy_min_days+floor(public.cw_random(p_career::text||':vacancy:'||t.club_id||':'||w.today)*(r.vacancy_max_days-r.vacancy_min_days+1))::int;
   insert into public.cw_job_vacancies(career_id,club_id,opened_on,closes_on,reason)
   values(p_career,t.club_id,w.today,w.today+days,format('%sº lugar, abaixo do esperado',t.pos)) on conflict do nothing;
   perform public.cw_news_add(p_career,'ai-fired:'||t.club_id||':'||w.today,'job',public.mgr_club_name(t.club_id)||' demite o treinador',
    format('Com o time em %sº lugar, a diretoria abriu a vaga. Candidaturas em Carreira > Propostas.',t.pos),90,t.club_id);
  end loop;
 end loop;
end $function$;

-- career_vacancy_apply
CREATE OR REPLACE FUNCTION public.career_vacancy_apply(p_vacancy uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare car public.careers;v public.cw_job_vacancies;w public.cw_world;r public.cw_job_rules;own text;days int;
begin
 car:=public.mgr_lock();
 select * into r from public.cw_job_rules;
 select * into w from public.cw_world where career_id=car.id;
 select * into v from public.cw_job_vacancies where id=p_vacancy and career_id=car.id;
 if not found or v.closes_on<w.today then raise exception 'Vaga encerrada';end if;
 select club_id into own from public.mgr_coach where career_id=car.id and status='employed';
 if v.club_id is not distinct from own then raise exception 'Você já treina este clube';end if;
 if exists(select 1 from public.cw_job_applications where career_id=car.id and vacancy_id=v.id) then raise exception 'Candidatura já enviada';end if;
 if v.rejected then raise exception 'Este clube já recusou sua candidatura';end if;
 if (select count(*) from public.cw_job_applications where career_id=car.id)>=r.max_open_applications then
  raise exception 'Limite de % candidaturas abertas. Aguarde uma resposta.',r.max_open_applications;
 end if;
 days:=r.answer_min_days+floor(public.cw_random(car.id::text||':apply:'||v.id)*(r.answer_max_days-r.answer_min_days+1))::int;
 insert into public.cw_job_applications(career_id,vacancy_id,applied_on,answer_on) values(car.id,v.id,w.today,w.today+days);
 update public.cw_runtime set version=version+1 where career_id=car.id;
 return public.career_vacancies();
end $function$;

-- career_vacancies
CREATE OR REPLACE FUNCTION public.career_vacancies()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare car public.careers;w public.cw_world;own text;rep numeric;lim int;
begin
 car:=public.cw_read_career();
 select * into w from public.cw_world where career_id=car.id;
 select club_id,reputation into own,rep from public.mgr_coach where career_id=car.id and status='employed';
 if rep is null then select reputation into rep from public.mgr_coach where career_id=car.id;end if;
 select max_open_applications into lim from public.cw_job_rules;
 return jsonb_build_object(
  'limit',lim,
  'open_applications',(select count(*) from public.cw_job_applications a where a.career_id=car.id),
  'reputation',round(rep,1),
  'vacancies',coalesce((select jsonb_agg(jsonb_build_object('id',v.id,'club_id',v.club_id,'reason',v.reason,
    'closes_in',greatest(0,v.closes_on-w.today),'required_reputation',public.cw_required_reputation(car.id,v.club_id),
    'strength',public.cw_club_strength(car.id,v.club_id,null,coalesce(w.elapsed_days,0)),
    'division',(select co.short_name from public.season_participants pa join public.sim_competitions co on co.id=pa.competition_id and co.kind='league'
      where pa.season_id=w.primary_season and pa.club_id=v.club_id limit 1),
    'applied',a.id is not null,'rejected',v.rejected,'answer_in',case when a.id is not null then greatest(0,a.answer_on-w.today) end)
    order by v.closes_on,v.club_id)
   from public.cw_job_vacancies v left join public.cw_job_applications a on a.vacancy_id=v.id and a.career_id=car.id
   where v.career_id=car.id and v.club_id is distinct from own),'[]'::jsonb));
end $function$;

-- Vaga encerrada fica 60 dias registrada: o clube não reabre vaga logo em seguida.
alter table public.cw_job_vacancies add column if not exists closed boolean not null default false;

-- cw_vacancies_tick
CREATE OR REPLACE FUNCTION public.cw_vacancies_tick(p_career uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
#variable_conflict use_column
declare w public.cw_world;r public.cw_job_rules;own text;rep numeric;cred numeric;comp record;t record;a record;
 req numeric;pay bigint;budget bigint;oid uuid;days int;prestige numeric;
begin
 select * into w from public.cw_world where career_id=p_career;
 if w.career_id is null then return;end if;
 select * into r from public.cw_job_rules;
 select club_id into own from public.mgr_coach where career_id=p_career and status='employed';
 select reputation into rep from public.mgr_coach where career_id=p_career;
 select coalesce(credibility,65) into cred from public.cw_coach where career_id=p_career;

 -- vagas vencidas: a IA contratou outro técnico
 for a in select v.id,v.club_id,ap.id app from public.cw_job_vacancies v left join public.cw_job_applications ap on ap.vacancy_id=v.id
  where v.career_id=p_career and v.closes_on<w.today and not v.closed loop
  if a.app is not null then
   perform public.mgr_msg(p_career,w.primary_season,w.elapsed_days,'board','Vaga preenchida',
    public.mgr_club_name(a.club_id)||' contratou outro treinador antes de responder à sua candidatura.',a.club_id);
  end if;
  update public.cw_job_vacancies set closed=true where id=a.id;
  delete from public.cw_job_applications where vacancy_id=a.id;
 end loop;
 delete from public.cw_job_vacancies where career_id=p_career and closed and closes_on<w.today-60;

 -- respostas das candidaturas
 for a in select ap.id,ap.vacancy_id,v.club_id from public.cw_job_applications ap join public.cw_job_vacancies v on v.id=ap.vacancy_id
  where ap.career_id=p_career and ap.answer_on<=w.today loop
  req:=public.cw_required_reputation(p_career,a.club_id);
  select c.prestige into prestige from public.cw_clubs c where c.career_id=p_career and c.club_id=a.club_id;
  if rep>=req then
   pay:=greatest(70,round(coalesce(prestige,50)*2.5+cred));
   budget:=greatest(0,public.cw_available_budget(p_career,a.club_id)-2*pay);
   insert into public.season_offers(career_id,season_id,from_club,kind,status,pitch,salary,contract_years,budget_guarantee,expires_on,expires_day,bonus_coins,context)
   values(p_career,w.primary_season,a.club_id,'coach','pending',
    'Sua candidatura convenceu a diretoria. Queremos você no comando.',pay,2,budget,public.cw_deadline(w.today),
    w.elapsed_days+(select max_negotiation_days from public.cw_rules),0,jsonb_build_object('source','application'))
   returning id into oid;
   perform public.mgr_msg(p_career,w.primary_season,w.elapsed_days,'board','Candidatura aceita: '||public.mgr_club_name(a.club_id),
    format('A diretoria aprovou seu nome: sua reputação (%s) atende ao porte do clube (pede %s). A proposta está em Carreira > Propostas.',round(rep),round(req)),a.club_id);
   delete from public.cw_job_applications where id=a.id;
   update public.cw_job_vacancies set closed=true,closes_on=w.today where id=a.vacancy_id;
  else
   perform public.mgr_msg(p_career,w.primary_season,w.elapsed_days,'board','Candidatura recusada: '||public.mgr_club_name(a.club_id),
    format('A diretoria preferiu um nome mais experiente. Para o porte do clube, ela pede reputação %s; a sua é %s (credibilidade %s também pesa).',
     round(req),round(rep),round(cred)),a.club_id);
   delete from public.cw_job_applications where id=a.id;
   update public.cw_job_vacancies set rejected=true where id=a.vacancy_id;
  end if;
 end loop;

 -- demissões da IA: clube muito abaixo da posição esperada pela força
 for comp in select sc.competition_id from public.season_competitions sc join public.sim_competitions co on co.id=sc.competition_id
  where sc.season_id=w.primary_season and co.kind='league' loop
  for t in select s.club_id,s.pos,s.played,
    rank() over(order by c.prestige desc,s.club_id) expected
   from public.sim_standings(w.primary_season,comp.competition_id,null) s join public.cw_clubs c on c.career_id=p_career and c.club_id=s.club_id loop
   continue when t.club_id is not distinct from own or t.played<r.min_played or t.pos-t.expected<r.fire_gap;
   continue when exists(select 1 from public.cw_job_vacancies v where v.career_id=p_career and v.club_id=t.club_id);
   continue when public.cw_random(p_career::text||':fire:'||t.club_id||':'||w.today)>=r.fire_daily_chance;
   days:=r.vacancy_min_days+floor(public.cw_random(p_career::text||':vacancy:'||t.club_id||':'||w.today)*(r.vacancy_max_days-r.vacancy_min_days+1))::int;
   insert into public.cw_job_vacancies(career_id,club_id,opened_on,closes_on,reason)
   values(p_career,t.club_id,w.today,w.today+days,format('%sº lugar, abaixo do esperado',t.pos)) on conflict do nothing;
   perform public.cw_news_add(p_career,'ai-fired:'||t.club_id||':'||w.today,'job',public.mgr_club_name(t.club_id)||' demite o treinador',
    format('Com o time em %sº lugar, a diretoria abriu a vaga. Candidaturas em Carreira > Propostas.',t.pos),90,t.club_id);
  end loop;
 end loop;
end $function$;

-- career_vacancy_apply
CREATE OR REPLACE FUNCTION public.career_vacancy_apply(p_vacancy uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare car public.careers;v public.cw_job_vacancies;w public.cw_world;r public.cw_job_rules;own text;days int;
begin
 car:=public.mgr_lock();
 select * into r from public.cw_job_rules;
 select * into w from public.cw_world where career_id=car.id;
 select * into v from public.cw_job_vacancies where id=p_vacancy and career_id=car.id;
 if not found or v.closed or v.closes_on<w.today then raise exception 'Vaga encerrada';end if;
 select club_id into own from public.mgr_coach where career_id=car.id and status='employed';
 if v.club_id is not distinct from own then raise exception 'Você já treina este clube';end if;
 if exists(select 1 from public.cw_job_applications where career_id=car.id and vacancy_id=v.id) then raise exception 'Candidatura já enviada';end if;
 if v.rejected then raise exception 'Este clube já recusou sua candidatura';end if;
 if (select count(*) from public.cw_job_applications where career_id=car.id)>=r.max_open_applications then
  raise exception 'Limite de % candidaturas abertas. Aguarde uma resposta.',r.max_open_applications;
 end if;
 days:=r.answer_min_days+floor(public.cw_random(car.id::text||':apply:'||v.id)*(r.answer_max_days-r.answer_min_days+1))::int;
 -- A resposta chega antes de a vaga fechar.
 insert into public.cw_job_applications(career_id,vacancy_id,applied_on,answer_on) values(car.id,v.id,w.today,least(w.today+days,v.closes_on));
 update public.cw_runtime set version=version+1 where career_id=car.id;
 return public.career_vacancies();
end $function$;

-- career_vacancies
CREATE OR REPLACE FUNCTION public.career_vacancies()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare car public.careers;w public.cw_world;own text;rep numeric;lim int;
begin
 car:=public.cw_read_career();
 select * into w from public.cw_world where career_id=car.id;
 select club_id,reputation into own,rep from public.mgr_coach where career_id=car.id and status='employed';
 if rep is null then select reputation into rep from public.mgr_coach where career_id=car.id;end if;
 select max_open_applications into lim from public.cw_job_rules;
 return jsonb_build_object(
  'limit',lim,
  'open_applications',(select count(*) from public.cw_job_applications a where a.career_id=car.id),
  'reputation',round(rep,1),
  'vacancies',coalesce((select jsonb_agg(jsonb_build_object('id',v.id,'club_id',v.club_id,'reason',v.reason,
    'closes_in',greatest(0,v.closes_on-w.today),'required_reputation',public.cw_required_reputation(car.id,v.club_id),
    'strength',public.cw_club_strength(car.id,v.club_id,null,coalesce(w.elapsed_days,0)),
    'division',(select co.short_name from public.season_participants pa join public.sim_competitions co on co.id=pa.competition_id and co.kind='league'
      where pa.season_id=w.primary_season and pa.club_id=v.club_id limit 1),
    'applied',a.id is not null,'rejected',v.rejected,'answer_in',case when a.id is not null then greatest(0,a.answer_on-w.today) end)
    order by v.closes_on,v.club_id)
   from public.cw_job_vacancies v left join public.cw_job_applications a on a.vacancy_id=v.id and a.career_id=car.id
   where v.career_id=car.id and not v.closed and v.club_id is distinct from own),'[]'::jsonb));
end $function$;

-- career_vacancy_club
CREATE OR REPLACE FUNCTION public.career_vacancy_club(p_vacancy uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare car public.careers;v public.cw_job_vacancies;
begin
 car:=public.cw_read_career();
 select * into v from public.cw_job_vacancies where id=p_vacancy and career_id=car.id and not closed;
 if not found then raise exception 'Vaga encerrada';end if;
 return public.cw_club_preview(car.id,v.club_id);
end $function$;
