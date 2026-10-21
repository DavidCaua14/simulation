-- =====================================================================
-- MODO TEMPORADAS — 3/3: MOTOR DA SIMULAÇÃO (funções do banco)
-- Toda a simulação roda AQUI, no servidor: o app não consegue "escolher" o resultado.
-- Funções que o app chama:  season_hub, season_play, season_start_next,
--                           season_offer_respond, season_standings, refresh_wallet,
--                           choose_initial_club
-- Funções "sim_*" são internas (o app não consegue chamá-las).
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1) SORTEIOS E PLACARES
-- ---------------------------------------------------------------------
-- Gols por Poisson (distribuição típica do futebol)
create or replace function public.sim_poisson(p_lambda double precision)
returns int language plpgsql volatile as $$
declare
  v_l double precision := exp(-p_lambda);
  v_k int := 0;
  v_p double precision := 1;
begin
  loop
    v_k := v_k + 1;
    v_p := v_p * random();
    exit when v_p <= v_l or v_k > 9;
  end loop;
  return v_k - 1;
end;
$$;

-- Placar: [gols_casa, gols_fora]. Quanto maior a diferença de força, maior a chance do favorito.
create or replace function public.sim_score(
  p_str_home int, p_str_away int, p_neutral boolean default false,
  p_boost_home double precision default 1, p_boost_away double precision default 1)
returns int[] language plpgsql volatile as $$
declare
  v_d  double precision := (p_str_home - p_str_away)::double precision;
  v_lh double precision;
  v_la double precision;
begin
  v_lh := (case when p_neutral then 1.25 else 1.40 end) * exp(0.022 * v_d)  * p_boost_home;
  v_la := (case when p_neutral then 1.25 else 1.05 end) * exp(-0.022 * v_d) * p_boost_away;
  return array[public.sim_poisson(v_lh), public.sim_poisson(v_la)];
end;
$$;

-- Todos contra todos (método do círculo). p_double = true -> ida e volta.
create or replace function public.sim_round_robin(p_teams text[], p_double boolean default true)
returns table (round_no int, home text, away text)
language plpgsql as $$
declare
  n   int  := array_length(p_teams, 1);
  arr text[] := p_teams;
  r   int;
  i   int;
  h   text;
  a   text;
begin
  for r in 1 .. n - 1 loop
    for i in 1 .. n / 2 loop
      if (r + i) % 2 = 1 then
        h := arr[i];         a := arr[n - i + 1];
      else
        h := arr[n - i + 1]; a := arr[i];
      end if;
      round_no := r; home := h; away := a; return next;
      if p_double then
        round_no := r + n - 1; home := a; away := h; return next;
      end if;
    end loop;
    arr := array[arr[1], arr[n]] || arr[2 : n - 1];   -- gira todos, menos o primeiro
  end loop;
end;
$$;

-- Vencedor nos pênaltis (o mais forte leva leve vantagem)
create or replace function public.sim_pens_winner(p_a text, p_b text)
returns text language plpgsql volatile as $$
declare v_sa int; v_sb int;
begin
  select strength into v_sa from public.sim_clubs where id = p_a;
  select strength into v_sb from public.sim_clubs where id = p_b;
  return case when random() < 1 / (1 + exp(-(v_sa - v_sb) / 25.0)) then p_a else p_b end;
end;
$$;

-- ---------------------------------------------------------------------
-- 2) TABELA DE CLASSIFICAÇÃO (liga e fase de grupos)
-- ---------------------------------------------------------------------
create or replace function public.sim_standings(p_season uuid, p_comp text, p_group text default null)
returns table (pos int, club_id text, played int, wins int, draws int, losses int, gf int, ga int, gd int, points int)
language sql stable as $$
  with x_members as (
    select cc.club_id as x_club
    from public.sim_competition_clubs cc
    where cc.competition_id = p_comp and (p_group is null or cc.group_label = p_group)
  ),
  x_res as (
    select f.home_club as x_c, f.home_goals as x_for, f.away_goals as x_against
    from public.season_fixtures f
    where f.season_id = p_season and f.competition_id = p_comp and f.status = 'played'
      and f.stage in ('league', 'group') and (p_group is null or f.group_label = p_group)
    union all
    select f.away_club, f.away_goals, f.home_goals
    from public.season_fixtures f
    where f.season_id = p_season and f.competition_id = p_comp and f.status = 'played'
      and f.stage in ('league', 'group') and (p_group is null or f.group_label = p_group)
  ),
  x_agg as (
    select m.x_club,
           count(r.x_c)::int                                   as x_p,
           (count(*) filter (where r.x_for > r.x_against))::int  as x_w,
           (count(*) filter (where r.x_for = r.x_against))::int  as x_d,
           (count(*) filter (where r.x_for < r.x_against))::int  as x_l,
           coalesce(sum(r.x_for), 0)::int                      as x_gf,
           coalesce(sum(r.x_against), 0)::int                  as x_ga
    from x_members m left join x_res r on r.x_c = m.x_club
    group by m.x_club
  )
  select (row_number() over (order by (a.x_w * 3 + a.x_d) desc, a.x_w desc, (a.x_gf - a.x_ga) desc, a.x_gf desc, a.x_club))::int as pos,
         a.x_club as club_id, a.x_p as played, a.x_w as wins, a.x_d as draws, a.x_l as losses,
         a.x_gf as gf, a.x_ga as ga, (a.x_gf - a.x_ga) as gd, (a.x_w * 3 + a.x_d) as points
  from x_agg a
  order by 1;
$$;

