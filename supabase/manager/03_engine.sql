-- =====================================================================
-- MODO CARREIRA (TREINADOR) — 3/5: MOTOR DE PARTIDAS
-- Simulação minuto a minuto no SERVIDOR (o app não escolhe resultado):
--   atributos x posição em que o jogador atua x condição física x ritmo x formação x táticas
--   x mando de campo x placar x aleatoriedade controlada.
-- Placar, eventos e estatísticas saem da MESMA simulação (os números são contados dos eventos).
-- Funções internas (mgr_*) — o app só chama as de 04_career.sql.
-- =====================================================================

-- jogador dentro do motor
do $$ begin
  if not exists (select 1 from pg_type where typname = 'mgr_ep') then
    create type public.mgr_ep as (
      pid text, sd smallint, slot text, pos text,
      aw float8, dw float8, cw float8, drain float8,
      att float8, cre float8, def float8, ctl float8, gk float8,
      fin float8, head float8, pace float8, stam float8, tack float8, str float8,
      fit float8, cond float8, rhy float8,
      goals int, assists int, shots int, sot int, saves int, fouls int, yel int, red int,
      inj boolean, on_field boolean, mins int
    );
  end if;
end $$;

-- formação "preferida" de cada clube da IA nesta carreira (calculada uma vez)
create table if not exists public.mgr_ai_clubs (
  career_id uuid not null references public.careers (id) on delete cascade,
  club_id   text not null references public.sim_clubs (id),
  formation text not null references public.sim_formations (id),
  primary key (career_id, club_id)
);
alter table public.mgr_ai_clubs enable row level security;
revoke all on public.mgr_ai_clubs from anon, authenticated;

-- ---------------------------------------------------------------------
-- 1) Utilidades
-- ---------------------------------------------------------------------
-- índice sorteado por pesos (1-based); 0 se não houver peso
create or replace function public.mgr_pick(p_w numeric[])
returns int language plpgsql volatile as $$
declare
  v_t numeric := 0;
  v_r numeric;
  v_i int;
begin
  if p_w is null then return 0; end if;
  for v_i in 1 .. coalesce(array_length(p_w, 1), 0) loop v_t := v_t + greatest(coalesce(p_w[v_i], 0), 0); end loop;
  if v_t <= 0 then return 0; end if;
  v_r := random() * v_t;
  for v_i in 1 .. array_length(p_w, 1) loop
    v_r := v_r - greatest(coalesce(p_w[v_i], 0), 0);
    if v_r <= 0 then return v_i; end if;
  end loop;
  return array_length(p_w, 1);
end;
$$;

create or replace function public.mgr_pick(p_w float8[])
returns int language plpgsql volatile as $$
declare
  v_t float8 := 0;
  v_r float8;
  v_i int;
  v_n int := coalesce(array_length(p_w, 1), 0);
begin
  for v_i in 1 .. v_n loop if p_w[v_i] > 0 then v_t := v_t + p_w[v_i]; end if; end loop;
  if v_t <= 0 then return 0; end if;
  v_r := random() * v_t;
  for v_i in 1 .. v_n loop
    if p_w[v_i] > 0 then
      v_r := v_r - p_w[v_i];
      if v_r <= 0 then return v_i; end if;
    end if;
  end loop;
  return v_n;
end;
$$;

-- fator de rendimento pela condição física (100 = 1.0; cai mais rápido abaixo de 50)
create or replace function public.mgr_cond_factor(p_cond numeric)
returns numeric language sql immutable as $$
  select (0.70 + 0.30 * p_cond / 100) * case when p_cond < 50 then 0.88 + 0.12 * p_cond / 50 else 1 end
$$;

-- adequação de um jogador a uma posição (natural 1.0 / secundária 0.97 / tabela sim_position_fit)
create or replace function public.mgr_fit(p_player text, p_pos text)
returns numeric language sql stable as $$
  select greatest(coalesce((select f.fit from public.sim_position_fit f where f.from_pos = p.position and f.to_pos = p_pos), 0.5),
                  case when p_pos = any (p.secondary_positions) then 0.97 else 0 end)
    from public.sim_players p where p.id = p_player
$$;

-- jogador disponível para a competição? (lesão e suspensão)
create or replace function public.mgr_available(p_injured_until int, p_susp jsonb, p_comp text, p_day int)
returns boolean language sql immutable as $$
  select (p_injured_until is null or p_injured_until <= p_day)
     and coalesce((p_susp ->> p_comp)::int, 0) <= 0
$$;

-- ---------------------------------------------------------------------
-- 2) Escalação automática (IA, sugestão do auxiliar e correção de escalação)
-- Guloso por escassez: goleiro, zagueiros, laterais, meio, ataque. Usa nota na posição x condição.
-- ---------------------------------------------------------------------
create or replace function public.mgr_auto_lineup(p_career uuid, p_club text, p_formation text, p_comp text, p_day int,
                                                  p_bench int default 12)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  v_form   public.sim_formations;
  v_pids   text[];
  v_isgk   boolean[];
  v_cf     float8[];
  v_eff    float8[];          -- matriz achatada: jogador i, posição k -> v_eff[(i-1)*10 + k]
  v_best   float8[];
  v_used   boolean[];
  v_n      int;
  v_slot   record;
  v_k      int;
  v_i      int;
  v_pick   int;
  v_sc     float8;
  v_top    float8;
  v_slots  jsonb := '{}'::jsonb;
  v_bench  text[] := '{}';
  v_gk     int := 0;
  v_order  int[];
  v_pos    text[] := array['GOL', 'LD', 'ZAG', 'LE', 'VOL', 'MC', 'MEI', 'PD', 'PE', 'ATA'];
