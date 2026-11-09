-- Consequências duras de fracasso (2026-11-09)
-- * Derrota: moral do elenco cai e o treinador perde pontos no ranking (só daqui para frente: nada retroativo).
-- * Eliminação em mata-mata: moral do elenco, diretoria, torcida e reputação caem bastante; mais pontos perdidos no ranking.
-- * Rebaixamento: demissão automática, diretoria e torcida revoltadas, reputação ("respeito") e credibilidade despencam,
--   e o clube não procura mais o treinador até a reputação chegar perto de 100 (mgr_club_bans.min_reputation).
-- Ajustes finos ficam em public.mgr_failure_rules (uma linha).

create table if not exists public.mgr_failure_rules (
  id boolean primary key default true check (id),
  loss_morale numeric not null default 3,           -- moral do elenco por derrota
  heavy_loss_morale numeric not null default 3,     -- extra por derrota por 3+ gols
  elim_morale numeric not null default 12,          -- extra por eliminação
  loss_rank_points int not null default 15,         -- pontos de ranking perdidos por derrota
  heavy_loss_rank_points int not null default 5,    -- extra por derrota por 3+ gols
  elim_rank_points int not null default 40,         -- extra por eliminação
  elim_board numeric not null default 14,           -- queda da diretoria na eliminação (antes 6)
  elim_fans numeric not null default 16,            -- queda da torcida na eliminação (antes 6)
  elim_reputation numeric not null default 1.5,     -- reputação perdida na eliminação
  releg_rep_keep numeric not null default 0.45,     -- reputação mantida após rebaixamento (fração)
  releg_rep_minus numeric not null default 5,       -- e ainda perde estes pontos
  releg_rep_floor numeric not null default 20,      -- piso: abaixo disso nem clube pequeno faria proposta
  releg_credibility numeric not null default 15,    -- credibilidade perdida (além dos −9 da demissão)
  releg_cred_floor numeric not null default 50,     -- piso da credibilidade, pelo mesmo motivo
  releg_rank_points int not null default 200,       -- pontos de ranking perdidos (além dos −150 da demissão)
  releg_morale numeric not null default 15,         -- moral do elenco rebaixado
  ban_reputation numeric not null default 95        -- reputação para o clube rebaixado voltar a procurá-lo
);
insert into public.mgr_failure_rules default values on conflict do nothing;

create table if not exists public.mgr_club_bans (
  career_id uuid not null references public.careers(id) on delete cascade,
  club_id text not null,
  reason text not null,
  season_no int,
  min_reputation numeric not null,
  created_at timestamptz not null default now(),
  primary key (career_id, club_id)
);
alter table public.mgr_failure_rules enable row level security;
alter table public.mgr_club_bans enable row level security;
revoke all on public.mgr_failure_rules, public.mgr_club_bans from anon, authenticated;

alter table public.mgr_coach add column if not exists rank_penalty int not null default 0;

-- Clube fechado para o treinador enquanto a reputação estiver abaixo do exigido.
create or replace function public.mgr_club_banned(p_career uuid, p_club text)
 returns boolean language sql stable security definer set search_path to 'public' as $$
 select exists(select 1 from public.mgr_club_bans b join public.mgr_coach c on c.career_id = b.career_id
                where b.career_id = p_career and b.club_id = p_club and coalesce(c.reputation, 0) < b.min_reputation)
$$;

-- Moral de todo o elenco do clube cai (jogadores sem linha própria usam a moral padrão 65 da view).
create or replace function public.mgr_squad_morale_hit(p_career uuid, p_club text, p_amount numeric)
 returns void language plpgsql security definer set search_path to 'public' as $$
begin
 if coalesce(p_amount, 0) <= 0 or p_club is null then return; end if;
 update public.cw_players p set morale = round(greatest(0, p.morale - p_amount), 1), morale_trend = -1
  where p.career_id = p_career
    and p.player_id in (select mp.player_id from public.mgr_players mp where mp.career_id = p_career and mp.club_id = p_club);
end $$;

-- Rebaixamento: revolta, demissão, reputação/credibilidade no chão e clube fechado.
create or replace function public.mgr_relegation_fallout(p_career uuid, p_season uuid, p_club text)
 returns void language plpgsql security definer set search_path to 'public' as $$