-- ---------------------------------------------------------------------
-- 3) CRIAÇÃO DA TEMPORADA (gera TODOS os jogos de liga, grupos e oitavas)
-- ---------------------------------------------------------------------
create or replace function public.sim_create_season(p_career uuid)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_club  text;
  v_no    int;
  v_id    uuid;
  v_teams text[];
  v_g     record;
  v_t     record;
  v_i     int;
begin
  select club_id into v_club from public.careers where id = p_career;
  if v_club is null then raise exception 'Escolha um clube antes de iniciar a temporada'; end if;

  select coalesce(max(season_no), 0) + 1 into v_no from public.career_seasons where career_id = p_career;
  insert into public.career_seasons (career_id, season_no, year, club_id)
  values (p_career, v_no, 2025 + v_no, v_club) returning id into v_id;

  insert into public.season_competitions (season_id, competition_id, stage) values
    (v_id, 'brasileirao', 'league'), (v_id, 'copa_brasil', 'r16'), (v_id, 'libertadores', 'group');

  -- Brasileirão: 38 rodadas (ida e volta), calendário embaralhado a cada temporada
  select array_agg(club_id order by random()) into v_teams
  from public.sim_competition_clubs where competition_id = 'brasileirao';
  insert into public.season_fixtures (season_id, competition_id, stage, round_no, home_club, away_club)
  select v_id, 'brasileirao', 'league', rr.round_no, rr.home, rr.away from public.sim_round_robin(v_teams, true) rr;

  -- Libertadores: 8 grupos de 4 (6 rodadas)
  for v_g in select distinct group_label from public.sim_competition_clubs where competition_id = 'libertadores' order by 1 loop
    select array_agg(club_id order by random()) into v_teams
    from public.sim_competition_clubs where competition_id = 'libertadores' and group_label = v_g.group_label;
    insert into public.season_fixtures (season_id, competition_id, stage, round_no, group_label, home_club, away_club)
    select v_id, 'libertadores', 'group', rr.round_no, v_g.group_label, rr.home, rr.away from public.sim_round_robin(v_teams, true) rr;
  end loop;

  -- Copa do Brasil: oitavas (ida e volta)
  for v_t in
    select group_label,
           max(club_id) filter (where seed = 1) as c1,
           max(club_id) filter (where seed = 2) as c2
    from public.sim_competition_clubs where competition_id = 'copa_brasil'
    group by group_label order by group_label
  loop
    v_i := substr(v_t.group_label, 2)::int;
    insert into public.season_fixtures (season_id, competition_id, stage, round_no, tie_no, leg, home_club, away_club) values
      (v_id, 'copa_brasil', 'r16', 1, v_i, 1, v_t.c1, v_t.c2),
      (v_id, 'copa_brasil', 'r16', 2, v_i, 2, v_t.c2, v_t.c1);
  end loop;

  insert into public.career_stats (career_id) values (p_career) on conflict do nothing;
  return v_id;
end;
$$;

-- ---------------------------------------------------------------------
-- 4) ENERGIA: trava a carreira e aplica a recarga (a cada 5h a energia livre volta a 10;
--    a energia BÔNUS (comprada) nunca é zerada pela recarga)
-- ---------------------------------------------------------------------
create or replace function public.sim_lock_career()
returns public.careers language plpgsql security definer set search_path = public as $$
declare
  v_c public.careers;
  v_k int;
begin
  select * into v_c from public.careers where user_id = auth.uid() and status = 'active' for update;
  if not found then raise exception 'Carreira ativa não encontrada'; end if;

  if now() >= v_c.energy_reset_at + interval '5 hours' then
    v_k := floor(extract(epoch from (now() - v_c.energy_reset_at)) / 18000)::int;   -- janelas de 5h completas
    update public.careers
       set energy = greatest(energy, 10),
           energy_reset_at = energy_reset_at + (v_k * interval '5 hours')
     where id = v_c.id
    returning * into v_c;
  end if;
  return v_c;
end;
$$;

-- Carteira atualizada (o topo do app chama isto): moedas, energia total e próxima recarga
create or replace function public.refresh_wallet()
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_c public.careers;
begin
  v_c := public.sim_lock_career();
  return jsonb_build_object(
    'coins', v_c.coins, 'energy', v_c.energy, 'bonus_energy', v_c.bonus_energy,
    'next_reset_at', v_c.energy_reset_at + interval '5 hours');
end;
$$;

-- ---------------------------------------------------------------------
-- 5) RODADAS, MATA-MATAS E FIM DE CAMPEONATO
-- ---------------------------------------------------------------------
-- Simula todos os jogos pendentes de uma rodada (os do usuário já vêm prontos)
create or replace function public.sim_play_round(p_season uuid, p_comp text, p_stage text, p_round int)
returns int language plpgsql security definer set search_path = public as $$
declare
  r      record;
  v_sc   int[];
  v_sh   int;
  v_sa   int;
  v_n    int := 0;
begin
  for r in
    select id, home_club, away_club from public.season_fixtures
    where season_id = p_season and competition_id = p_comp and stage = p_stage
      and round_no = p_round and status = 'pending'
    order by id
  loop
    select strength into v_sh from public.sim_clubs where id = r.home_club;
    select strength into v_sa from public.sim_clubs where id = r.away_club;
    v_sc := public.sim_score(v_sh, v_sa, p_stage = 'final');
    update public.season_fixtures
       set home_goals = v_sc[1], away_goals = v_sc[2], status = 'played', played_at = now()
     where id = r.id;
    v_n := v_n + 1;
  end loop;
  return v_n;
