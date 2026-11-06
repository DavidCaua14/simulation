-- XP por vitória (2026-11-06): cada vitória numa partida jogada pelo treinador rende 40 XP de conta,
-- multiplicado pela competição (xp_mult) e pela fase (mata-mata ×1,2; final ×1,5). Creditado uma única vez
-- por partida em base_match_rewards (mesmo lugar da energia por vitória) e mostrado no pós-jogo.
alter table public.base_match_rewards add column if not exists xp int not null default 0;

create or replace function public.base_award_match(p_fixture bigint)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare f public.season_fixtures;s public.career_seasons;club text;mine int;opp int;won boolean;mult numeric;award public.base_match_rewards;
begin
 select * into f from public.season_fixtures where id=p_fixture;
 if f.id is null or f.status<>'played' or not coalesce(f.player_match,false) then return;end if;
 if f.played_at is null or f.played_at<(select activated_at from public.base_card_release) then return;end if;
 select * into s from public.career_seasons where id=f.season_id;
 club:=coalesce(f.coach_club,s.club_id);
 if club is null or club not in(f.home_club,f.away_club) then return;end if;
 perform 1 from public.careers where id=s.career_id for update;
 mine:=case when f.home_club=club then f.home_goals else f.away_goals end;
 opp:=case when f.home_club=club then f.away_goals else f.home_goals end;
 won:=mine>opp or(mine=opp and f.home_pens is not null and case when f.home_club=club then f.home_pens>f.away_pens else f.away_pens>f.home_pens end);
 select c.xp_mult*(case public.mgr_stage_rank(f.competition_id,f.stage) when 5 then 1.5 when 4 then 1.2 when 3 then 1.2 when 2 then 1.2 else 1 end) into mult
  from public.sim_competitions c where c.id=f.competition_id;
 insert into public.base_match_rewards(fixture_id,season_id,career_id,coins,energy,xp)
  values(f.id,s.id,s.career_id,0,won::int,case when won then round(40*coalesce(mult,1))::int else 0 end)
  on conflict do nothing returning * into award;
 if award.fixture_id is null then return;end if;
 if award.coins>0 then perform public.econ_apply(s.career_id,'coins',award.coins,'match_reward',f.id::text);end if;
 if award.energy>0 then perform public.econ_apply(s.career_id,'bonus_energy',1,'match_win_energy',f.id::text);end if;
 -- XP da conta por vitória (sobe de nível mais rápido); creditado uma vez por partida, como a energia
 if award.xp>0 then update public.careers set xp=xp+award.xp where id=s.career_id;end if;
end $function$;

create or replace function public.mgr_after_user_match(p_fixture bigint)
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
  v_xp := coalesce((select xp from public.base_match_rewards where fixture_id=p_fixture),0);
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