declare rr public.mgr_failure_rules; s public.career_seasons; c public.mgr_coach;
begin
 select * into rr from public.mgr_failure_rules;
 select * into s from public.career_seasons where id = p_season;
 select * into c from public.mgr_coach where career_id = p_career;
 if c.status <> 'employed' or c.club_id is distinct from p_club then return; end if;
 update public.mgr_coach set board_confidence = 0, fan_mood = 0 where career_id = p_career;
 perform public.mgr_squad_morale_hit(p_career, p_club, rr.releg_morale);
 perform public.mgr_msg(p_career, p_season, s.day_no, 'board', 'Diretoria revoltada',
   format('O rebaixamento %s é inaceitável. A diretoria não quer mais o seu nome no clube.', public.mgr_club_do(p_club)), p_club);
 perform public.mgr_msg(p_career, p_season, s.day_no, 'fans', 'Torcida em fúria',
   'Protestos na porta do CT, pichações no muro e gritos de "fora!": a torcida responsabiliza você pela queda.', p_club);
 perform public.mgr_fire(p_career, 'rebaixamento do clube');
 update public.mgr_coach
    set reputation = round(greatest(least(reputation, rr.releg_rep_floor), reputation * rr.releg_rep_keep - rr.releg_rep_minus), 2),
        rank_penalty = rank_penalty + rr.releg_rank_points
  where career_id = p_career;
 update public.cw_coach set credibility = greatest(least(credibility, rr.releg_cred_floor), credibility - rr.releg_credibility) where career_id = p_career;
 insert into public.mgr_club_bans(career_id, club_id, reason, season_no, min_reputation)
 values (p_career, p_club, 'rebaixamento', s.season_no, rr.ban_reputation)
 on conflict (career_id, club_id) do update set reason = excluded.reason, season_no = excluded.season_no,
   min_reputation = excluded.min_reputation, created_at = now();
 perform public.cw_news_add(p_career, 'relegation:' || p_season, 'job',
   public.mgr_club_name(p_club) || ' é rebaixado e demite o treinador',
   format('Diretoria e torcida estão revoltadas. Sua reputação despencou e só clubes menores devem procurar você. %s não volta a fazer proposta até sua reputação chegar a %s.',
          public.mgr_club_name(p_club), round(rr.ban_reputation)), 100, p_club);
end $$;

revoke all on function public.mgr_club_banned(uuid, text), public.mgr_squad_morale_hit(uuid, text, numeric),
  public.mgr_relegation_fallout(uuid, uuid, text) from public, anon, authenticated;

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
  v_fr    public.mgr_failure_rules;
  v_rk    int := 0;
  v_mo    numeric := 0;
begin
  select * into v_f from public.season_fixtures where id = p_fixture;
  select * into v_m from public.mgr_matches where fixture_id = p_fixture;
  select * into v_s from public.career_seasons where id = v_f.season_id;
  select * into v_c from public.mgr_coach where career_id = v_m.career_id for update;
  select * into v_comp from public.sim_competitions where id = v_f.competition_id;
  select * into v_car from public.careers where id = v_m.career_id;
  select * into v_fr from public.mgr_failure_rules;
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
  if v_out then v_db := v_db - v_fr.elim_board; v_df := v_df - v_fr.elim_fans; end if;  -- eliminação pesa muito mais (2026-11-09)
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
  if v_out then v_dr := v_dr - v_fr.elim_reputation; end if;

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
  -- derrota/eliminação: moral do elenco e pontos de ranking (2026-11-09)
  if v_res = 'loss' then
    v_rk := v_fr.loss_rank_points + case when v_opp - v_my >= 3 then v_fr.heavy_loss_rank_points else 0 end;
    v_mo := v_fr.loss_morale + case when v_opp - v_my >= 3 then v_fr.heavy_loss_morale else 0 end;
  end if;
  if v_out then v_rk := v_rk + v_fr.elim_rank_points; v_mo := v_mo + v_fr.elim_morale; end if;
  if v_rk > 0 then update public.mgr_coach set rank_penalty = rank_penalty + v_rk where career_id = v_c.career_id; end if;
  perform public.mgr_squad_morale_hit(v_c.career_id, v_c.club_id, v_mo);
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
    'fire_reason', v_fire,
    'ranking', jsonb_build_object('delta', -v_rk),
    'squad_morale', jsonb_build_object('delta', -v_mo));