end;
$$;

-- Fecha as eliminatórias de uma fase: soma os dois jogos; empate vai para os pênaltis.
-- Devolve os classificados (na ordem dos confrontos).
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

    select coalesce(sum(case when home_club = v_c1 then home_goals else away_goals end), 0),
           coalesce(sum(case when home_club = v_c2 then home_goals else away_goals end), 0)
      into v_g1, v_g2
      from public.season_fixtures
     where season_id = p_season and competition_id = p_comp and stage = p_stage and tie_no = v_t.tie_no;

    select id, home_club into v_last, v_lasthome from public.season_fixtures
     where season_id = p_season and competition_id = p_comp and stage = p_stage and tie_no = v_t.tie_no
     order by leg desc limit 1;

    if v_g1 > v_g2 then v_w := v_c1;
    elsif v_g2 > v_g1 then v_w := v_c2;
    else
      v_w  := public.sim_pens_winner(v_c1, v_c2);
      v_wp := 3 + floor(random() * 3)::int;                              -- 3 a 5
      v_lp := greatest(0, v_wp - 1 - floor(random() * 2)::int);          -- vencedor sempre na frente
      update public.season_fixtures
         set home_pens = case when v_lasthome = v_w then v_wp else v_lp end,
             away_pens = case when v_lasthome = v_w then v_lp else v_wp end
       where id = v_last;
    end if;

    update public.season_fixtures set tie_winner = v_w where id = v_last;
    v_out := v_out || v_w;
  end loop;
  return v_out;
end;
$$;

-- Sorteio de uma fase eliminatória entre os classificados
create or replace function public.sim_draw_knockout(p_season uuid, p_comp text, p_stage text, p_winners text[])
returns void language plpgsql security definer set search_path = public as $$
declare
  v_t text[];
  v_i int;
  v_a text;
  v_b text;
begin
  select array_agg(x order by random()) into v_t from unnest(p_winners) as x;
  for v_i in 1 .. array_length(v_t, 1) / 2 loop
    v_a := v_t[2 * v_i - 1];
    v_b := v_t[2 * v_i];
    if p_stage = 'final' then       -- final em jogo único (campo neutro)
      insert into public.season_fixtures (season_id, competition_id, stage, round_no, tie_no, leg, home_club, away_club)
      values (p_season, p_comp, 'final', 1, v_i, 1, v_a, v_b);
    else
      insert into public.season_fixtures (season_id, competition_id, stage, round_no, tie_no, leg, home_club, away_club) values
        (p_season, p_comp, p_stage, 1, v_i, 1, v_a, v_b),
        (p_season, p_comp, p_stage, 2, v_i, 2, v_b, v_a);
    end if;
  end loop;
end;
$$;