begin
  select * into v_form from public.sim_formations where id = coalesce(p_formation, '4-3-3');
  if not found then select * into v_form from public.sim_formations where id = '4-3-3'; end if;

  -- todos os disponíveis de uma vez (indisponíveis entram com peso mínimo: só se não houver ninguém)
  select array_agg(x.pid order by x.pid), array_agg(x.isgk order by x.pid), array_agg(x.cf order by x.pid),
         array_agg(x.best order by x.pid)
    into v_pids, v_isgk, v_cf, v_best
    from (
      select mp.player_id as pid, p.position = 'GOL' as isgk,
             (public.mgr_cond_factor(mp.condition) * (case when mp.condition < 60 then 0.9 else 1 end)
               * (case when public.mgr_available(mp.injured_until, mp.susp, p_comp, p_day) then 1 else 0.001 end))::float8 as cf,
             (select r.eff from public.sim_player_pos_ratings r where r.player_id = p.id and r.pos = p.position)::float8 as best
        from public.mgr_players mp join public.sim_players p on p.id = mp.player_id and p.active
       where mp.career_id = p_career and mp.club_id = p_club
    ) x;
  v_n := coalesce(array_length(v_pids, 1), 0);
  if v_n = 0 then return jsonb_build_object('formation', v_form.id, 'slots', '{}'::jsonb, 'bench', '[]'::jsonb); end if;

  select array_agg(r.eff::float8 order by mp.player_id, sp.sort)
    into v_eff
    from public.mgr_players mp
    join public.sim_players p on p.id = mp.player_id and p.active
    join public.sim_player_pos_ratings r on r.player_id = mp.player_id
    join public.sim_positions sp on sp.code = r.pos
   where mp.career_id = p_career and mp.club_id = p_club;

  v_used := array_fill(false, array[v_n]);
  for v_slot in
    select s ->> 'slot' as slot, s ->> 'pos' as pos
      from jsonb_array_elements(v_form.slots) s
     order by case s ->> 'pos' when 'GOL' then 1 when 'ZAG' then 2 when 'LD' then 3 when 'LE' then 3 when 'VOL' then 4
                               when 'ATA' then 5 when 'MC' then 6 when 'MEI' then 7 else 8 end
  loop
    v_k := array_position(v_pos, v_slot.pos);
    v_pick := 0; v_top := -1;
    for v_i in 1 .. v_n loop
      continue when v_used[v_i];
      v_sc := v_eff[(v_i - 1) * 10 + v_k] * v_cf[v_i];
      if v_sc > v_top then v_top := v_sc; v_pick := v_i; end if;
    end loop;
    if v_pick > 0 then
      v_used[v_pick] := true;
      v_slots := v_slots || jsonb_build_object(v_slot.slot, v_pids[v_pick]);
    end if;
  end loop;

  -- banco: 1 goleiro + os melhores restantes (só disponíveis)
  v_top := -1;
  for v_i in 1 .. v_n loop
    if not v_used[v_i] and v_isgk[v_i] and v_cf[v_i] > 0.01 and v_best[v_i] > v_top then v_top := v_best[v_i]; v_gk := v_i; end if;
  end loop;
  if v_gk > 0 then v_bench := array[v_pids[v_gk]]; v_used[v_gk] := true; end if;
  select array_agg(i order by v_best[i] * v_cf[i] desc) into v_order
    from generate_series(1, v_n) i where not v_used[i] and v_cf[i] > 0.01;
  for v_i in 1 .. least(coalesce(array_length(v_order, 1), 0), greatest(p_bench - coalesce(array_length(v_bench, 1), 0), 0)) loop
    v_bench := v_bench || v_pids[v_order[v_i]];
  end loop;

  return jsonb_build_object('formation', v_form.id, 'slots', v_slots, 'bench', to_jsonb(v_bench));
end;
$$;

-- soma das notas de uma escalação (para escolher a formação da IA)
create or replace function public.mgr_lineup_score(p_lineup jsonb, p_form text)
returns numeric language sql stable as $$
  select coalesce(sum(r.eff), 0)
    from public.sim_formations f
    cross join lateral jsonb_array_elements(f.slots) s
    join public.sim_player_pos_ratings r on r.player_id = p_lineup -> 'slots' ->> (s ->> 'slot') and r.pos = s ->> 'pos'
   where f.id = p_form
$$;

-- formação da IA: a que melhor encaixa o elenco (calculada uma vez por carreira e clube)
create or replace function public.mgr_ai_formation(p_career uuid, p_club text)
returns text language plpgsql security definer set search_path = public as $$
declare v_f text;
begin
  select formation into v_f from public.mgr_ai_clubs where career_id = p_career and club_id = p_club;
  if v_f is not null then return v_f; end if;
  -- soma das k melhores notas por posição exigida em cada formação (aproximação rápida do melhor encaixe)
  with ranked as (
    select r.pos, r.eff, row_number() over (partition by r.pos order by r.eff desc) as rk
      from public.mgr_players mp join public.sim_player_pos_ratings r on r.player_id = mp.player_id
     where mp.career_id = p_career and mp.club_id = p_club
  ), slots as (
    select f.id, s ->> 'pos' as pos, row_number() over (partition by f.id, s ->> 'pos' order by s ->> 'slot') as k
      from public.sim_formations f cross join lateral jsonb_array_elements(f.slots) s
     where f.id in ('4-3-3', '4-2-3-1', '4-4-2', '3-5-2', '4-1-4-1')
  )
  select sl.id into v_f
    from slots sl join ranked rk on rk.pos = sl.pos and rk.rk = sl.k
   group by sl.id
   order by sum(rk.eff) * case sl.id when '4-2-3-1' then 1.004 when '4-3-3' then 1.003 else 1 end desc
   limit 1;
  v_f := coalesce(v_f, '4-3-3');
  insert into public.mgr_ai_clubs (career_id, club_id, formation) values (p_career, p_club, v_f)
  on conflict (career_id, club_id) do update set formation = excluded.formation;
  return v_f;
end;
$$;

-- ---------------------------------------------------------------------
-- 3) Montagem da partida
-- ---------------------------------------------------------------------
-- coloca os 11 + banco de um lado em mgr_match_players
create or replace function public.mgr_build_side(p_fixture bigint, p_side char, p_career uuid, p_club text, p_lineup jsonb)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_slots jsonb;
  v_form  text := p_lineup ->> 'formation';
begin
  select f.slots into v_slots from public.sim_formations f where f.id = v_form;

  insert into public.mgr_match_players (fixture_id, player_id, side, club_id, slot, pos, status, starter, fit, cond, rhythm,
    c_att, c_cre, c_def, c_ctl, c_gk, c_fin, c_head, c_pace, c_stam, c_tack, c_str, entered_min)
  select p_fixture, p.id, p_side, p_club, s ->> 'slot', s ->> 'pos', 'on', true,
         public.mgr_fit(p.id, s ->> 'pos'), mp.condition, mp.rhythm,
         0.35 * a.finishing + 0.25 * a.off_ball + 0.20 * a.dribbling + 0.20 * a.pace,
         0.40 * a.passing + 0.35 * a.vision + 0.25 * a.technique,
         0.30 * a.marking + 0.30 * a.tackling + 0.25 * a.positioning + 0.15 * a.heading,
         0.40 * a.passing + 0.30 * a.technique + 0.15 * a.vision + 0.15 * a.stamina,
         0.40 * a.gk_reflexes + 0.30 * a.gk_handling + 0.30 * a.gk_positioning,
         a.finishing, a.heading, a.pace, a.stamina, a.tackling, a.strength, 0
    from jsonb_array_elements(v_slots) s
    join public.sim_players p on p.id = p_lineup -> 'slots' ->> (s ->> 'slot')
    join public.sim_player_attrs a on a.player_id = p.id
    join public.mgr_players mp on mp.career_id = p_career and mp.player_id = p.id
  on conflict (fixture_id, player_id) do nothing;

  insert into public.mgr_match_players (fixture_id, player_id, side, club_id, slot, pos, status, starter, fit, cond, rhythm,
    c_att, c_cre, c_def, c_ctl, c_gk, c_fin, c_head, c_pace, c_stam, c_tack, c_str)
  select p_fixture, p.id, p_side, p_club, null, p.position, 'bench', false, 1, mp.condition, mp.rhythm,
         0.35 * a.finishing + 0.25 * a.off_ball + 0.20 * a.dribbling + 0.20 * a.pace,
         0.40 * a.passing + 0.35 * a.vision + 0.25 * a.technique,
         0.30 * a.marking + 0.30 * a.tackling + 0.25 * a.positioning + 0.15 * a.heading,
         0.40 * a.passing + 0.30 * a.technique + 0.15 * a.vision + 0.15 * a.stamina,
         0.40 * a.gk_reflexes + 0.30 * a.gk_handling + 0.30 * a.gk_positioning,
         a.finishing, a.heading, a.pace, a.stamina, a.tackling, a.strength
    from jsonb_array_elements_text(coalesce(p_lineup -> 'bench', '[]'::jsonb)) b(pid)
    join public.sim_players p on p.id = b.pid
    join public.sim_player_attrs a on a.player_id = p.id
    join public.mgr_players mp on mp.career_id = p_career and mp.player_id = p.id
  on conflict (fixture_id, player_id) do nothing;