end;
$function$;

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
  v_dp    record;   -- perfil de dificuldade em vigor (evoluÃ§Ã£o 05: public.mgr_difficulty)
  v_dr    numeric := 0;
  v_n     int;
  v_i     int;
  v_league_fire boolean := false; -- Fase 4: a meta da liga decide a demissÃ£o
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
  for r in select competition_id from public.season_competitions where season_id = p_season and status <> 'finished' loop
    perform public.sim_complete_competition(p_season, r.competition_id);
  end loop;
  select * into v_c from public.mgr_coach where career_id = v_s.career_id;

  -- metas de outra passagem ou de passagem iniciada nesta temporada com menos de 10 jogos nÃ£o sÃ£o cobradas
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
      -- campanha no campeonato nacional tambÃ©m conta para a reputaÃ§Ã£o
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

  -- acesso, rebaixamento e vagas continentais da prÃ³xima temporada (aplicado uma Ãºnica vez)
  v_sum := v_sum || jsonb_build_object('transition', public.sim_season_transition(p_season));
  update public.career_seasons set status = 'finished', finished_at = now(), summary = v_sum where id = p_season;
  v_releg := v_c.status = 'employed' and exists (select 1 from jsonb_each(coalesce(v_sum #> '{transition,relegated}', '{}'::jsonb)) e
             cross join lateral jsonb_array_elements_text(case when jsonb_typeof(e.value) = 'array' then e.value else '[]'::jsonb end) x where x = v_c.club_id);
  -- PrÃªmio de fim de temporada (Fase 4): moedas pela meta superada e por tÃ­tulo, uma vez por temporada;
  -- reputaÃ§Ã£o da temporada com teto de +6 (cada ponto vale 15 no rank).
  if v_c.status = 'employed' then
    select count(*) into v_titles from public.season_competitions where season_id = p_season and champion_club = v_c.club_id;
    v_coins := v_coins + v_rr.title_coins * v_titles;
    v_dr := v_dr + v_rr.title_reputation * v_titles;
  end if;
  v_dr := least(v_dr, v_rr.reputation_cap);
  v_rep_before := v_c.reputation;
  v_dp := public.mgr_difficulty(v_s.career_id);   -- lido ANTES de contar a temporada (o perfil vale atÃ© o fim dela)
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
      perform public.mgr_fire(v_s.career_id, 'objetivo da temporada nÃ£o cumprido');
    else
      perform public.mgr_msg(v_s.career_id, p_season, v_s.day_no, 'board', 'BalanÃ§o da temporada ' || v_s.year,
        case when v_met + v_fail = 0 then 'VocÃª assumiu o clube na reta final: as metas desta temporada nÃ£o foram cobradas. A avaliaÃ§Ã£o comeÃ§a na prÃ³xima.'
             when v_fail = 0 then 'Objetivos cumpridos. A diretoria estÃ¡ satisfeita e conta com vocÃª na prÃ³xima temporada.'
             when v_met > 0 then format('%s objetivo(s) cumprido(s) e %s nÃ£o. A diretoria espera evoluÃ§Ã£o.', v_met, v_fail)
             else 'Temporada abaixo do esperado. A cobranÃ§a vai aumentar.' end, v_c.club_id);
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
     and not public.mgr_club_banned(p_career, x.club_id)
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
                             'region', (select region from public.sim_competitions where id = v_cand.league),
                             'abroad', v_cand.other or (select country from public.sim_clubs where id = v_cand.id) is distinct from coalesce((select country from public.sim_clubs where id = v_coach.club_id), 'BRA')))
  returning id into v_id;
  perform public.mgr_msg(p_career, p_season, p_day, 'offer', 'Proposta: ' || v_cand.name, v_pitch, v_cand.id);
  return jsonb_build_object('id', v_id, 'club_id', v_cand.id, 'bonus_coins', v_bonus, 'pitch', v_pitch, 'expires_day', p_day + 5,
                            'context', jsonb_build_object('position', v_pos, 'objective', v_obj, 'league', v_cand.league,
                            'abroad', v_cand.other or (select country from public.sim_clubs where id = v_cand.id) is distinct from coalesce((select country from public.sim_clubs where id = v_coach.club_id), 'BRA')));