-- Oitavas da Libertadores: 1º de cada grupo x 2º de OUTRO grupo (decide em casa o 1º)
create or replace function public.sim_draw_lib_r16(p_season uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_wc text[] := '{}';  v_wg text[] := '{}';
  v_rc text[] := '{}';  v_rg text[] := '{}';
  v_g  record;
  v_perm int[];
  v_ok boolean;
  v_i  int;
  v_try int;
begin
  for v_g in select distinct group_label from public.sim_competition_clubs where competition_id = 'libertadores' order by 1 loop
    v_wc := v_wc || (select s1.club_id from public.sim_standings(p_season, 'libertadores', v_g.group_label) s1 where s1.pos = 1);
    v_rc := v_rc || (select s2.club_id from public.sim_standings(p_season, 'libertadores', v_g.group_label) s2 where s2.pos = 2);
    v_wg := v_wg || v_g.group_label;
    v_rg := v_rg || v_g.group_label;
  end loop;

  for v_try in 1 .. 300 loop
    select array_agg(i order by random()) into v_perm from generate_series(1, array_length(v_rc, 1)) as i;
    v_ok := true;
    for v_i in 1 .. array_length(v_wc, 1) loop
      if v_rg[v_perm[v_i]] = v_wg[v_i] then v_ok := false; exit; end if;
    end loop;
    exit when v_ok;
  end loop;

  for v_i in 1 .. array_length(v_wc, 1) loop
    insert into public.season_fixtures (season_id, competition_id, stage, round_no, tie_no, leg, home_club, away_club) values
      (p_season, 'libertadores', 'r16', 1, v_i, 1, v_rc[v_perm[v_i]], v_wc[v_i]),
      (p_season, 'libertadores', 'r16', 2, v_i, 2, v_wc[v_i], v_rc[v_perm[v_i]]);
  end loop;
end;
$$;

-- Encerra o campeonato: define campeão/vice, o resultado do jogador e o bônus
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
begin
  select * into v_s from public.career_seasons where id = p_season;

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
   where season_id = p_season and competition_id = p_comp and (home_club = v_s.club_id or away_club = v_s.club_id);
  select count(*) into v_played from public.season_fixtures
   where season_id = p_season and competition_id = p_comp and player_match;

  if v_has > 0 then
    if p_comp = 'brasileirao' then
      select t.pos into v_pos from public.sim_standings(p_season, p_comp, null) t where t.club_id = v_s.club_id;
      v_label := case when v_pos = 1 then 'Campeão' else v_pos::text || 'º lugar' end;
      v_code  := case when v_pos = 1 then 'p1' when v_pos <= 4 then 'p2_4' when v_pos <= 8 then 'p5_8' else 'pother' end;
    elsif v_champ = v_s.club_id then
      v_label := 'Campeão';       v_code := 'champion';
    elsif v_runner = v_s.club_id then
      v_label := 'Vice-campeão';  v_code := 'runner_up';
    else
      select f.stage into v_last from public.season_fixtures f
       where f.season_id = p_season and f.competition_id = p_comp and (f.home_club = v_s.club_id or f.away_club = v_s.club_id)
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
      if v_code in ('champion', 'p1') then
        update public.career_stats set titles = titles + 1, popularity = least(1000, popularity + 100), updated_at = now()
         where career_id = v_s.career_id;
      elsif v_code in ('runner_up', 'p2_4') then
        update public.career_stats set popularity = least(1000, popularity + 30), updated_at = now()
         where career_id = v_s.career_id;
      end if;
    end if;
  end if;

  update public.season_competitions
     set status = 'finished', champion_club = v_champ, runner_up_club = v_runner,
         player_club = case when v_has > 0 then v_s.club_id end,
         player_result = v_label,
         player_bonus_xp = case when v_played > 0 then v_xp end,
         player_bonus_coins = case when v_played > 0 then v_coins end
   where season_id = p_season and competition_id = p_comp;
end;
$$;

-- Avança o campeonato quando a fase atual termina (gera o próximo mata-mata, fecha o campeonato...)
create or replace function public.sim_advance(p_season uuid, p_comp text)
returns boolean language plpgsql security definer set search_path = public as $$
declare
  v_sc  public.season_competitions;
  v_w   text[];
  v_nxt text;
begin
  select * into v_sc from public.season_competitions where season_id = p_season and competition_id = p_comp;
  if v_sc.status = 'finished' then return false; end if;
  if exists (select 1 from public.season_fixtures where season_id = p_season and competition_id = p_comp and status = 'pending') then
    return false;                                  -- ainda há jogos na fase atual
  end if;
  if not exists (select 1 from public.season_fixtures where season_id = p_season and competition_id = p_comp) then
    return false;
  end if;

  if v_sc.stage = 'league' then
    perform public.sim_finish_competition(p_season, p_comp);
  elsif v_sc.stage = 'group' then
    perform public.sim_draw_lib_r16(p_season);
    update public.season_competitions set stage = 'r16' where season_id = p_season and competition_id = p_comp;
  elsif v_sc.stage in ('r16', 'qf', 'sf') then
    v_w   := public.sim_resolve_ties(p_season, p_comp, v_sc.stage);
    v_nxt := case v_sc.stage when 'r16' then 'qf' when 'qf' then 'sf' else 'final' end;
    perform public.sim_draw_knockout(p_season, p_comp, v_nxt, v_w);
    update public.season_competitions set stage = v_nxt where season_id = p_season and competition_id = p_comp;
  elsif v_sc.stage = 'final' then
    perform public.sim_resolve_ties(p_season, p_comp, 'final');
    perform public.sim_finish_competition(p_season, p_comp);
  end if;
  return true;
end;
$$;

-- Joga TUDO que falta de um campeonato (usado quando o jogador é eliminado ou a temporada acaba)
create or replace function public.sim_complete_competition(p_season uuid, p_comp text)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_i     int;
  v_st    text;
  v_stage text;
  v_round int;
  v_found boolean;
  v_prog  boolean;
begin
  for v_i in 1 .. 400 loop
    select status into v_st from public.season_competitions where season_id = p_season and competition_id = p_comp;
    exit when v_st = 'finished';

    select f.stage, f.round_no into v_stage, v_round from public.season_fixtures f
     where f.season_id = p_season and f.competition_id = p_comp and f.status = 'pending'
     order by f.round_no, f.id limit 1;
    v_found := found;
    if v_found then perform public.sim_play_round(p_season, p_comp, v_stage, v_round); end if;

    v_prog := public.sim_advance(p_season, p_comp);
    if not v_found and not v_prog then
      raise exception 'Campeonato travado: %', p_comp;
    end if;
  end loop;
end;
$$;

-- ---------------------------------------------------------------------
-- 6) PROPOSTAS DE OUTROS CLUBES (quanto mais popularidade, mais propostas e melhores)
-- ---------------------------------------------------------------------
create or replace function public.sim_make_offer(p_career uuid, p_season uuid, p_cur text, p_pop int)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_cur   int;
  v_cand  text;
  v_str   int;
  v_bonus int;
  v_pitch text;
  v_id    uuid;
begin
  select strength into v_cur from public.sim_clubs where id = p_cur;

  select id, strength into v_cand, v_str from public.sim_clubs
   where tier = 'serie_a' and id <> p_cur
     and id not in (select from_club from public.season_offers where career_id = p_career and status = 'pending')
     and strength <= v_cur + 4 + p_pop / 40        -- popularidade alta alcança clubes maiores
     and strength >= v_cur - 6
   order by random() limit 1;
  if v_cand is null then return null; end if;

  v_bonus := (round((300 + p_pop * 4 + v_str * 8) / 50.0) * 50)::int;
  v_pitch := case
    when v_str > v_cur + 3 then 'Projeto ambicioso: querem você como peça-chave para brigar por títulos.'
    when v_str < v_cur - 2 then 'Prometem a camisa de titular absoluto e o clube inteiro jogando em torno de você.'
    else 'Mesmo patamar, mais protagonismo: você seria uma das estrelas do elenco.'
  end;

  insert into public.season_offers (career_id, season_id, from_club, bonus_coins, pitch)
  values (p_career, p_season, v_cand, v_bonus, v_pitch) returning id into v_id;

  return jsonb_build_object('id', v_id, 'club_id', v_cand, 'bonus_coins', v_bonus, 'pitch', v_pitch);