end;
$$;

-- força média do 11 (para a tática da IA e para a expectativa da diretoria)
create or replace function public.mgr_side_strength(p_fixture bigint, p_side char)
returns numeric language sql stable as $$
  select coalesce(avg(r.eff), 60)
    from public.mgr_match_players mp
    join public.sim_player_pos_ratings r on r.player_id = mp.player_id and r.pos = mp.pos
   where mp.fixture_id = p_fixture and mp.side = p_side and mp.status = 'on'
$$;

-- tática da IA conforme a diferença de força e o mando
create or replace function public.mgr_ai_tactics(p_diff numeric, p_home boolean)
returns jsonb language sql immutable as $$
  select jsonb_build_object(
    'mentality', case when p_diff > 7 then 1 when p_diff < -8 then -1 when not p_home and p_diff < -3 then -1 else 0 end,
    'pressing',  case when p_diff > 3 then 'high' when p_diff < -8 then 'low' else 'medium' end,
    'line',      case when p_diff > 5 then 'high' when p_diff < -7 then 'low' else 'medium' end,
    'tempo',     'normal',
    'build',     case when p_diff > 4 then 'short' when p_diff < -6 then 'direct' else 'mixed' end,
    'width',     'mixed',
    'manage',    'normal')
$$;

-- táticas padrão (valores válidos)
create or replace function public.mgr_tactics_clean(p_t jsonb)
returns jsonb language sql immutable as $$
  select jsonb_build_object(
    'mentality', greatest(-2, least(2, coalesce((p_t ->> 'mentality')::int, 0))),
    'pressing',  case when p_t ->> 'pressing' in ('low', 'medium', 'high') then p_t ->> 'pressing' else 'medium' end,
    'line',      case when p_t ->> 'line' in ('low', 'medium', 'high') then p_t ->> 'line' else 'medium' end,
    'tempo',     case when p_t ->> 'tempo' in ('slow', 'normal', 'fast') then p_t ->> 'tempo' else 'normal' end,
    'build',     case when p_t ->> 'build' in ('short', 'mixed', 'direct') then p_t ->> 'build' else 'mixed' end,
    'width',     case when p_t ->> 'width' in ('center', 'mixed', 'wide') then p_t ->> 'width' else 'mixed' end,
    'manage',    case when p_t ->> 'manage' in ('keep', 'normal', 'push') then p_t ->> 'manage' else 'normal' end)
$$;

-- registra um evento
create or replace function public.mgr_event(p_fixture bigint, p_minute int, p_side char, p_kind text,
                                            p_player text default null, p_player2 text default null, p_detail text default null)
returns void language plpgsql security definer set search_path = public as $$
declare v_seq int;
begin
  update public.mgr_matches set state = jsonb_set(state, '{seq}', to_jsonb(coalesce((state ->> 'seq')::int, 0) + 1))
   where fixture_id = p_fixture returning (state ->> 'seq')::int into v_seq;
  insert into public.mgr_match_events (fixture_id, seq, minute, side, kind, player_id, player2_id, detail)
  values (p_fixture, coalesce(v_seq, 1), p_minute, p_side, p_kind, p_player, p_player2, p_detail);
end;
$$;

-- Cria a partida (idempotente). p_user_side = 'h'/'a' quando o usuário comanda um dos lados.
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
begin
  if exists (select 1 from public.mgr_matches where fixture_id = p_fixture) then return; end if;
  select * into v_f from public.season_fixtures where id = p_fixture;
  select * into v_s from public.career_seasons where id = v_f.season_id;
  select rules into v_rules from public.sim_competitions where id = v_f.competition_id;
  v_neut := (v_f.stage = 'final');
  v_dec  := v_f.stage in ('r16', 'qf', 'sf', 'final') and (v_f.stage = 'final' or v_f.leg = 2);
  if v_dec and v_f.stage <> 'final' then
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
    'extra_time_rule', (v_f.stage = 'final' and coalesce((v_rules ->> 'final_extra_time')::boolean, false)),
    'et', false, 'comp', v_f.competition_id, 'stage', v_f.stage, 'day', v_s.day_no,
    'form', jsonb_build_array(round((0.93 + random() * 0.14)::numeric, 3), round((0.93 + random() * 0.14)::numeric, 3))));

  v_lh := case when p_user_side = 'h' then p_user_lineup
               else public.mgr_auto_lineup(p_career, v_f.home_club, public.mgr_ai_formation(p_career, v_f.home_club), v_f.competition_id, v_s.day_no) end;
  v_la := case when p_user_side = 'a' then p_user_lineup
               else public.mgr_auto_lineup(p_career, v_f.away_club, public.mgr_ai_formation(p_career, v_f.away_club), v_f.competition_id, v_s.day_no) end;
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

-- ---------------------------------------------------------------------
-- 4) Substituição (valida as regras)
-- ---------------------------------------------------------------------
create or replace function public.mgr_do_sub(p_fixture bigint, p_side char, p_out text, p_in text, p_minute int,
                                             p_new_window boolean, p_detail text default null)
returns text language plpgsql security definer set search_path = public as $$
declare
  v_m    public.mgr_matches;
  v_o    public.mgr_match_players;
  v_i    public.mgr_match_players;
  v_used int;
  v_win  int;
begin
  select * into v_m from public.mgr_matches where fixture_id = p_fixture;
  v_used := (v_m.state -> 'subs' -> p_side ->> 'used')::int;
  v_win  := (v_m.state -> 'subs' -> p_side ->> 'windows')::int;
  if v_used >= (v_m.state ->> 'max_subs')::int then return 'Limite de substituições atingido.'; end if;
  if p_new_window and p_minute not in (45, 90) and v_win >= (v_m.state ->> 'max_windows')::int then
    return 'Você já usou todas as paradas para substituição.';
  end if;
  select * into v_o from public.mgr_match_players where fixture_id = p_fixture and player_id = p_out and side = p_side;
  select * into v_i from public.mgr_match_players where fixture_id = p_fixture and player_id = p_in and side = p_side;
  if v_o.player_id is null or v_o.status not in ('on', 'injured_off') then return 'Quem sai precisa estar em campo.'; end if;
  if v_o.status = 'injured_off' and v_o.slot is null then return 'Esse jogador já foi substituído.'; end if;
  if v_i.player_id is null or v_i.status <> 'bench' then return 'Quem entra precisa estar no banco (e não pode ter jogado).'; end if;

  update public.mgr_match_players
     set status = case when status = 'injured_off' then 'injured_off' else 'off' end, left_min = coalesce(left_min, p_minute), slot = null
   where fixture_id = p_fixture and player_id = p_out;
  update public.mgr_match_players
     set status = 'on', slot = v_o.slot, pos = v_o.pos, fit = public.mgr_fit(p_in, v_o.pos), entered_min = p_minute
   where fixture_id = p_fixture and player_id = p_in;
  update public.mgr_matches
     set state = jsonb_set(jsonb_set(state, array['subs', p_side, 'used'], to_jsonb(v_used + 1)),
                           array['subs', p_side, 'windows'], to_jsonb(v_win + case when p_new_window and p_minute not in (45, 90) then 1 else 0 end))
   where fixture_id = p_fixture;
  perform public.mgr_event(p_fixture, p_minute, p_side, 'sub', p_in, p_out, p_detail);
  return null;
end;
$$;