end;
$function$;

CREATE OR REPLACE FUNCTION public.cw_required_reputation(p_career uuid, p_club text)
 RETURNS numeric
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
 select greatest(coalesce((select b.min_reputation from public.mgr_club_bans b where b.career_id=p_career and b.club_id=p_club),0),round((coalesce(c.prestige,s.strength)-55-(coalesce(k.credibility,(select credibility from public.cw_coach where career_id=p_career),65)-65)*.18)/.32,1))
 from public.sim_clubs s left join public.cw_clubs c on c.career_id=p_career and c.club_id=s.id left join public.cw_coach k on k.career_id=c.career_id
 where s.id=p_club
$function$;

CREATE OR REPLACE FUNCTION public.ranking_scores()
 RETURNS TABLE(career_id uuid, nickname text, photo_id text, level integer, club_id text, titles integer, wins integer, draws integer, losses integer, reputation numeric, events integer, fired integer, points bigint, created_at timestamp with time zone, xp integer, avatar text, has_photo boolean)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select c.id,c.nickname,c.photo_id,c.level,
   case when mc.status='employed' then mc.club_id end,
   coalesce(mc.titles,0),coalesce(mc.wins,0),coalesce(mc.draws,0),coalesce(mc.losses,0),round(coalesce(mc.reputation,0),1),
   coalesce(ev.n,0)::int,coalesce(mc.fired_count,0),
   (coalesce(lg.legacy_points,0)+c.level*100+floor(coalesce(c.xp,0)/10.0)+round(coalesce(mc.reputation,0)*15)
    +coalesce(mc.titles,0)*500+coalesce(mc.wins,0)*20+coalesce(mc.draws,0)*7+coalesce(ev.n,0)*25-coalesce(mc.fired_count,0)*150-coalesce(mc.rank_penalty,0))::bigint,
   c.created_at,coalesce(c.xp,0),
   case when pp.avatar_data like 'data:%' then null else pp.avatar_data end,coalesce(pp.avatar_data like 'data:%',false)
  from public.careers c
  left join public.career_legacy lg on lg.career_id=c.id
  left join public.mgr_coach mc on mc.career_id=c.id
  left join public.player_profiles pp on pp.career_id=c.id
  left join (select e.career_id,count(*) n from public.event_completions e group by e.career_id) ev on ev.career_id=c.id
  where c.status='active'
 $function$;

CREATE OR REPLACE FUNCTION public.ranking_overall(p_limit integer DEFAULT 50)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare me uuid:=public.cw_current_career();
begin
 return(with ranked as(
   select s.*,row_number() over(order by s.points desc,s.level desc,s.wins desc,s.created_at,s.career_id) as position from public.ranking_scores() s)
  select jsonb_build_object(
   'entries',coalesce((select jsonb_agg(jsonb_build_object('position',r.position,'nickname',r.nickname,'photo_id',r.photo_id,'avatar',r.avatar,'has_photo',r.has_photo,'level',r.level,'club_id',r.club_id,
     'titles',r.titles,'wins',r.wins,'draws',r.draws,'losses',r.losses,'reputation',r.reputation,'events',r.events,'points',r.points,'is_me',r.career_id=me) order by r.position)
    from ranked r where r.position<=least(greatest(coalesce(p_limit,50),1),100)),'[]'::jsonb),
   'me',(select jsonb_build_object('position',r.position,'nickname',r.nickname,'photo_id',r.photo_id,'avatar',r.avatar,'has_photo',r.has_photo,'level',r.level,'xp',r.xp,
     'club_id',r.club_id,'titles',r.titles,'wins',r.wins,'draws',r.draws,'losses',r.losses,'reputation',r.reputation,'events',r.events,'fired',r.fired,'penalty',(select coalesce(rank_penalty,0) from public.mgr_coach where career_id=r.career_id),'points',r.points,
     'difficulty_label',(public.cw_difficulty_level(r.career_id)).label,'ranking_mult',(public.cw_difficulty_level(r.career_id)).ranking_mult)
    from ranked r where r.career_id=me),
   'total',(select count(*) from ranked)));
end $function$;