end;
$$;

-- Chance de chegar uma proposta depois de uma partida (máx. 3 propostas pendentes)
create or replace function public.sim_maybe_offer(p_career uuid, p_season uuid, p_cur text, p_pop int)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_n int;
begin
  select count(*) into v_n from public.season_offers where career_id = p_career and status = 'pending';
  if v_n >= 3 then return null; end if;
  if random() > 0.01 + p_pop * 0.0004 then return null; end if;   -- 1% sem fama ... ~25% com 600 de popularidade
  return public.sim_make_offer(p_career, p_season, p_cur, p_pop);
end;
$$;

-- ---------------------------------------------------------------------
-- 7) FIM DA TEMPORADA
-- ---------------------------------------------------------------------
create or replace function public.sim_finalize_season(p_season uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_s   public.career_seasons;
  r     record;
  v_sum jsonb;
  v_pop int;
  v_n   int;
  v_i   int;
begin
  select * into v_s from public.career_seasons where id = p_season;

  -- campeonatos que o jogador não disputou (ou dos quais saiu) terminam "sozinhos"
  for r in select competition_id from public.season_competitions where season_id = p_season and status <> 'finished' loop
    perform public.sim_complete_competition(p_season, r.competition_id);
  end loop;

  select jsonb_agg(jsonb_build_object(
           'competition', sc.competition_id, 'champion', sc.champion_club, 'runner_up', sc.runner_up_club,
           'player_result', sc.player_result, 'bonus_xp', sc.player_bonus_xp, 'bonus_coins', sc.player_bonus_coins)
         order by sc.competition_id)
    into v_sum from public.season_competitions sc where sc.season_id = p_season;

  update public.career_seasons set status = 'finished', finished_at = now(), summary = v_sum where id = p_season;
  update public.career_stats set seasons_played = seasons_played + 1, updated_at = now() where career_id = v_s.career_id;

  -- janela de transferências: 0 a 3 propostas, conforme a popularidade
  select popularity into v_pop from public.career_stats where career_id = v_s.career_id;
  v_n := least(3, v_pop / 200 + (case when random() < 0.5 then 1 else 0 end));
  for v_i in 1 .. v_n loop
    perform public.sim_make_offer(v_s.career_id, p_season, v_s.club_id, v_pop);
  end loop;
end;
$$;

-- ---------------------------------------------------------------------
-- 8) AÇÕES DO JOGADOR (chamadas pelo app)
-- ---------------------------------------------------------------------
-- Simula a PRÓXIMA partida do seu clube no campeonato escolhido. Custa 1 de energia.
create or replace function public.season_play(p_competition text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_c     public.careers;
  v_s     public.career_seasons;
  v_comp  public.sim_competitions;
  v_sc    public.season_competitions;
  v_f     public.season_fixtures;
  v_f2    public.season_fixtures;
  v_lvl0  int;
  v_home  boolean;
  v_sh    int;
  v_sa    int;
  v_q     double precision;
  v_gs    double precision;
  v_as    double precision;
  v_fac   double precision;
  v_sco   int[];
  v_hg    int;
  v_ag    int;
  v_my    int;
  v_opp   int;
  v_pg    int := 0;
  v_pa    int := 0;
  v_i     int;
  v_res   text;
  v_rat   numeric;
  v_mult  numeric;
  v_xp    int;
  v_coins int;
  v_pop   int;     -- popularidade TOTAL (para a chance de proposta)
  v_dpop  int;     -- variação de popularidade desta partida
  v_pending int;
  v_cst   text;
  v_offer jsonb;
  v_round jsonb;
  v_comp_done boolean := false;
  v_season_done boolean := false;
begin
  v_c := public.sim_lock_career();
  v_lvl0 := v_c.level;
  if v_c.energy + v_c.bonus_energy < 1 then
    raise exception 'Sem energia. Espere a recarga para simular a próxima partida.';
  end if;

  select * into v_s from public.career_seasons where career_id = v_c.id and status = 'active';
  if not found then raise exception 'Não há temporada em andamento. Inicie a próxima temporada.'; end if;

  select * into v_comp from public.sim_competitions where id = p_competition;
  if not found then raise exception 'Campeonato inválido'; end if;
  select * into v_sc from public.season_competitions where season_id = v_s.id and competition_id = p_competition;

  select * into v_f from public.season_fixtures
   where season_id = v_s.id and competition_id = p_competition and status = 'pending'
     and (home_club = v_s.club_id or away_club = v_s.club_id)
   order by round_no, id limit 1;
  if not found then raise exception 'Seu clube não tem partidas pendentes neste campeonato.'; end if;

  -- gasta a energia livre primeiro; a bônus (comprada) só quando a livre acabar
  if v_c.energy >= 1 then
    update public.careers set energy = energy - 1 where id = v_c.id;
  else
    update public.careers set bonus_energy = bonus_energy - 1 where id = v_c.id;
  end if;

  -- ---- a partida ----------------------------------------------------
  v_home := (v_f.home_club = v_s.club_id);
  select strength into v_sh from public.sim_clubs where id = v_f.home_club;
  select strength into v_sa from public.sim_clubs where id = v_f.away_club;

  -- qualidade do jogador: sobe com o nível (nível 1 = 0.28 ... nível 24+ = 0.95)
  v_q := least(0.95, 0.25 + 0.03 * v_c.level);

  v_sco := public.sim_score(v_sh, v_sa, v_f.stage = 'final',
             case when v_home then 1 + 0.18 * v_q else 1 - 0.06 * v_q end,
             case when v_home then 1 - 0.06 * v_q else 1 + 0.18 * v_q end);
  v_hg := v_sco[1];  v_ag := v_sco[2];
  v_my  := case when v_home then v_hg else v_ag end;
  v_opp := case when v_home then v_ag else v_hg end;
  v_res := case when v_my > v_opp then 'win' when v_my = v_opp then 'draw' else 'loss' end;

  -- chance de o gol / a assistência do SEU time ter sido seu: depende da POSIÇÃO e do NÍVEL
  v_gs := case v_c.position when 'ATA' then 0.36 when 'PE' then 0.26 when 'PD' then 0.26 when 'MEI' then 0.24
            when 'MC' then 0.12 when 'VOL' then 0.05 when 'LD' then 0.05 when 'LE' then 0.05
            when 'ZAG' then 0.06 when 'GOL' then 0.002 else 0.12 end;
  v_as := case v_c.position when 'ATA' then 0.15 when 'PE' then 0.25 when 'PD' then 0.25 when 'MEI' then 0.32
            when 'MC' then 0.28 when 'VOL' then 0.12 when 'LD' then 0.22 when 'LE' then 0.22
            when 'ZAG' then 0.04 when 'GOL' then 0.02 else 0.12 end;
  v_fac := 0.35 + 0.65 * v_q;
  for v_i in 1 .. v_my loop
    if random() < v_gs * v_fac then v_pg := v_pg + 1;
    elsif random() < v_as * v_fac then v_pa := v_pa + 1;
    end if;
  end loop;

  -- nota da partida (3.0 a 10.0)
  v_rat := 5.8 + 1.0 * (v_q - 0.5)
         + case v_res when 'win' then 0.6 when 'draw' then 0.1 else -0.4 end
         + v_pg * 1.1 + v_pa * 0.6
         + case when v_opp = 0 and v_c.position in ('GOL', 'ZAG', 'LD', 'LE', 'VOL') then 0.7 else 0 end
         + (random() - 0.5) * 1.2;
  v_rat := round(greatest(3.0, least(10.0, v_rat))::numeric, 1);

  update public.season_fixtures
     set home_goals = v_hg, away_goals = v_ag, status = 'played', player_match = true,
         player_goals = v_pg, player_assists = v_pa, player_rating = v_rat, played_at = now()
   where id = v_f.id;
  update public.season_competitions set status = 'active'
   where season_id = v_s.id and competition_id = p_competition and status = 'pending';

  -- ---- prêmios, estatísticas e popularidade -------------------------
  v_mult := v_comp.xp_mult * (case v_f.stage when 'final' then 1.5 when 'r16' then 1.2 when 'qf' then 1.2 when 'sf' then 1.2 else 1 end);
  v_xp    := round((case v_res when 'win' then 30 when 'draw' then 15 else 8 end  + v_pg * 10 + v_pa * 6)  * v_mult)::int;
  v_coins := round((case v_res when 'win' then 60 when 'draw' then 25 else 10 end + v_pg * 30 + v_pa * 15) * v_mult)::int;
  v_dpop  := (case v_res when 'win' then 8 when 'draw' then 3 else -2 end) + v_pg * 6 + v_pa * 4
           + (case when v_rat >= 8 then 5 when v_rat < 5 then -3 else 0 end)
           + (case when v_f.stage in ('r16', 'qf', 'sf', 'final') then 2 else 0 end);

  update public.careers set xp = xp + v_xp, coins = coins + v_coins where id = v_c.id;   -- o gatilho sobe o nível a cada 1000 XP

  update public.career_stats
     set matches = matches + 1,
         wins   = wins   + (v_res = 'win')::int,
         draws  = draws  + (v_res = 'draw')::int,
         losses = losses + (v_res = 'loss')::int,
         goals = goals + v_pg, assists = assists + v_pa,
         popularity = greatest(0, least(1000, popularity + v_dpop)),
         updated_at = now()
   where career_id = v_c.id;

  update public.career_seasons
     set matches = matches + 1,
         wins   = wins   + (v_res = 'win')::int,
         draws  = draws  + (v_res = 'draw')::int,
         losses = losses + (v_res = 'loss')::int,
         goals = goals + v_pg, assists = assists + v_pa,
         xp_earned = xp_earned + v_xp, coins_earned = coins_earned + v_coins
   where id = v_s.id;

  -- ---- o resto da rodada, o próximo mata-mata e o fim do campeonato --
  perform public.sim_play_round(v_s.id, p_competition, v_f.stage, v_f.round_no);
  perform public.sim_advance(v_s.id, p_competition);

  select count(*) into v_pending from public.season_fixtures
   where season_id = v_s.id and competition_id = p_competition and status = 'pending'
     and (home_club = v_s.club_id or away_club = v_s.club_id);
  select status into v_cst from public.season_competitions where season_id = v_s.id and competition_id = p_competition;
  if v_cst <> 'finished' and v_pending = 0 then            -- seu clube caiu: o resto do torneio é jogado
    perform public.sim_complete_competition(v_s.id, p_competition);
  end if;
  select * into v_sc from public.season_competitions where season_id = v_s.id and competition_id = p_competition;
  v_comp_done := (v_sc.status = 'finished');

  -- ---- proposta de outro clube? -------------------------------------
  select popularity into v_pop from public.career_stats where career_id = v_c.id;
  v_offer := public.sim_maybe_offer(v_c.id, v_s.id, v_s.club_id, v_pop);

  -- ---- acabou a temporada? ------------------------------------------
  if not exists (select 1 from public.season_fixtures
                  where season_id = v_s.id and status = 'pending' and (home_club = v_s.club_id or away_club = v_s.club_id)) then
    perform public.sim_finalize_season(v_s.id);
    v_season_done := true;
  end if;

  -- ---- resposta para a tela -----------------------------------------
  select * into v_c  from public.careers where id = v_c.id;
  select * into v_f2 from public.season_fixtures where id = v_f.id;
  select jsonb_agg(jsonb_build_object('home', o.home_club, 'away', o.away_club, 'hg', o.home_goals, 'ag', o.away_goals, 'group', o.group_label) order by o.id)
    into v_round
    from public.season_fixtures o
   where o.season_id = v_s.id and o.competition_id = p_competition and o.stage = v_f.stage
     and o.round_no = v_f.round_no and o.id <> v_f.id;

  return jsonb_build_object(
    'competition', p_competition,
    'stage', v_f.stage, 'round', v_f.round_no, 'leg', v_f.leg, 'group', v_f.group_label,
    'venue', case when v_home then 'home' else 'away' end,
    'home', v_f2.home_club, 'away', v_f2.away_club,
    'home_goals', v_f2.home_goals, 'away_goals', v_f2.away_goals,
    'home_pens', v_f2.home_pens, 'away_pens', v_f2.away_pens, 'tie_winner', v_f2.tie_winner,
    'my_club', v_s.club_id, 'result', v_res,
    'player', jsonb_build_object('goals', v_pg, 'assists', v_pa, 'rating', v_rat),
    'rewards', jsonb_build_object('xp', v_xp, 'coins', v_coins, 'popularity', v_dpop),
    'level_up', v_c.level > v_lvl0, 'new_level', v_c.level,
    'round_results', coalesce(v_round, '[]'::jsonb),
    'competition_finished', v_comp_done,
    'competition_result', case when v_comp_done then v_sc.player_result end,
    'competition_bonus', case when v_comp_done and coalesce(v_sc.player_bonus_xp, 0) + coalesce(v_sc.player_bonus_coins, 0) > 0
                              then jsonb_build_object('xp', v_sc.player_bonus_xp, 'coins', v_sc.player_bonus_coins) end,
    'champion', case when v_comp_done then v_sc.champion_club end,
    'offer', v_offer,
    'season_finished', v_season_done,
    'energy', v_c.energy + v_c.bonus_energy);
end;
$$;

-- Tela principal do modo Temporadas: tudo num único retorno
create or replace function public.season_hub()
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_c     public.careers;
  v_st    public.career_stats;
  v_s     public.career_seasons;
  v_sc    public.season_competitions;
  v_nf    public.season_fixtures;
  r       record;
  v_total int;
  v_played int;
  v_pending int;
  v_status text;
  v_grp   text;
  v_pos   int;
  v_pts   int;
  v_pl    int;
  v_item  jsonb;
  v_comps jsonb := '[]'::jsonb;
  v_offers jsonb;
begin
  v_c := public.sim_lock_career();
  if v_c.club_id is null then raise exception 'Escolha um clube antes de jogar temporadas.'; end if;

  insert into public.career_stats (career_id) values (v_c.id) on conflict do nothing;
  select * into v_st from public.career_stats where career_id = v_c.id;

  select * into v_s from public.career_seasons where career_id = v_c.id order by season_no desc limit 1;
  if v_s.id is null then
    perform public.sim_create_season(v_c.id);
    select * into v_s from public.career_seasons where career_id = v_c.id order by season_no desc limit 1;
  end if;

  for r in select id, name, short_name from public.sim_competitions order by sort_order loop
    select * into v_sc from public.season_competitions where season_id = v_s.id and competition_id = r.id;

    select count(*), count(*) filter (where status = 'played'), count(*) filter (where status = 'pending')
      into v_total, v_played, v_pending
      from public.season_fixtures
     where season_id = v_s.id and competition_id = r.id and (home_club = v_s.club_id or away_club = v_s.club_id);

    v_status := case when v_sc.status = 'finished' then 'finished'
                     when v_total = 0 then 'not_in'
                     when v_pending = 0 then 'out'
                     else 'active' end;

    v_item := jsonb_build_object(
      'id', r.id, 'name', r.name, 'short_name', r.short_name, 'status', v_status, 'stage', v_sc.stage,
      'played', v_played, 'total', v_total,
      'champion', v_sc.champion_club, 'runner_up', v_sc.runner_up_club,
      'player_result', v_sc.player_result, 'bonus_xp', v_sc.player_bonus_xp, 'bonus_coins', v_sc.player_bonus_coins);

    if v_status = 'active' then
      select * into v_nf from public.season_fixtures
       where season_id = v_s.id and competition_id = r.id and status = 'pending'
         and (home_club = v_s.club_id or away_club = v_s.club_id)
       order by round_no, id limit 1;
      v_item := v_item || jsonb_build_object('next', jsonb_build_object(
        'home', v_nf.home_club, 'away', v_nf.away_club, 'round', v_nf.round_no, 'stage', v_nf.stage,
        'leg', v_nf.leg, 'group', v_nf.group_label,
        'venue', case when v_nf.home_club = v_s.club_id then 'home' else 'away' end,
        'neutral', (v_nf.stage = 'final')));
    end if;

    -- posição na tabela (Brasileirão e fase de grupos da Libertadores)
    if v_total > 0 and r.id <> 'copa_brasil' then
      v_grp := null;
      if r.id = 'libertadores' then
        select group_label into v_grp from public.season_fixtures
         where season_id = v_s.id and competition_id = r.id and stage = 'group'
           and (home_club = v_s.club_id or away_club = v_s.club_id) limit 1;
      end if;
      select t.pos, t.points, t.played into v_pos, v_pts, v_pl
        from public.sim_standings(v_s.id, r.id, v_grp) t where t.club_id = v_s.club_id;
      v_item := v_item || jsonb_build_object('table', jsonb_build_object('group', v_grp, 'pos', v_pos, 'points', v_pts, 'played', v_pl));
    end if;

    v_comps := v_comps || jsonb_build_array(v_item);
  end loop;

  select coalesce(jsonb_agg(jsonb_build_object(
           'id', o.id, 'club_id', o.from_club, 'bonus_coins', o.bonus_coins, 'pitch', o.pitch, 'created_at', o.created_at)
         order by o.created_at desc), '[]'::jsonb)
    into v_offers from public.season_offers o where o.career_id = v_c.id and o.status = 'pending';

  return jsonb_build_object(
    'career', jsonb_build_object(
      'id', v_c.id, 'nickname', v_c.nickname, 'position', v_c.position, 'level', v_c.level, 'xp', v_c.xp,
      'coins', v_c.coins, 'energy', v_c.energy, 'bonus_energy', v_c.bonus_energy,
      'next_reset_at', v_c.energy_reset_at + interval '5 hours', 'club_id', v_c.club_id),
    'stats', to_jsonb(v_st) - 'career_id',
    'season', to_jsonb(v_s) - 'career_id',
    'competitions', v_comps,
    'offers', v_offers);
end;
$$;

-- Classificação (liga ou grupo) de uma temporada SUA
create or replace function public.season_standings(p_season uuid, p_comp text, p_group text default null)
returns table (pos int, club_id text, played int, wins int, draws int, losses int, gf int, ga int, gd int, points int)
language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from public.career_seasons s join public.careers c on c.id = s.career_id
                  where s.id = p_season and c.user_id = auth.uid()) then
    raise exception 'Temporada não encontrada';
  end if;
  return query select * from public.sim_standings(p_season, p_comp, p_group);