-- melhor reserva para uma vaga
create or replace function public.mgr_best_bench(p_fixture bigint, p_side char, p_pos text)
returns text language sql stable as $$
  select mp.player_id
    from public.mgr_match_players mp
    join public.sim_player_pos_ratings r on r.player_id = mp.player_id and r.pos = p_pos
   where mp.fixture_id = p_fixture and mp.side = p_side and mp.status = 'bench'
   order by r.eff * public.mgr_cond_factor(mp.cond) desc
   limit 1
$$;

-- O "auxiliar"/IA mexe no time: substituições por cansaço/lesão/cartão e ajuste de postura pelo placar
create or replace function public.mgr_ai_manage(p_fixture bigint, p_side char, p_minute int)
returns int language plpgsql security definer set search_path = public as $$
declare
  v_m     public.mgr_matches;
  v_my    int;
  v_opp   int;
  v_base  int;
  v_ment  int;
  r       record;
  v_in    text;
  v_n     int := 0;
  v_first boolean := true;
  v_max   int := case when p_minute >= 75 then 3 else 2 end;
begin
  select * into v_m from public.mgr_matches where fixture_id = p_fixture;
  v_my  := (v_m.state -> 'score' ->> (case when p_side = 'h' then 0 else 1 end))::int
         + (v_m.state -> 'agg' ->> (case when p_side = 'h' then 0 else 1 end))::int;
  v_opp := (v_m.state -> 'score' ->> (case when p_side = 'h' then 1 else 0 end))::int
         + (v_m.state -> 'agg' ->> (case when p_side = 'h' then 1 else 0 end))::int;
  v_base := (v_m.state -> 'base_mentality' ->> (case when p_side = 'h' then 0 else 1 end))::int;

  -- postura
  v_ment := v_base;
  if v_my < v_opp and p_minute >= 60 then v_ment := least(2, v_base + case when v_opp - v_my >= 2 or p_minute >= 75 then 2 else 1 end);
  elsif v_my > v_opp and p_minute >= 75 then v_ment := greatest(-2, v_base - 1);
  end if;
  if v_ment <> coalesce((v_m.state -> 'tactics' -> p_side ->> 'mentality')::int, 0) then
    update public.mgr_matches set state = jsonb_set(state, array['tactics', p_side, 'mentality'], to_jsonb(v_ment)) where fixture_id = p_fixture;
  end if;

  -- substituições (lesionados primeiro, depois os mais cansados / pendurados)
  for r in
    select mp.player_id, mp.pos, mp.status
      from public.mgr_match_players mp
     where mp.fixture_id = p_fixture and mp.side = p_side
       and ((mp.status = 'injured_off' and mp.slot is not null)
            or (mp.status = 'on' and mp.pos <> 'GOL' and p_minute >= 45
                and (mp.cond < 66 or (mp.yellow > 0 and mp.pos in ('ZAG', 'LD', 'LE', 'VOL') and p_minute >= 55)
                     or (p_minute >= 70 and mp.cond < 74 and v_my <> v_opp))))
     order by (mp.status = 'injured_off') desc, mp.cond
  loop
    exit when v_n >= v_max and r.status <> 'injured_off';
    v_in := public.mgr_best_bench(p_fixture, p_side,
              case when v_my < v_opp and p_minute >= 70 and r.pos in ('VOL', 'ZAG') and v_ment >= 1 then 'ATA' else r.pos end);
    exit when v_in is null;
    exit when public.mgr_do_sub(p_fixture, p_side, r.player_id, v_in, p_minute, v_first) is not null;
    v_first := false;
    v_n := v_n + 1;
  end loop;
  return v_n;
end;
$$;

-- ---------------------------------------------------------------------
-- 5) O MOTOR: simula do minuto atual até p_to.
--    p_interactive = lado do usuário (pausa em lesão/expulsão dele) ou null (IA cuida dos dois)
--    Devolve o motivo da parada: 'ht' | 'ft' | 'et_ht' | 'injury' | 'red' | 'segment'
-- ---------------------------------------------------------------------
create or replace function public.mgr_engine_run(p_fixture bigint, p_to int, p_interactive char)
returns text language plpgsql security definer set search_path = public as $$
declare
  v_m      public.mgr_matches;
  v_p      public.mgr_ep[];
  v_n      int;
  v_min    int;
  v_end    int;
  v_stop   text := 'segment';
  i        int;
  j        int;
  s        int;
  d        int;
  v_e      float8;
  v_att    float8[];
  v_def    float8[];
  v_ctl    float8[];
  v_gkr    float8[];
  v_gki    int[];
  v_defav  float8[];
  v_paceav float8[];
  v_non    int[];
  v_tac    jsonb;
  v_ment   int[];
  v_amult  float8[];
  v_dmult  float8[];
  v_freq   float8[];
  v_qual   float8[];
  v_drainm float8[];
  v_foulm  float8[];
  v_offm   float8[];
  v_hdr    float8[];
  v_sc     int[];
  v_agg    int[];
  v_poss   int[];
  v_corn   int[];
  v_offs   int[];
  v_ph     float8;
  v_r      float8;
  v_pa     float8;
  v_q      float8;
  v_w      float8[];
  v_k      int;
  v_a      int;
  v_gkidx  int;
  v_head   boolean;
  v_reload boolean;
  v_neut   boolean;
  v_et     boolean;
  v_side   char;
  v_oside  char;
  v_dsec   char;
  v_inj_stop boolean;
  v_lead   int;
  v_detail text;
  v_form   float8[];
  v_tpress text[];
  v_tline  text[];
  v_ttempo text[];
  v_tbuild text[];
  v_tmanage text[];
  v_tment  int[];
  v_ctlm   float8[];
  v_dws    float8[];
  v_dirty  boolean := true;