end;
$$;

-- Começa a próxima temporada (só depois de a atual terminar)
create or replace function public.season_start_next()
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_c public.careers;
begin
  v_c := public.sim_lock_career();
  if exists (select 1 from public.career_seasons where career_id = v_c.id and status = 'active') then
    raise exception 'Você ainda tem uma temporada em andamento.';
  end if;
  update public.season_offers set status = 'expired', responded_at = now() where career_id = v_c.id and status = 'pending';
  perform public.sim_create_season(v_c.id);
  return jsonb_build_object('ok', true);
end;
$$;

-- Aceitar ou recusar uma proposta. Aceitar = transferência imediata + bônus de assinatura.
create or replace function public.season_offer_respond(p_offer uuid, p_accept boolean)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_c public.careers;
  v_o public.season_offers;
begin
  v_c := public.sim_lock_career();
  select * into v_o from public.season_offers where id = p_offer and career_id = v_c.id for update;
  if not found then raise exception 'Proposta não encontrada'; end if;
  if v_o.status <> 'pending' then raise exception 'Esta proposta não está mais disponível'; end if;

  if p_accept then
    update public.career_seasons set club_id = v_o.from_club where career_id = v_c.id and status = 'active';
    update public.careers set club_id = v_o.from_club, coins = coins + v_o.bonus_coins where id = v_c.id;
    update public.season_offers set status = 'accepted', responded_at = now() where id = v_o.id;
    update public.season_offers set status = 'expired', responded_at = now()
     where career_id = v_c.id and status = 'pending' and id <> v_o.id;
  else
    update public.season_offers set status = 'declined', responded_at = now() where id = v_o.id;
  end if;
  return jsonb_build_object('ok', true, 'accepted', p_accept, 'club_id', v_o.from_club);