begin
  select * into v_m from public.mgr_matches where fixture_id = p_fixture for update;
  if v_m.status <> 'live' then return 'ft'; end if;
  v_form := array[coalesce((v_m.state -> 'form' ->> 0)::numeric, 1), coalesce((v_m.state -> 'form' ->> 1)::numeric, 1)];
  v_min := v_m.minute;
  v_et  := coalesce((v_m.state ->> 'et')::boolean, false);
  v_end := least(p_to, case when v_et then 120 else 90 end);
  v_neut := coalesce((v_m.state ->> 'neutral')::boolean, false);
  v_poss := array[(v_m.state -> 'poss' ->> 0)::int, (v_m.state -> 'poss' ->> 1)::int];
  v_corn := array[(v_m.state -> 'corners' ->> 0)::int, (v_m.state -> 'corners' ->> 1)::int];
  v_offs := array[(v_m.state -> 'offsides' ->> 0)::int, (v_m.state -> 'offsides' ->> 1)::int];
  v_sc   := array[(v_m.state -> 'score' ->> 0)::int, (v_m.state -> 'score' ->> 1)::int];
  v_agg  := array[(v_m.state -> 'agg' ->> 0)::int, (v_m.state -> 'agg' ->> 1)::int];
  v_reload := true;

  while v_min < v_end loop
    v_min := v_min + 1;

    -- a IA (e o auxiliar, no modo automático) mexe nos intervalos e marcos do jogo
    if v_min in (46, 61, 71, 81, 91, 106) then
      if v_p is not null then   -- grava antes: a IA decide olhando a condição e o placar atuais
        update public.mgr_match_players m
           set cond = round(x.cond::numeric, 2), goals = x.goals, assists = x.assists, shots = x.shots, sot = x.sot, saves = x.saves,
               fouls = x.fouls, yellow = x.yel, red = x.red,
               minutes = greatest(0, coalesce(m.left_min, v_min) - coalesce(m.entered_min, 0))
          from unnest(v_p) x where m.fixture_id = p_fixture and m.player_id = x.pid;
        update public.mgr_matches
           set state = state || jsonb_build_object('score', to_jsonb(v_sc), 'poss', to_jsonb(v_poss), 'corners', to_jsonb(v_corn), 'offsides', to_jsonb(v_offs))
         where fixture_id = p_fixture;
        v_p := null;
      end if;
      if p_interactive is distinct from 'h' then perform public.mgr_ai_manage(p_fixture, 'h', v_min - 1); end if;
      if p_interactive is distinct from 'a' then perform public.mgr_ai_manage(p_fixture, 'a', v_min - 1); end if;
      v_reload := true;
    end if;

    if v_reload then
      if v_p is not null then
        update public.mgr_match_players m
           set cond = round(x.cond::numeric, 2), goals = x.goals, assists = x.assists, shots = x.shots, sot = x.sot, saves = x.saves,
               fouls = x.fouls, yellow = x.yel, red = x.red,
               minutes = greatest(0, coalesce(m.left_min, v_min) - coalesce(m.entered_min, 0))
          from unnest(v_p) x where m.fixture_id = p_fixture and m.player_id = x.pid;
      end if;
      select * into v_m from public.mgr_matches where fixture_id = p_fixture;
      select array_agg(row(mp.player_id, case when mp.side = 'h' then 1 else 2 end, mp.slot, mp.pos,
                           sp.w_att::float8, sp.w_def::float8, sp.w_ctl::float8, sp.drain::float8,
                           mp.c_att::float8, mp.c_cre::float8, mp.c_def::float8, mp.c_ctl::float8, mp.c_gk::float8, mp.c_fin::float8,
                           mp.c_head::float8, mp.c_pace::float8, mp.c_stam::float8, mp.c_tack::float8, mp.c_str::float8,
                           mp.fit::float8, mp.cond::float8, mp.rhythm::float8, mp.goals, mp.assists, mp.shots, mp.sot, mp.saves, mp.fouls, mp.yellow, mp.red,
                           false, true, mp.minutes)::public.mgr_ep order by mp.side, mp.slot)
        into v_p
        from public.mgr_match_players mp join public.sim_positions sp on sp.code = mp.pos
       where mp.fixture_id = p_fixture and mp.status = 'on';
      v_n := coalesce(array_length(v_p, 1), 0);
      v_tac := v_m.state -> 'tactics';
      v_reload := false;
      v_dirty := true;
      -- parâmetros táticos fixos até a próxima mudança
      v_tpress := array[v_tac -> 'h' ->> 'pressing', v_tac -> 'a' ->> 'pressing'];
      v_tline  := array[v_tac -> 'h' ->> 'line', v_tac -> 'a' ->> 'line'];
      v_ttempo := array[v_tac -> 'h' ->> 'tempo', v_tac -> 'a' ->> 'tempo'];
      v_tbuild := array[v_tac -> 'h' ->> 'build', v_tac -> 'a' ->> 'build'];
      v_tmanage := array[v_tac -> 'h' ->> 'manage', v_tac -> 'a' ->> 'manage'];
      v_tment  := array[coalesce((v_tac -> 'h' ->> 'mentality')::int, 0), coalesce((v_tac -> 'a' ->> 'mentality')::int, 0)];
      v_freq := array[1, 1]; v_qual := array[0, 0]; v_drainm := array[1, 1]; v_foulm := array[1, 1]; v_offm := array[1, 1];
      v_hdr := array[0.2, 0.2]; v_ctlm := array[1, 1];
      for s in 1 .. 2 loop
        d := 3 - s;
        if v_tpress[s] = 'high' then v_freq[s] := v_freq[s] * 1.06; v_drainm[s] := 1.30; v_foulm[s] := 1.25; v_ctlm[d] := v_ctlm[d] * 0.93;
        elsif v_tpress[s] = 'low' then v_drainm[s] := 0.85; v_foulm[s] := 0.85; v_ctlm[d] := v_ctlm[d] * 1.04; end if;
        if v_ttempo[s] = 'fast' then v_freq[s] := v_freq[s] * 1.10; v_drainm[s] := v_drainm[s] * 1.18; v_ctlm[s] := v_ctlm[s] * 0.97;
        elsif v_ttempo[s] = 'slow' then v_freq[s] := v_freq[s] * 0.90; v_drainm[s] := v_drainm[s] * 0.90; v_ctlm[s] := v_ctlm[s] * 1.04; end if;
        if v_tbuild[s] = 'short' then v_freq[s] := v_freq[s] * 0.95; v_qual[s] := v_qual[s] + 0.04; v_ctlm[s] := v_ctlm[s] * 1.05;
        elsif v_tbuild[s] = 'direct' then v_freq[s] := v_freq[s] * 1.08; v_qual[s] := v_qual[s] - 0.03; v_offm[s] := 1.25; v_ctlm[s] := v_ctlm[s] * 0.94; end if;
        v_hdr[s] := case v_tac -> (case when s = 1 then 'h' else 'a' end) ->> 'width' when 'wide' then 0.30 when 'center' then 0.10 else 0.20 end;
        if v_hdr[s] = 0.10 then v_qual[s] := v_qual[s] + 0.02; end if;
        -- linha defensiva do ADVERSÁRIO muda a frequência de ataque e os impedimentos
        if v_tline[d] = 'high' then v_freq[s] := v_freq[s] * 0.95; v_offm[s] := v_offm[s] * 1.7;
        elsif v_tline[d] = 'low' then v_freq[s] := v_freq[s] * 1.06; v_offm[s] := v_offm[s] * 0.6; end if;
      end loop;
      if not v_neut then v_ctlm[1] := v_ctlm[1] * 1.05; end if;
    end if;

    -- ---- força dos times (recalculada a cada 3 minutos ou quando alguém sai/entra) ----
    if v_dirty or v_min % 3 = 1 then
      v_dirty := false;
      v_att := array[0, 0]; v_def := array[0, 0]; v_ctl := array[0, 0]; v_gkr := array[30, 30]; v_gki := array[0, 0];
      v_defav := array[0, 0]; v_paceav := array[0, 0]; v_non := array[0, 0]; v_dws := array[0, 0];
      for i in 1 .. v_n loop
        continue when not v_p[i].on_field;
        s := v_p[i].sd;
        v_e := v_p[i].fit * (0.70 + 0.003 * v_p[i].cond) * (case when v_p[i].cond < 50 then 0.88 + 0.0024 * v_p[i].cond else 1 end)
               * (0.94 + 0.0006 * v_p[i].rhy);
        v_att[s] := v_att[s] + v_p[i].aw * (0.62 * v_p[i].att + 0.38 * v_p[i].cre) * v_e;
        v_def[s] := v_def[s] + v_p[i].dw * v_p[i].def * v_e;
        v_ctl[s] := v_ctl[s] + v_p[i].cw * v_p[i].ctl * v_e;
        v_non[s] := v_non[s] + 1;
        if v_p[i].pos = 'GOL' then v_gkr[s] := v_p[i].gk * v_e; v_gki[s] := i;
        else
          v_defav[s] := v_defav[s] + v_p[i].dw * v_p[i].def;
          v_paceav[s] := v_paceav[s] + v_p[i].dw * v_p[i].pace;
          v_dws[s] := v_dws[s] + v_p[i].dw;
        end if;
      end loop;
      for s in 1 .. 2 loop
        v_defav[s] := case when v_dws[s] > 0 then v_defav[s] / v_dws[s] else 40 end;
        v_paceav[s] := case when v_dws[s] > 0 then v_paceav[s] / v_dws[s] else 50 end;
      end loop;
    end if;

    -- ---- postura (muda com o placar conforme a "gestão do jogo") ----
    for s in 1 .. 2 loop
      d := 3 - s;
      v_ment[s] := v_tment[s];
      v_lead := (v_sc[s] + v_agg[s]) - (v_sc[d] + v_agg[d]);
      if v_tmanage[s] = 'keep' and v_lead > 0 and v_min >= 70 then v_ment[s] := greatest(-2, v_ment[s] - 1); end if;
      if v_tmanage[s] = 'push' and v_lead <= 0 and v_min >= 60 then v_ment[s] := least(2, v_ment[s] + 1); end if;
      v_amult[s] := (array[0.80, 0.90, 1.00, 1.10, 1.20])[v_ment[s] + 3];
      v_dmult[s] := (array[1.15, 1.07, 1.00, 0.94, 0.86])[v_ment[s] + 3] * case when v_tpress[s] = 'low' then 1.03 else 1 end;
    end loop;

    -- ---- posse ----
    v_r := v_ctl[1] * v_ctlm[1];
    v_q := v_ctl[2] * v_ctlm[2];
    v_ph := greatest(0.25, least(0.75, 0.5 + 1.4 * (v_r / greatest(v_r + v_q, 1) - 0.5)));
    s := case when random() < v_ph then 1 else 2 end;
    d := 3 - s;
    v_side := case when s = 1 then 'h' else 'a' end;
    v_oside := case when d = 1 then 'h' else 'a' end;
    v_poss[s] := v_poss[s] + 1;

    -- ---- jogada de ataque? ----
    v_pa := 0.335 * power(greatest(v_att[s] * v_amult[s] * v_form[s] * (case when v_neut then 1 when s = 1 then 1.16 else 0.96 end), 1)
                          / greatest(v_def[d] * v_dmult[d] * v_form[d], 1) / 0.86, 0.7)
                  * v_freq[s];
    v_pa := greatest(0.05, least(0.62, v_pa));

    if random() < v_pa then
      v_r := random();
      if v_r < 0.07 * v_offm[s] then
        -- impedimento
        v_offs[s] := v_offs[s] + 1;
        if p_interactive is not null then
          v_w := '{}';
          for i in 1 .. v_n loop v_w := v_w || case when v_p[i].on_field and v_p[i].sd = s then v_p[i].aw * v_p[i].pace else 0 end; end loop;
          v_k := public.mgr_pick(v_w);
          if v_k > 0 then perform public.mgr_event(p_fixture, v_min, v_side, 'offside', v_p[v_k].pid); end if;
        end if;
      elsif v_r < 0.07 + 0.10 then
        -- falta do defensor na jogada (pode virar pênalti ou cartão)
        v_w := '{}';
        for i in 1 .. v_n loop
          v_w := v_w || case when v_p[i].on_field and v_p[i].sd = d and v_p[i].pos <> 'GOL' then v_p[i].dw * (1 + (100 - v_p[i].tack) / 100) else 0 end;
        end loop;
        v_k := public.mgr_pick(v_w);
        if v_k > 0 then
          v_p[v_k].fouls := v_p[v_k].fouls + 1;
          if random() < 0.28 * (case when v_p[v_k].yel > 0 then 0.5 else 1 end) then   -- cartão por falta tática
            if v_p[v_k].yel >= 1 then
              v_p[v_k].red := 1; v_p[v_k].on_field := false; v_dirty := true;
              perform public.mgr_event(p_fixture, v_min, v_oside, 'second_yellow', v_p[v_k].pid);
              update public.mgr_match_players set status = 'sent_off', left_min = v_min, slot = null where fixture_id = p_fixture and player_id = v_p[v_k].pid;
              if p_interactive = v_oside then v_stop := 'red'; end if;
            else
              v_p[v_k].yel := 1;
              perform public.mgr_event(p_fixture, v_min, v_oside, 'yellow', v_p[v_k].pid);
            end if;
          end if;
          if random() < 0.11 then                                         -- pênalti
            v_a := 0; v_e := -1;
            for i in 1 .. v_n loop
              if v_p[i].on_field and v_p[i].sd = s and v_p[i].pos <> 'GOL' and v_p[i].fin > v_e then v_e := v_p[i].fin; v_a := i; end if;
            end loop;
            if v_a > 0 then
              v_p[v_a].shots := v_p[v_a].shots + 1;
              v_gkidx := v_gki[d];
              if random() < greatest(0.55, least(0.88, 0.70 + 0.004 * (v_p[v_a].fin - v_gkr[d]))) then
                v_p[v_a].sot := v_p[v_a].sot + 1; v_p[v_a].goals := v_p[v_a].goals + 1; v_sc[s] := v_sc[s] + 1;
                perform public.mgr_event(p_fixture, v_min, v_side, 'pen_goal', v_p[v_a].pid);
              else
                if random() < 0.6 and v_gkidx > 0 then
                  v_p[v_a].sot := v_p[v_a].sot + 1; v_p[v_gkidx].saves := v_p[v_gkidx].saves + 1;
                  perform public.mgr_event(p_fixture, v_min, v_side, 'pen_miss', v_p[v_a].pid, v_p[v_gkidx].pid, 'defendido');
                else
                  perform public.mgr_event(p_fixture, v_min, v_side, 'pen_miss', v_p[v_a].pid, null, 'para fora');
                end if;
              end if;
            end if;
          end if;
        end if;
      elsif v_r < 0.17 + 0.12 then
        if random() < 0.45 then v_corn[s] := v_corn[s] + 1; end if;  -- cruzamento cortado / jogada desarmada
      else
        -- ---- finalização ----
        v_head := random() < v_hdr[s];
        v_w := '{}';
        for i in 1 .. v_n loop
          v_w := v_w || case when v_p[i].on_field and v_p[i].sd = s and v_p[i].pos <> 'GOL' then
                   case when v_head then (v_p[i].aw + 0.25) * power(v_p[i].head / 60, 3)
                        else power(v_p[i].aw + 0.05, 1.6) * power(v_p[i].fin / 60, 2) * (0.70 + 0.003 * v_p[i].cond) end
                 else 0 end;
        end loop;
        v_k := public.mgr_pick(v_w);
        if v_k > 0 then
          v_p[v_k].shots := v_p[v_k].shots + 1;
          v_q := 0.30 + 0.004 * ((case when v_head then v_p[v_k].head else v_p[v_k].att end) - v_defav[d])
                 + case when s = 1 and not v_neut then 0.02 else 0 end
                 + v_qual[s] + random() * 0.35
                 + case v_tline[d] when 'high' then 0.003 * (v_p[v_k].pace - v_paceav[d]) when 'low' then -0.04 else 0 end
                 - case when v_head then 0.08 else 0 end;
          v_q := greatest(0.05, least(0.95, v_q * v_p[v_k].fit));
          v_gkidx := v_gki[d];
          v_r := random();
          if v_r < 0.20 then
            -- bloqueada
            if random() < 0.60 then v_corn[s] := v_corn[s] + 1; end if;
            if p_interactive is not null then perform public.mgr_event(p_fixture, v_min, v_side, 'shot_off', v_p[v_k].pid, null, 'bloqueado'); end if;
          elsif random() < greatest(0.10, least(0.75, 0.24 + 0.32 * v_q + 0.0035 * (v_p[v_k].fin - 65))) then
            v_p[v_k].sot := v_p[v_k].sot + 1;
            if random() < greatest(0.05, least(0.70, 0.09 + 0.38 * v_q + 0.003 * (v_p[v_k].fin - v_gkr[d]))) then
              -- GOL
              v_p[v_k].goals := v_p[v_k].goals + 1;
              v_sc[s] := v_sc[s] + 1;
              v_a := 0;
              if random() < 0.78 then
                v_w := '{}';
                for i in 1 .. v_n loop
                  v_w := v_w || case when v_p[i].on_field and v_p[i].sd = s and i <> v_k and v_p[i].pos <> 'GOL'
                                     then (v_p[i].aw + 0.6 * v_p[i].cw) * power(v_p[i].cre / 60, 2) else 0 end;
                end loop;
                v_a := public.mgr_pick(v_w);
                if v_a > 0 then v_p[v_a].assists := v_p[v_a].assists + 1; end if;
              end if;
              perform public.mgr_event(p_fixture, v_min, v_side, 'goal', v_p[v_k].pid,
                                       case when v_a > 0 then v_p[v_a].pid end, case when v_head then 'de cabeça' end);
            else
              if v_gkidx > 0 then v_p[v_gkidx].saves := v_p[v_gkidx].saves + 1; end if;
              if random() < 0.40 then v_corn[s] := v_corn[s] + 1; end if;
              if p_interactive is not null or v_q > 0.62 then
                perform public.mgr_event(p_fixture, v_min, v_side, 'save', v_p[v_k].pid,
                                         case when v_gkidx > 0 then v_p[v_gkidx].pid end, case when v_q > 0.62 then 'grande chance' end);
              end if;
            end if;
          else
            if random() < 0.18 then v_corn[s] := v_corn[s] + 1; end if;
            if p_interactive is not null then
              perform public.mgr_event(p_fixture, v_min, v_side, 'shot_off', v_p[v_k].pid, null, case when v_q > 0.62 then 'grande chance' end);
            end if;
          end if;
        end if;
      end if;
    end if;

    -- ---- faltas no meio-campo e cartões (os dois times) ----
    for s in 1 .. 2 loop
      continue when random() >= 0.125 * v_foulm[s] * (case when v_min > 75 then 1.15 else 1 end);
      v_side := case when s = 1 then 'h' else 'a' end;
      v_w := '{}';
      for i in 1 .. v_n loop
        v_w := v_w || case when v_p[i].on_field and v_p[i].sd = s and v_p[i].pos <> 'GOL'
                           then (v_p[i].dw + 0.3) * (1 + (100 - v_p[i].tack) / 100) * case when v_p[i].yel > 0 then 0.45 else 1 end else 0 end;
      end loop;
      v_k := public.mgr_pick(v_w);
      continue when v_k = 0;
      v_p[v_k].fouls := v_p[v_k].fouls + 1;
      v_r := random();
      if v_r < 0.0018 then
        v_p[v_k].red := 1; v_p[v_k].on_field := false; v_dirty := true;
        perform public.mgr_event(p_fixture, v_min, v_side, 'red', v_p[v_k].pid);
        update public.mgr_match_players set status = 'sent_off', left_min = v_min, slot = null where fixture_id = p_fixture and player_id = v_p[v_k].pid;
        if p_interactive = v_side then v_stop := 'red'; end if;
      elsif v_r < 0.0018 + 0.165 * (1 + (60 - v_p[v_k].tack) / 100) * (case when v_p[v_k].yel > 0 then 0.55 else 1 end) * (case when v_tpress[s] = 'high' then 1.1 else 1 end) then
        if v_p[v_k].yel >= 1 then
          v_p[v_k].red := 1; v_p[v_k].on_field := false; v_dirty := true;
          perform public.mgr_event(p_fixture, v_min, v_side, 'second_yellow', v_p[v_k].pid);
          update public.mgr_match_players set status = 'sent_off', left_min = v_min, slot = null where fixture_id = p_fixture and player_id = v_p[v_k].pid;
          if p_interactive = v_side then v_stop := 'red'; end if;
        else
          v_p[v_k].yel := 1;
          perform public.mgr_event(p_fixture, v_min, v_side, 'yellow', v_p[v_k].pid);
        end if;
      end if;
    end loop;

    -- ---- desgaste, lesões e minutos jogados ----
    v_inj_stop := false;
    if v_min % 3 = 0 then
      for i in 1 .. v_n loop
        continue when not v_p[i].on_field;
        s := v_p[i].sd;
        v_side := case when s = 1 then 'h' else 'a' end;
        v_p[i].cond := greatest(0, v_p[i].cond - 3 * 0.21 * v_p[i].drain * (1.32 - v_p[i].stam / 100 * 0.62) * v_drainm[s]
                                   * case when v_et then 1.15 else 1 end);
        if random() < 3 * 0.00005 * (1 + greatest(0, 70 - v_p[i].cond) / 25) * (case when v_tpress[s] = 'high' then 1.15 else 1 end) then
          v_p[i].inj := true; v_p[i].on_field := false; v_dirty := true;
          perform public.mgr_event(p_fixture, v_min, v_side, 'injury', v_p[i].pid);
          update public.mgr_match_players set status = 'injured_off', injured = true, left_min = v_min where fixture_id = p_fixture and player_id = v_p[i].pid;
          if p_interactive = v_side then v_inj_stop := true;
          else
            -- a IA troca na hora (se ainda tiver substituição)
            v_detail := public.mgr_do_sub(p_fixture, v_side, v_p[i].pid, public.mgr_best_bench(p_fixture, v_side, v_p[i].pos), v_min, true);
            v_reload := true;
          end if;
        end if;
      end loop;
    end if;
    if v_inj_stop then v_stop := 'injury'; end if;

    if v_reload then  -- grava o estado antes de recarregar a lista de quem está em campo
      update public.mgr_matches
         set state = state || jsonb_build_object('score', to_jsonb(v_sc), 'poss', to_jsonb(v_poss), 'corners', to_jsonb(v_corn), 'offsides', to_jsonb(v_offs))
       where fixture_id = p_fixture;
    end if;

    exit when v_stop in ('red', 'injury');
    if v_min = 45 and not v_et then v_stop := 'ht'; exit; end if;
    if v_min = 105 and v_et then v_stop := 'et_ht'; exit; end if;
  end loop;

  -- grava tudo
  if v_p is not null then
    update public.mgr_match_players m
       set cond = round(x.cond::numeric, 2), goals = x.goals, assists = x.assists, shots = x.shots, sot = x.sot, saves = x.saves,
           fouls = x.fouls, yellow = x.yel, red = x.red,
           minutes = greatest(0, coalesce(m.left_min, v_min) - coalesce(m.entered_min, 0))
      from unnest(v_p) x where m.fixture_id = p_fixture and m.player_id = x.pid;
  end if;
  update public.mgr_matches
     set minute = v_min, updated_at = now(),
         state = state || jsonb_build_object('score', to_jsonb(v_sc), 'poss', to_jsonb(v_poss), 'corners', to_jsonb(v_corn), 'offsides', to_jsonb(v_offs))
   where fixture_id = p_fixture;

  if v_min >= (case when v_et then 120 else 90 end) then v_stop := 'ft'; end if;
  if v_stop = 'segment' and v_min = 45 then v_stop := 'ht'; end if;
  return v_stop;
end;
$$;

-- ---------------------------------------------------------------------
-- 6) Notas dos jogadores (calculadas dos números da própria partida)
-- ---------------------------------------------------------------------
create or replace function public.mgr_rate(p_fixture bigint, p_final boolean default false)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_m  public.mgr_matches;
  v_h  int;
  v_a  int;
begin
  select * into v_m from public.mgr_matches where fixture_id = p_fixture;
  v_h := (v_m.state -> 'score' ->> 0)::int;
  v_a := (v_m.state -> 'score' ->> 1)::int;
  update public.mgr_match_players mp
     set rating = round(greatest(3.0, least(10.0,
           6.0 + 1.05 * mp.goals + 0.55 * mp.assists + 0.10 * mp.sot + 0.03 * mp.shots
           - 0.35 * mp.yellow - 1.6 * mp.red
           + case when mp.pos = 'GOL' then 0.22 * mp.saves - 0.30 * x.conceded + case when x.conceded = 0 and mp.minutes >= 60 then 0.6 else 0 end
                  when mp.pos in ('ZAG', 'LD', 'LE') then -0.12 * x.conceded + case when x.conceded = 0 and mp.minutes >= 60 then 0.35 else 0 end
                  when mp.pos = 'VOL' then -0.06 * x.conceded + case when x.conceded = 0 and mp.minutes >= 60 then 0.15 else 0 end
                  else case when x.scored = 0 and mp.pos in ('ATA', 'PD', 'PE', 'MEI') then -0.25 else 0 end end
           + case when x.scored > x.conceded then 0.25 when x.scored < x.conceded then -0.25 else 0 end
           + (mp.fit - 0.92) * 2.5 + (public.mgr_cond_factor(mp.cond) - 0.9)
           + case when p_final and mp.minutes >= 20 then (random() - 0.5) * 0.7 else 0 end
         ))::numeric, 1)
    from (select s.side,
                 case when s.side = 'h' then v_h else v_a end as scored,
                 case when s.side = 'h' then v_a else v_h end as conceded
            from (values ('h'::char), ('a'::char)) s(side)) x
   where mp.fixture_id = p_fixture and mp.side = x.side and mp.minutes > 0;