end;
$$;

-- ---------------------------------------------------------------------
-- 9) ESCOLHA DO CLUBE INICIAL (substitui o UPDATE direto do app, que permitia trocar de clube à vontade)
-- ---------------------------------------------------------------------
create or replace function public.choose_initial_club(p_club text)
returns void language plpgsql security definer set search_path = public as $$
declare v_c public.careers;
begin
  v_c := public.sim_lock_career();
  if v_c.club_id is not null then raise exception 'Você já tem clube.'; end if;
  if p_club not in ('botafogo', 'fluminense', 'flamengo') then raise exception 'Clube inválido.'; end if;
  update public.careers set club_id = p_club where id = v_c.id;
end;
$$;
revoke update (club_id) on public.careers from authenticated;

-- ---------------------------------------------------------------------
-- 10) PERMISSÕES: o app só chama as funções "públicas"; as sim_* ficam internas
-- ---------------------------------------------------------------------
do $$
declare f record;
begin
  for f in select p.oid::regprocedure as sig, p.proname
           from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and (p.proname like 'sim\_%' or p.proname like 'season\_%'
                 or p.proname in ('refresh_wallet', 'choose_initial_club', 'careers_level_up'))
  loop
    execute format('revoke all on function %s from public, anon, authenticated', f.sig);
    if f.proname in ('season_hub', 'season_play', 'season_start_next', 'season_offer_respond',
                     'season_standings', 'refresh_wallet', 'choose_initial_club') then
      execute format('grant execute on function %s to authenticated', f.sig);
    end if;
  end loop;
end $$;