end;
$$;

-- ---------------------------------------------------------------------
-- 7) Pênaltis (disputa) — eventos so_goal / so_miss
-- ---------------------------------------------------------------------
create or replace function public.mgr_shootout(p_fixture bigint, p_minute int)
returns int[] language plpgsql security definer set search_path = public as $$
declare
  v_tk_h text[];
  v_tk_a text[];
  v_fin  jsonb;
  v_gk   numeric[] := array[60, 60];
  v_gkp  text[] := array[null, null];
  v_sc   int[] := array[0, 0];
  v_k    int := 0;
  v_s    int;
  v_pid  text;
  v_n    int;
  v_done boolean := false;
  v_g1   numeric;
  v_g2   numeric;
  v_p1   text;
  v_p2   text;
begin
  select array_agg(player_id order by c_fin desc) into v_tk_h from public.mgr_match_players
   where fixture_id = p_fixture and side = 'h' and status = 'on' and pos <> 'GOL';
  select array_agg(player_id order by c_fin desc) into v_tk_a from public.mgr_match_players
   where fixture_id = p_fixture and side = 'a' and status = 'on' and pos <> 'GOL';
  select jsonb_object_agg(player_id, c_fin) into v_fin from public.mgr_match_players where fixture_id = p_fixture;
  select coalesce(max(c_gk) filter (where side = 'h' and pos = 'GOL' and status = 'on'), 45),
         coalesce(max(c_gk) filter (where side = 'a' and pos = 'GOL' and status = 'on'), 45)
    into v_g1, v_g2 from public.mgr_match_players where fixture_id = p_fixture;
  v_gk := array[v_g1, v_g2];
  select max(player_id) filter (where side = 'h' and pos = 'GOL' and status = 'on'),
         max(player_id) filter (where side = 'a' and pos = 'GOL' and status = 'on')
    into v_p1, v_p2 from public.mgr_match_players where fixture_id = p_fixture;
  v_gkp := array[v_p1, v_p2];
  if v_tk_h is null then v_tk_h := array[v_gkp[1]]; end if;
  if v_tk_a is null then v_tk_a := array[v_gkp[2]]; end if;

  while not v_done and v_k < 30 loop
    v_k := v_k + 1;
    for v_s in 1 .. 2 loop
      if v_s = 1 then v_n := array_length(v_tk_h, 1); v_pid := v_tk_h[1 + (v_k - 1) % v_n];
      else v_n := array_length(v_tk_a, 1); v_pid := v_tk_a[1 + (v_k - 1) % v_n]; end if;
      if random() < greatest(0.55, least(0.9, 0.74 + 0.004 * (coalesce((v_fin ->> v_pid)::numeric, 50) - v_gk[3 - v_s]))) then
        v_sc[v_s] := v_sc[v_s] + 1;
        perform public.mgr_event(p_fixture, p_minute, case when v_s = 1 then 'h' else 'a' end, 'so_goal', v_pid);
      else
        perform public.mgr_event(p_fixture, p_minute, case when v_s = 1 then 'h' else 'a' end, 'so_miss', v_pid, v_gkp[3 - v_s]);
      end if;
      -- decidido nas 5 primeiras?
      if v_k <= 5 then
        if v_sc[1] > v_sc[2] + (5 - v_k) + (case when v_s = 1 then 1 else 0 end)
           or v_sc[2] > v_sc[1] + (5 - v_k) then v_done := true; exit; end if;
      end if;
    end loop;
    if v_k >= 5 and v_sc[1] <> v_sc[2] then v_done := true; end if;
  end loop;
  return v_sc;
end;
$$;

-- ---------------------------------------------------------------------
-- 8) Apito final: placar no calendário, prorrogação/pênaltis, súmula, estatísticas e estado dos jogadores
--    (NÃO mexe na carreira do treinador — isso fica em 04_career.sql)
-- ---------------------------------------------------------------------
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
    if v_aggh = v_agga then
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

-- ---------------------------------------------------------------------
-- 9) Partida inteira da IA (rodadas, campeonatos paralelos)
-- ---------------------------------------------------------------------
create or replace function public.mgr_sim_fixture(p_fixture bigint, p_career uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_stop text;
begin
  perform public.mgr_match_create(p_fixture, p_career, null, null);
  v_stop := public.mgr_engine_run(p_fixture, 45, null);
  v_stop := public.mgr_engine_run(p_fixture, 90, null);
  if v_stop = 'ft' and public.mgr_needs_extra_time(p_fixture) then
    update public.mgr_matches set state = jsonb_set(state, '{et}', 'true'::jsonb) where fixture_id = p_fixture;
    v_stop := public.mgr_engine_run(p_fixture, 105, null);
    v_stop := public.mgr_engine_run(p_fixture, 120, null);
  end if;
  perform public.mgr_match_finish(p_fixture);
end;
$$;

-- precisa de prorrogação? (final em jogo único empatada, se o regulamento manda)
create or replace function public.mgr_needs_extra_time(p_fixture bigint)
returns boolean language sql stable as $$
  select coalesce((m.state ->> 'extra_time_rule')::boolean, false)
     and not coalesce((m.state ->> 'et')::boolean, false)
     and (m.state -> 'score' ->> 0)::int + (m.state -> 'agg' ->> 0)::int = (m.state -> 'score' ->> 1)::int + (m.state -> 'agg' ->> 1)::int
    from public.mgr_matches m where m.fixture_id = p_fixture
$$;
