-- =====================================================================
-- EVOLUÇÃO 03 — MOTOR DE COMPETIÇÕES CONFIGURÁVEL
-- O formato de cada competição vem de sim_competitions.rules.phases (veja data/competitions/competitions.json).
-- Estas funções SUBSTITUEM (create or replace) as versões fixas de supabase/seasons e supabase/manager:
--   sim_create_season, sim_standings, sim_resolve_ties, sim_advance, sim_finish_competition, sim_next_event,
--   mgr_stage_rank, mgr_best_stage, mgr_comp_do.
-- Os três campeonatos que já existiam (Brasileirão, Copa do Brasil, Libertadores) têm configuração equivalente
-- ao comportamento anterior (mesmas fases, mando, prorrogação e pênaltis) — testado em supabase/evolution/tests.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1) Leitura da configuração
-- ---------------------------------------------------------------------
create or replace function public.sim_comp_phases(p_comp text)
returns jsonb language sql stable set search_path = public as $$
  select coalesce((select rules -> 'phases' from public.sim_competitions where id = p_comp), '[]'::jsonb)
$$;

-- fase pelo id (com o índice, começando em 1)
create or replace function public.sim_phase(p_comp text, p_phase text)
returns jsonb language sql stable set search_path = public as $$
  select x.ph || jsonb_build_object('idx', x.o)
    from jsonb_array_elements(public.sim_comp_phases(p_comp)) with ordinality as x(ph, o)
   where x.ph ->> 'id' = p_phase
   limit 1
$$;

create or replace function public.sim_phase_at(p_comp text, p_idx int)
returns jsonb language sql stable set search_path = public as $$
  select x.ph || jsonb_build_object('idx', x.o)
    from jsonb_array_elements(public.sim_comp_phases(p_comp)) with ordinality as x(ph, o)
   where x.o = p_idx
$$;

create or replace function public.sim_phase_index(p_comp text, p_phase text)
returns int language sql stable set search_path = public as $$
  select coalesce((public.sim_phase(p_comp, p_phase) ->> 'idx')::int, 99)
$$;

-- fase -> "tamanho" (para objetivos): 1 liga/grupos/fases iniciais, 2 oitavas, 3 quartas, 4 semi, 5 final, 6 campeão
create or replace function public.mgr_stage_rank(p_comp text, p_stage text)
returns int language sql stable set search_path = public as $$
  select case when p_stage = 'champion' then 6
              else coalesce((public.sim_phase(p_comp, p_stage) ->> 'rank')::int, public.mgr_stage_rank(p_stage)) end
$$;

create or replace function public.mgr_best_stage(p_season uuid, p_comp text, p_club text)
returns int language sql stable set search_path = public as $$
  select greatest(
    coalesce((select max(public.mgr_stage_rank(p_comp, f.stage)) from public.season_fixtures f
               where f.season_id = p_season and f.competition_id = p_comp and (f.home_club = p_club or f.away_club = p_club)), 0),
    coalesce((select 6 from public.season_competitions sc where sc.season_id = p_season and sc.competition_id = p_comp
               and sc.status = 'finished' and sc.champion_club = p_club), 0))
$$;

create or replace function public.mgr_comp_do(p_comp text)
returns text language sql stable set search_path = public as $$
  select case when p_comp = 'brasileirao' then 'do ' else 'da ' end || coalesce((select name from public.sim_competitions where id = p_comp), p_comp)
$$;

-- região de um clube (clube estrangeiro não tem região: não disputa liga nacional no jogo)
create or replace function public.sim_club_region(p_club text)
returns text language sql stable set search_path = public as $$
  select region from public.sim_clubs where id = p_club
$$;

-- regra de acesso/rebaixamento em vigor para um ano
create or replace function public.sim_promotion_rules_for(p_region text, p_year int)
returns setof public.sim_promotion_rules language sql stable set search_path = public as $$
  select * from public.sim_promotion_rules
   where region = p_region and from_year <= p_year and (to_year is null or to_year >= p_year)
   order by upper_comp
$$;

-- ---------------------------------------------------------------------
-- 2) Participantes da temporada
--    1ª temporada da região: participantes de referência (temporada oficial cadastrada).
--    Depois: a divisão de cada clube sai do fim da temporada anterior (season_transitions).
-- ---------------------------------------------------------------------
create or replace function public.sim_participants_build(p_season uuid)
returns int language plpgsql security definer set search_path = public as $$
declare
  v_s     public.career_seasons;
  v_t     public.season_transitions;
  c       record;
  v_list  text[];
  v_q     text[];
  v_slots record;
  v_i     int;
  v_n     int := 0;
  v_entry jsonb;
  v_lg    record;
begin
  select * into v_s from public.career_seasons where id = p_season;
  if exists (select 1 from public.season_participants where season_id = p_season) then
    return 0;                                            -- já montado (idempotente)
  end if;
  select t.* into v_t from public.season_transitions t
    join public.career_seasons fs on fs.id = t.from_season
   where t.career_id = v_s.career_id and t.region = v_s.region and fs.season_no < v_s.season_no
   order by fs.season_no desc limit 1;

  -- 2a) LIGAS
  for c in select * from public.sim_competitions where region = v_s.region and active and kind = 'league' order by sort_order loop
    v_list := null;
    if v_t.id is not null and v_t.result -> 'leagues' ? c.id then
      select array_agg(x) into v_list from jsonb_array_elements_text(v_t.result -> 'leagues' -> c.id) x;
    end if;
    if v_list is null then
      select array_agg(club_id order by club_id) into v_list from public.sim_competition_clubs where competition_id = c.id;
    end if;
    insert into public.season_participants (season_id, competition_id, club_id, division_key, origin)
    select p_season, c.id, x,
           v_s.region || ':league',
           case when v_t.id is null then 'reference'
                when coalesce(v_t.result -> 'promoted' -> c.id, '[]'::jsonb) ? x then 'promoted'
                when coalesce(v_t.result -> 'relegated' -> c.id, '[]'::jsonb) ? x then 'relegated'
                else 'stayed' end
      from unnest(v_list) x;
    get diagnostics v_i = row_count;
    v_n := v_n + v_i;
  end loop;

  -- 2b) COPAS NACIONAIS: com "entry" (copas inglesas) = todos os clubes das ligas da temporada, entrando na fase da sua divisão;
  --     sem "entry" (Copa do Brasil) = chave de referência
  for c in select * from public.sim_competitions where region = v_s.region and active and kind = 'cup' order by sort_order loop
    v_entry := c.rules -> 'entry';
    if v_entry is not null then
      for v_lg in select key as comp, value #>> '{}' as phase from jsonb_each(v_entry) loop
        insert into public.season_participants (season_id, competition_id, club_id, entry_phase, origin)
        select p_season, c.id, sp.club_id, v_lg.phase, 'league'
          from public.season_participants sp
         where sp.season_id = p_season and sp.competition_id = v_lg.comp
        on conflict do nothing;
      end loop;
    else
      insert into public.season_participants (season_id, competition_id, club_id, group_label, seed, entry_phase, origin)
      select p_season, c.id, cc.club_id, cc.group_label, cc.seed, cc.entry_phase, 'reference'
        from public.sim_competition_clubs cc where cc.competition_id = c.id
      on conflict do nothing;
    end if;
    get diagnostics v_i = row_count;
    v_n := v_n + v_i;
  end loop;

  -- 2c) CONTINENTAIS: referência; as vagas do país da região passam para os mais bem colocados da liga na temporada anterior
  for c in select * from public.sim_competitions where region = v_s.region and active and kind = 'continental' order by sort_order loop
    v_q := null;
    if v_t.id is not null and v_t.result -> 'qualified' ? c.id then
      select array_agg(x order by o) into v_q from jsonb_array_elements_text(v_t.result -> 'qualified' -> c.id) with ordinality as t(x, o);
    end if;
    -- vagas da região (melhor pote/grupo primeiro), na ordem em que serão preenchidas
    v_i := 0;
    for v_slots in
      select cc.club_id, cc.group_label, cc.seed, cc.entry_phase, coalesce(cl.region = v_s.region, false) as mine
        from public.sim_competition_clubs cc join public.sim_clubs cl on cl.id = cc.club_id
       where cc.competition_id = c.id
       order by coalesce(cl.region = v_s.region, false) desc, cc.seed nulls last, cl.strength desc, cc.club_id
    loop
      if v_slots.mine and v_q is not null then
        v_i := v_i + 1;
        if v_i <= coalesce(array_length(v_q, 1), 0) then
          insert into public.season_participants (season_id, competition_id, club_id, group_label, seed, entry_phase, origin)
          values (p_season, c.id, v_q[v_i], v_slots.group_label, v_slots.seed, v_slots.entry_phase, 'qualified')
          on conflict do nothing;
        end if;
      else
        insert into public.season_participants (season_id, competition_id, club_id, group_label, seed, entry_phase, origin)
        values (p_season, c.id, v_slots.club_id, v_slots.group_label, v_slots.seed, v_slots.entry_phase, 'reference')
        on conflict do nothing;
      end if;
    end loop;
    get diagnostics v_i = row_count;
  end loop;

  select count(*) into v_n from public.season_participants where season_id = p_season;
  return v_n;
end;
$$;

-- ---------------------------------------------------------------------
-- 3) Criação da temporada (região do clube do técnico)
-- ---------------------------------------------------------------------
drop function if exists public.sim_create_season(uuid, text);
create or replace function public.sim_create_season(p_career uuid, p_region text)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_club text;
  v_no   int;
  v_id   uuid;
  c      record;
  v_ph   jsonb;
begin
  select club_id into v_club from public.careers where id = p_career;
  if v_club is null then raise exception 'Escolha um clube antes de iniciar a temporada'; end if;
  if not exists (select 1 from public.sim_competitions where region = p_region and active) then
    raise exception 'Região sem competições: %', p_region;
  end if;

  select coalesce(max(season_no), 0) + 1 into v_no from public.career_seasons where career_id = p_career;
  insert into public.career_seasons (career_id, season_no, year, club_id, region)
  values (p_career, v_no, 2025 + v_no, v_club, p_region) returning id into v_id;

  perform public.sim_participants_build(v_id);

  for c in select * from public.sim_competitions where region = p_region and active order by sort_order loop
    v_ph := public.sim_phase_at(c.id, 1);
    if v_ph is null then raise exception 'Competição sem fases: %', c.id; end if;
    insert into public.season_competitions (season_id, competition_id, stage) values (v_id, c.id, v_ph ->> 'id');
    perform public.sim_phase_create(v_id, c.id, v_ph ->> 'id', null);
  end loop;

  insert into public.career_stats (career_id) values (p_career) on conflict do nothing;
  return v_id;
end;
$$;

-- assinatura antiga (modo jogador / chamadas existentes): região do clube atual, Brasil por padrão
create or replace function public.sim_create_season(p_career uuid)
returns uuid language plpgsql security definer set search_path = public as $$
begin
  return public.sim_create_season(p_career,
    coalesce((select cl.region from public.careers c join public.sim_clubs cl on cl.id = c.club_id where c.id = p_career), 'BRA'));
end;
$$;

-- ---------------------------------------------------------------------
-- 4) Fase de liga suíça (UCL): modelo de calendário + sorteio das vagas de cada pote
--    Evita clubes do mesmo país no mesmo jogo (tenta várias combinações e fica com a de menos conflitos).
-- ---------------------------------------------------------------------
create or replace function public.sim_swiss_create(p_season uuid, p_comp text, p_phase jsonb)
returns int language plpgsql security definer set search_path = public as $$
declare
  v_tpls   jsonb := (select rules -> 'swiss_templates' from public.sim_competitions where id = p_comp);
  v_tpl    jsonb;
  v_best   text[];
  v_bestc  int := 1000000;
  v_slots  text[];
  v_try    int;
  v_pot    int;
  v_ids    text[];
  v_conf   int;
  v_cty    jsonb;
  m        jsonb;
  v_n      int := 0;
begin
  if v_tpls is null or jsonb_array_length(v_tpls) = 0 then raise exception 'UCL sem modelo de calendário (swiss_templates)'; end if;
  if (select count(*) from public.season_participants where season_id = p_season and competition_id = p_comp) <> 36 then
    raise exception 'Fase de liga precisa de 36 clubes';
  end if;
  v_tpl := v_tpls -> floor(random() * jsonb_array_length(v_tpls))::int;
  select jsonb_object_agg(sp.club_id, cl.country) into v_cty
    from public.season_participants sp join public.sim_clubs cl on cl.id = sp.club_id
   where sp.season_id = p_season and sp.competition_id = p_comp;

  for v_try in 1 .. 300 loop
    v_slots := '{}';
    for v_pot in 1 .. 4 loop
      select array_agg(club_id order by random()) into v_ids
        from public.season_participants where season_id = p_season and competition_id = p_comp and seed = v_pot;
      if coalesce(array_length(v_ids, 1), 0) <> 9 then raise exception 'Pote % da fase de liga sem 9 clubes', v_pot; end if;
      v_slots := v_slots || v_ids;
    end loop;
    v_conf := 0;
    for m in select * from jsonb_array_elements(v_tpl) loop
      if v_cty ->> v_slots[(m ->> 1)::int + 1] = v_cty ->> v_slots[(m ->> 2)::int + 1] then v_conf := v_conf + 1; end if;
    end loop;
    if v_conf < v_bestc then v_bestc := v_conf; v_best := v_slots; end if;
    exit when v_conf = 0;
  end loop;

  for m in select * from jsonb_array_elements(v_tpl) loop
    insert into public.season_fixtures (season_id, competition_id, stage, round_no, home_club, away_club)
    values (p_season, p_comp, p_phase ->> 'id', (m ->> 0)::int, v_best[(m ->> 1)::int + 1], v_best[(m ->> 2)::int + 1]);
    v_n := v_n + 1;
  end loop;
  return v_n;
end;
$$;

-- ---------------------------------------------------------------------
-- 5) Confrontos de uma fase eliminatória. Devolve (confronto, mandante do 1º jogo, visitante do 1º jogo).
--    Em ida e volta o 2º jogo inverte o mando: quem é melhor colocado/cabeça de chave aparece como VISITANTE do 1º jogo
--    (decide em casa). Em jogo único (não neutro) o melhor colocado é o MANDANTE.
-- ---------------------------------------------------------------------
create or replace function public.sim_phase_pairs(p_season uuid, p_comp text, p_phase jsonb, p_winners text[])
returns table (o_tie int, o_home text, o_away text)
language plpgsql security definer set search_path = public as $$
declare
  v_mode  text := coalesce(p_phase #>> '{pairing,mode}', 'draw');
  v_legs  int  := coalesce((p_phase ->> 'legs')::int, 1);
  v_from  text := p_phase #>> '{pairing,from}';
  v_seedf text := p_phase #>> '{pairing,seed_from}';
  v_ent   text[];
  v_pos   jsonb;
  v_i     int;
  v_a     text;
  v_b     text;
  v_hi    text;
  v_lo    text;
  pr      jsonb;
  v_wc text[]; v_wg text[]; v_rc text[]; v_rg text[];
  v_perm int[];
  v_ok   boolean;
  v_try  int;
  v_g    record;
  v_s1   text[];
  v_s2   text[];
  v_w    text[];
  v_tie  int := 0;
  v_grp  int;
  v_seedpairs int[][] := array[[1,2],[7,8],[3,4],[5,6]];
begin
  -- quem entra nesta fase: vencedores da fase anterior + clubes que entram aqui (copas inglesas)
  v_ent := coalesce(p_winners, '{}') || coalesce((select array_agg(club_id order by club_id) from public.season_participants
            where season_id = p_season and competition_id = p_comp
              and (entry_phase = p_phase ->> 'id' or (entry_phase is null and (p_phase ->> 'idx')::int = 1))), '{}');

  -- posição na fase de liga (quando a chave depende dela)
  if coalesce(v_from, v_seedf) is not null then
    select jsonb_object_agg(t.club_id, t.pos) into v_pos from public.sim_standings(p_season, p_comp, null) t;
  end if;

  if v_mode = 'fixed' then
    -- Copa do Brasil: confrontos de referência (T1..T8), seed 1 manda o 1º jogo
    for v_g in
      select sp.group_label, max(sp.club_id) filter (where sp.seed = 1) as c1, max(sp.club_id) filter (where sp.seed = 2) as c2
        from public.season_participants sp
       where sp.season_id = p_season and sp.competition_id = p_comp and sp.group_label is not null
       group by sp.group_label order by sp.group_label
    loop
      o_tie := coalesce(nullif(regexp_replace(v_g.group_label, '\D', '', 'g'), '')::int, v_tie + 1);
      v_tie := o_tie;
      o_home := v_g.c1; o_away := v_g.c2; return next;
    end loop;

  elsif v_mode = 'draw' then
    select array_agg(x order by random()) into v_ent from unnest(v_ent) x;
    for v_i in 1 .. coalesce(array_length(v_ent, 1), 0) / 2 loop
      o_tie := v_i; o_home := v_ent[2 * v_i - 1]; o_away := v_ent[2 * v_i]; return next;
    end loop;

  elsif v_mode = 'lib_r16' then
    -- 1º de cada grupo x 2º de OUTRO grupo; o 1º decide em casa
    for v_g in select distinct group_label from public.season_participants
                where season_id = p_season and competition_id = p_comp and group_label is not null order by 1 loop
      v_wc := coalesce(v_wc, '{}') || (select s.club_id from public.sim_standings(p_season, p_comp, v_g.group_label) s where s.pos = 1);
      v_rc := coalesce(v_rc, '{}') || (select s.club_id from public.sim_standings(p_season, p_comp, v_g.group_label) s where s.pos = 2);
      v_wg := coalesce(v_wg, '{}') || v_g.group_label;
      v_rg := coalesce(v_rg, '{}') || v_g.group_label;
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
      o_tie := v_i; o_home := v_rc[v_perm[v_i]]; o_away := v_wc[v_i]; return next;
    end loop;

  elsif v_mode = 'positions' then
    -- pares de posições da liga (ex.: Série B [[3,6],[4,5]]); o melhor colocado decide em casa
    v_i := 0;
    for pr in select * from jsonb_array_elements(p_phase #> '{pairing,pairs}') loop
      v_i := v_i + 1;
      select club_id into v_hi from public.sim_standings(p_season, p_comp, null) where pos = (pr ->> 0)::int;
      select club_id into v_lo from public.sim_standings(p_season, p_comp, null) where pos = (pr ->> 1)::int;
      o_tie := v_i;
      if v_legs = 2 then o_home := v_lo; o_away := v_hi; else o_home := v_hi; o_away := v_lo; end if;
      return next;
    end loop;

  elsif v_mode = 'champ_sf' then
    -- playoff da Championship: 3º x vencedor de pior campanha; 4º x o outro (melhor colocado decide em casa)
    select club_id into v_a from public.sim_standings(p_season, p_comp, null) where pos = (p_phase #>> '{pairing,seeds,0}')::int;
    select club_id into v_b from public.sim_standings(p_season, p_comp, null) where pos = (p_phase #>> '{pairing,seeds,1}')::int;
    select array_agg(x order by (v_pos ->> x)::int desc) into v_w from unnest(p_winners) x;   -- pior campanha primeiro
    o_tie := 1; o_home := v_w[1]; o_away := v_a; return next;
    o_tie := 2; o_home := v_w[2]; o_away := v_b; return next;

  elsif v_mode = 'bracket' then
    -- chave fixa: vencedor do confronto k x vencedor do k+1; com seed_from, o melhor colocado decide em casa
    for v_i in 1 .. coalesce(array_length(p_winners, 1), 0) / 2 loop
      v_a := p_winners[2 * v_i - 1]; v_b := p_winners[2 * v_i];
      if v_seedf is not null and (v_pos ->> v_a)::int < (v_pos ->> v_b)::int then
        v_hi := v_a; v_lo := v_b;
      elsif v_seedf is not null then
        v_hi := v_b; v_lo := v_a;
      elsif random() < 0.5 then v_hi := v_a; v_lo := v_b;
      else v_hi := v_b; v_lo := v_a; end if;
      o_tie := v_i;
      if v_legs = 2 then o_home := v_lo; o_away := v_hi; else o_home := v_hi; o_away := v_lo; end if;
      return next;
    end loop;

  elsif v_mode = 'ucl_po' then
    -- (9º/10º x 23º/24º), (11º/12º x 21º/22º), (13º/14º x 19º/20º), (15º/16º x 17º/18º); cabeça de chave decide em casa
    for v_grp in 0 .. 3 loop
      select array_agg(club_id order by random()) into v_s1 from public.sim_standings(p_season, p_comp, null)
       where pos in (9 + 2 * v_grp, 10 + 2 * v_grp);
      select array_agg(club_id order by random()) into v_s2 from public.sim_standings(p_season, p_comp, null)
       where pos in (23 - 2 * v_grp, 24 - 2 * v_grp);
      for v_i in 1 .. 2 loop
        v_tie := v_tie + 1;
        o_tie := v_tie; o_home := v_s2[v_i]; o_away := v_s1[v_i]; return next;
      end loop;
    end loop;

  elsif v_mode = 'ucl_r16' then
    -- vencedores do playoff chegam na ordem dos confrontos: 1-2 (9º/10º), 3-4 (11º/12º), 5-6 (13º/14º), 7-8 (15º/16º)
    -- 1º/2º x vencedores 7-8 · 7º/8º x vencedores 1-2 · 3º/4º x vencedores 5-6 · 5º/6º x vencedores 3-4
    -- ordem dos confrontos = chave: [1/2, 7/8, 3/4, 5/6] de um lado e os outros do outro (1º e 2º em lados opostos)
    for v_grp in 1 .. 4 loop
      select array_agg(club_id order by random()) into v_s1 from public.sim_standings(p_season, p_comp, null)
       where pos in (v_seedpairs[v_grp][1], v_seedpairs[v_grp][2]);
      v_wc := coalesce(v_wc, '{}') || v_s1;
    end loop;
    -- v_wc = [s(1/2)a, s(1/2)b, s(7/8)a, s(7/8)b, s(3/4)a, s(3/4)b, s(5/6)a, s(5/6)b]
    v_rc := array[p_winners[7], p_winners[8], p_winners[1], p_winners[2], p_winners[5], p_winners[6], p_winners[3], p_winners[4]];
    if random() < 0.5 then v_rc := array[v_rc[2], v_rc[1], v_rc[3], v_rc[4], v_rc[5], v_rc[6], v_rc[7], v_rc[8]]; end if;
    if random() < 0.5 then v_rc := array[v_rc[1], v_rc[2], v_rc[4], v_rc[3], v_rc[5], v_rc[6], v_rc[7], v_rc[8]]; end if;
    if random() < 0.5 then v_rc := array[v_rc[1], v_rc[2], v_rc[3], v_rc[4], v_rc[6], v_rc[5], v_rc[7], v_rc[8]]; end if;
    if random() < 0.5 then v_rc := array[v_rc[1], v_rc[2], v_rc[3], v_rc[4], v_rc[5], v_rc[6], v_rc[8], v_rc[7]]; end if;
    -- lado A: confrontos 1-4 ; lado B: 5-8
    o_tie := 1; o_home := v_rc[1]; o_away := v_wc[1]; return next;
    o_tie := 2; o_home := v_rc[3]; o_away := v_wc[3]; return next;
    o_tie := 3; o_home := v_rc[5]; o_away := v_wc[5]; return next;
    o_tie := 4; o_home := v_rc[7]; o_away := v_wc[7]; return next;
    o_tie := 5; o_home := v_rc[2]; o_away := v_wc[2]; return next;
    o_tie := 6; o_home := v_rc[4]; o_away := v_wc[4]; return next;
    o_tie := 7; o_home := v_rc[6]; o_away := v_wc[6]; return next;
    o_tie := 8; o_home := v_rc[8]; o_away := v_wc[8]; return next;

  else
    raise exception 'Chaveamento desconhecido: %', v_mode;
  end if;
end;
$$;

-- ---------------------------------------------------------------------
-- 6) Cria os jogos de uma fase
-- ---------------------------------------------------------------------
create or replace function public.sim_phase_create(p_season uuid, p_comp text, p_phase_id text, p_winners text[])
returns int language plpgsql security definer set search_path = public as $$
declare
  v_ph    jsonb := public.sim_phase(p_comp, p_phase_id);
  v_type  text;
  v_legs  int;
  v_teams text[];
  v_g     record;
  r       record;
  v_n     int := 0;
begin
  if v_ph is null then raise exception 'Fase % não existe em %', p_phase_id, p_comp; end if;
  if exists (select 1 from public.season_fixtures where season_id = p_season and competition_id = p_comp and stage = p_phase_id) then
    return 0;                                                    -- já criada (idempotente)
  end if;
  v_type := v_ph ->> 'type';
  v_legs := coalesce((v_ph ->> 'legs')::int, 1);

  if v_type = 'league' then
    select array_agg(club_id order by random()) into v_teams
      from public.season_participants where season_id = p_season and competition_id = p_comp
       and (entry_phase is null or entry_phase = p_phase_id);
    if coalesce(array_length(v_teams, 1), 0) < 2 or array_length(v_teams, 1) % 2 = 1 then
      raise exception 'Liga % precisa de número par de clubes (tem %)', p_comp, coalesce(array_length(v_teams, 1), 0);
    end if;
    insert into public.season_fixtures (season_id, competition_id, stage, round_no, home_club, away_club)
    select p_season, p_comp, p_phase_id, rr.round_no, rr.home, rr.away from public.sim_round_robin(v_teams, v_legs = 2) rr;
    get diagnostics v_n = row_count;

  elsif v_type = 'groups' then
    for v_g in select distinct group_label from public.season_participants
                where season_id = p_season and competition_id = p_comp and group_label is not null order by 1 loop
      select array_agg(club_id order by random()) into v_teams
        from public.season_participants where season_id = p_season and competition_id = p_comp and group_label = v_g.group_label;
      insert into public.season_fixtures (season_id, competition_id, stage, round_no, group_label, home_club, away_club)
      select p_season, p_comp, p_phase_id, rr.round_no, v_g.group_label, rr.home, rr.away from public.sim_round_robin(v_teams, v_legs = 2) rr;
      v_n := v_n + array_length(v_teams, 1) * (array_length(v_teams, 1) - 1) / (case when v_legs = 2 then 1 else 2 end);
    end loop;

  elsif v_type = 'swiss' then
    v_n := public.sim_swiss_create(p_season, p_comp, v_ph);

  elsif v_type = 'knockout' then
    for r in select * from public.sim_phase_pairs(p_season, p_comp, v_ph, p_winners) loop
      if r.o_home is null or r.o_away is null then raise exception 'Confronto incompleto em % / %', p_comp, p_phase_id; end if;
      insert into public.season_fixtures (season_id, competition_id, stage, round_no, tie_no, leg, home_club, away_club)
      values (p_season, p_comp, p_phase_id, 1, r.o_tie, 1, r.o_home, r.o_away);
      v_n := v_n + 1;
      if v_legs = 2 then
        insert into public.season_fixtures (season_id, competition_id, stage, round_no, tie_no, leg, home_club, away_club)
        values (p_season, p_comp, p_phase_id, 2, r.o_tie, 2, r.o_away, r.o_home);
        v_n := v_n + 1;
      end if;
    end loop;
    if v_n = 0 then raise exception 'Fase eliminatória sem confrontos: % / %', p_comp, p_phase_id; end if;
  else
    raise exception 'Tipo de fase desconhecido: %', v_type;
  end if;
  return v_n;
end;
$$;

-- ---------------------------------------------------------------------
-- 7) Fecha os confrontos de uma fase (respeita o vencedor que o motor já gravou)
--    tie = 'higher_seed': empate no agregado classifica quem decidiu em casa (o mais bem colocado)
-- ---------------------------------------------------------------------
create or replace function public.sim_resolve_ties(p_season uuid, p_comp text, p_stage text)
returns text[] language plpgsql security definer set search_path = public as $$
declare
  v_ph      jsonb := public.sim_phase(p_comp, p_stage);
  v_rule    text  := coalesce(public.sim_phase(p_comp, p_stage) ->> 'tie', 'penalties');
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
      elsif v_rule = 'higher_seed' then
        v_w := v_lasthome;
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

-- ---------------------------------------------------------------------
-- 8) Avança a competição quando a fase atual termina
-- ---------------------------------------------------------------------
create or replace function public.sim_advance(p_season uuid, p_comp text)
returns boolean language plpgsql security definer set search_path = public as $$
declare
  v_sc  public.season_competitions;
  v_cur jsonb;
  v_nxt jsonb;
  v_w   text[];
begin
  select * into v_sc from public.season_competitions where season_id = p_season and competition_id = p_comp for update;
  if not found or v_sc.status = 'finished' then return false; end if;
  if exists (select 1 from public.season_fixtures where season_id = p_season and competition_id = p_comp and status = 'pending') then
    return false;                                  -- ainda há jogos na fase atual
  end if;
  if not exists (select 1 from public.season_fixtures where season_id = p_season and competition_id = p_comp and stage = v_sc.stage) then
    return false;
  end if;

  v_cur := public.sim_phase(p_comp, v_sc.stage);
  if v_cur is null then
    -- temporada criada antes da configuração por fases: encerra do jeito antigo
    if v_sc.stage = 'final' then perform public.sim_resolve_ties(p_season, p_comp, 'final'); end if;
    perform public.sim_finish_competition(p_season, p_comp);
    return true;
  end if;
  if v_cur ->> 'type' = 'knockout' then
    v_w := public.sim_resolve_ties(p_season, p_comp, v_sc.stage);
  end if;
  v_nxt := public.sim_phase_at(p_comp, (v_cur ->> 'idx')::int + 1);
  if v_nxt is null then
    perform public.sim_finish_competition(p_season, p_comp);
  else
    perform public.sim_phase_create(p_season, p_comp, v_nxt ->> 'id', v_w);
    update public.season_competitions set stage = v_nxt ->> 'id' where season_id = p_season and competition_id = p_comp;
  end if;
  return true;
end;
$$;

-- ---------------------------------------------------------------------
-- 9) Classificação com os critérios de desempate de cada competição
--    points, wins, away_wins, gd, gf, away_gf, h2h_pts, h2h_gd, h2h_gf, h2h_away_gf (confronto direto entre empatados em pontos),
--    opp_pts, opp_gd, opp_gf (soma dos adversários enfrentados — fase de liga da UCL), reds / yellows / fairplay (menos é melhor)
-- ---------------------------------------------------------------------
drop function if exists public.sim_standings(uuid, text, text);
create or replace function public.sim_standings(p_season uuid, p_comp text, p_group text default null)
returns table (pos int, club_id text, played int, wins int, draws int, losses int, gf int, ga int, gd int, points int)
language sql stable set search_path = public as $$
  with x_members as (
    select distinct m.c as x_club from (
      select sp.club_id as c from public.season_participants sp
       where sp.season_id = p_season and sp.competition_id = p_comp and (p_group is null or sp.group_label = p_group)
         and (sp.entry_phase is null or sp.entry_phase in ('league', 'group'))
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
           (count(*) filter (where r.x_for > r.x_against and r.x_away))::int as x_aw,
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
           sum(r.x_for)::int as h_gf,
           (coalesce(sum(r.x_for) filter (where r.x_away), 0))::int as h_agf
      from x_res r
      join x_pts a1 on a1.x_club = r.x_c
      join x_pts a2 on a2.x_club = r.x_o
     where a1.x_pt = a2.x_pt
     group by r.x_c
  ),
  x_opp as (
    select r.x_c, sum(o.x_pt)::int as o_pt, sum(o.x_gf - o.x_ga)::int as o_gd, sum(o.x_gf)::int as o_gf
      from x_res r join x_pts o on o.x_club = r.x_o
     group by r.x_c
  ),
  x_full as (
    select p.*,
           (select array_agg(case t when 'points' then p.x_pt when 'wins' then p.x_w when 'away_wins' then p.x_aw
                                    when 'gd' then p.x_gf - p.x_ga when 'gf' then p.x_gf when 'away_gf' then p.x_agf
                                    when 'h2h_pts' then coalesce(h.h_pt, 0) when 'h2h_gd' then coalesce(h.h_gd, 0)
                                    when 'h2h_gf' then coalesce(h.h_gf, 0) when 'h2h_away_gf' then coalesce(h.h_agf, 0)
                                    when 'opp_pts' then coalesce(o.o_pt, 0) when 'opp_gd' then coalesce(o.o_gd, 0)
                                    when 'opp_gf' then coalesce(o.o_gf, 0)
                                    when 'reds' then -coalesce(c.x_r, 0) when 'yellows' then -coalesce(c.x_y, 0)
                                    when 'fairplay' then -(coalesce(c.x_y, 0) + 3 * coalesce(c.x_r, 0)) else 0 end order by k)
              from jsonb_array_elements_text(coalesce((select sc.rules -> 'tiebreakers' from public.sim_competitions sc where sc.id = p_comp),
                                                      '["points","wins","gd","gf"]'::jsonb)) with ordinality as t(t, k)) as x_key
      from x_pts p
      left join x_h2h h on h.x_c = p.x_club
      left join x_opp o on o.x_c = p.x_club
      left join x_cards c on c.x_c = p.x_club
  )
  select (row_number() over (order by f.x_key desc, f.x_club))::int as pos,
         f.x_club as club_id, f.x_p as played, f.x_w as wins, f.x_d as draws, f.x_l as losses,
         f.x_gf as gf, f.x_ga as ga, (f.x_gf - f.x_ga) as gd, f.x_pt as points
    from x_full f
   order by 1;
$$;

-- ---------------------------------------------------------------------
-- 10) Fim de competição: campeão (liga = 1º colocado; copa = vencedor da final), resultado do seu clube e bônus
-- ---------------------------------------------------------------------
create or replace function public.sim_finish_competition(p_season uuid, p_comp text)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_s      public.career_seasons;
  v_comp   public.sim_competitions;
  v_ff     public.season_fixtures;
  v_champ  text;
  v_runner text;
  v_has    int;
  v_played int;
  v_pos    int;
  v_rank   int;
  v_last   text;
  v_code   text;
  v_label  text;
  v_xp     int := 0;
  v_coins  int := 0;
  v_cont   boolean;
  v_club   text;
  v_lastph jsonb;
  v_up     text;
begin
  select * into v_s from public.career_seasons where id = p_season;
  select * into v_comp from public.sim_competitions where id = p_comp;
  v_club := v_s.club_id;
  v_cont := v_comp.kind = 'continental';

  if coalesce(v_comp.rules ->> 'champion', case when v_comp.kind = 'league' then 'league' else 'final' end) = 'league' then
    select t.club_id into v_champ  from public.sim_standings(p_season, p_comp, null) t where t.pos = 1;
    select t.club_id into v_runner from public.sim_standings(p_season, p_comp, null) t where t.pos = 2;
  else
    v_lastph := public.sim_phase_at(p_comp, jsonb_array_length(public.sim_comp_phases(p_comp)));
    select * into v_ff from public.season_fixtures
     where season_id = p_season and competition_id = p_comp and stage = coalesce(v_lastph ->> 'id', 'final') and tie_winner is not null
     order by leg desc limit 1;
    v_champ  := v_ff.tie_winner;
    v_runner := case when v_ff.home_club = v_champ then v_ff.away_club else v_ff.home_club end;
  end if;

  select count(*) into v_has from public.season_fixtures
   where season_id = p_season and competition_id = p_comp and v_club is not null and (home_club = v_club or away_club = v_club);
  select count(*) into v_played from public.season_fixtures
   where season_id = p_season and competition_id = p_comp and player_match and (v_s.mode = 'player' or coach_club = v_club);

  if v_has > 0 then
    if v_comp.kind = 'league' then
      select t.pos into v_pos from public.sim_standings(p_season, p_comp, null) t where t.club_id = v_club;
      v_label := case when v_pos = 1 then 'Campeão' else v_pos::text || 'º lugar' end;
      -- playoff de acesso vencido
      select pr.upper_comp into v_up from public.sim_promotion_rules_for(v_s.region, v_s.year) pr where pr.lower_comp = p_comp limit 1;
      if v_up is not null and exists (select 1 from public.season_fixtures f where f.season_id = p_season and f.competition_id = p_comp
                                        and f.tie_winner = v_club and f.stage = (select promoted_playoff_phase from public.sim_promotion_rules_for(v_s.region, v_s.year) where lower_comp = p_comp limit 1)) then
        v_label := v_label || ' · acesso no playoff';
      elsif v_up is not null and v_pos <= (select promoted_direct from public.sim_promotion_rules_for(v_s.region, v_s.year) where lower_comp = p_comp limit 1) then
        v_label := v_label || ' · acesso';
      end if;
      v_code  := case when v_pos = 1 then 'p1' when v_pos <= 4 then 'p2_4' when v_pos <= 8 then 'p5_8' else 'pother' end;
    elsif v_champ = v_club then
      v_label := 'Campeão';       v_code := 'champion';
    elsif v_runner = v_club then
      v_label := 'Vice-campeão';  v_code := 'runner_up';
    else
      select f.stage into v_last from public.season_fixtures f
       where f.season_id = p_season and f.competition_id = p_comp and (f.home_club = v_club or f.away_club = v_club)
       order by public.sim_phase_index(p_comp, f.stage) desc limit 1;
      v_rank  := public.mgr_stage_rank(p_comp, v_last);
      v_code  := case v_rank when 4 then 'sf' when 3 then 'qf' when 2 then 'r16' else 'group' end;
      v_label := 'Eliminado: ' || lower(coalesce(public.sim_phase(p_comp, v_last) ->> 'label', v_last));
    end if;

    if v_played > 0 then
      v_xp := case v_code
        when 'p1' then 500 when 'p2_4' then 250 when 'p5_8' then 120 when 'pother' then 50
        when 'champion'   then case when v_cont then 600 else 400 end
        when 'runner_up'  then case when v_cont then 300 else 200 end
        when 'sf'         then case when v_cont then 150 else 100 end
        when 'qf'         then case when v_cont then 80  else 50  end
        when 'r16'        then case when v_cont then 40  else 0   end
        when 'group'      then case when v_cont then 20  else 0   end else 0 end;
      v_coins := case v_code
        when 'p1' then 3000 when 'p2_4' then 1500 when 'p5_8' then 700 when 'pother' then 250
        when 'champion'   then case when v_cont then 4000 else 2500 end
        when 'runner_up'  then case when v_cont then 2000 else 1200 end
        when 'sf'         then case when v_cont then 800  else 500  end
        when 'qf'         then case when v_cont then 400  else 250  end
        when 'r16'        then case when v_cont then 200  else 0    end
        when 'group'      then case when v_cont then 100  else 0    end else 0 end;
      -- liga da 2ª divisão paga proporcionalmente (multiplicador da competição)
      if v_comp.kind = 'league' and coalesce(v_comp.division, 1) > 1 then
        v_xp := round(v_xp * v_comp.xp_mult)::int;
        v_coins := round(v_coins * v_comp.xp_mult)::int;
      end if;

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
-- 11) Calendário: próximo "dia" = rodada do campeonato mais atrasado (rodadas feitas / rodadas previstas)
--     Empate: prioridade configurada (continental, copa, liga...).
-- ---------------------------------------------------------------------
create or replace function public.sim_next_event(p_season uuid, p_club text)
returns table (o_comp text, o_kind text, o_stage text, o_round int)
language sql stable set search_path = public as $$
  with x_rounds as (
    select f.competition_id as x_comp, f.stage as x_stage, f.round_no as x_round,
           bool_and(f.status = 'played') as x_done,
           coalesce(bool_or(f.status = 'pending' and (f.home_club = p_club or f.away_club = p_club)), false) as x_mine
      from public.season_fixtures f
     where f.season_id = p_season
     group by f.competition_id, f.stage, f.round_no
  ),
  x_pick as (
    select r.x_comp,
           (count(*) filter (where r.x_done))::numeric
             / greatest(coalesce((c.rules ->> 'calendar_rounds')::int,
                                 case r.x_comp when 'brasileirao' then 38 when 'copa_brasil' then 7 else 13 end), 1) as x_ratio,
           coalesce((c.rules ->> 'calendar_priority')::int, 9) as x_prio
      from x_rounds r join public.sim_competitions c on c.id = r.x_comp
     group by r.x_comp, c.rules
    having bool_or(not r.x_done)
     order by 2, 3, 1
     limit 1
  )
  select p.x_comp, (case when n.x_mine then 'mine' else 'free' end), n.x_stage, n.x_round
    from x_pick p
    join lateral (
      select * from x_rounds rr
       where rr.x_comp = p.x_comp and not rr.x_done
       order by public.sim_phase_index(rr.x_comp, rr.x_stage), rr.x_round
       limit 1
    ) n on true;
$$;

-- ---------------------------------------------------------------------
-- 12) Fim de temporada: acesso, rebaixamento e classificação continental (UMA vez por temporada)
-- ---------------------------------------------------------------------
create or replace function public.sim_season_transition(p_season uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_s      public.career_seasons;
  v_prev   jsonb;
  r        record;
  c        record;
  v_upper  text[];
  v_lower  text[];
  v_down   text[];
  v_up     text[];
  v_po     text[];
  v_n      int;
  v_res    jsonb := jsonb_build_object('leagues', '{}'::jsonb, 'promoted', '{}'::jsonb, 'relegated', '{}'::jsonb, 'qualified', '{}'::jsonb);
  v_q      text[];
  v_from   text;
begin
  select * into v_s from public.career_seasons where id = p_season for update;
  select result into v_prev from public.season_transitions where from_season = p_season;
  if found then return v_prev; end if;                         -- já aplicado: não roda de novo
  if exists (select 1 from public.season_fixtures where season_id = p_season and status = 'pending') then
    raise exception 'A temporada ainda tem jogos pendentes.';
  end if;

  -- ligas que não mudam (sem regra): ficam como estão
  for c in select sp.competition_id as comp, array_agg(sp.club_id order by sp.club_id) as clubs
             from public.season_participants sp join public.sim_competitions sc on sc.id = sp.competition_id
            where sp.season_id = p_season and sc.kind = 'league' group by sp.competition_id loop
    v_res := jsonb_set(v_res, array['leagues', c.comp], to_jsonb(c.clubs));
  end loop;

  for r in select * from public.sim_promotion_rules_for(v_s.region, v_s.year) loop
    -- só aplica se as DUAS divisões foram disputadas nesta temporada (temporadas antigas não tinham Série B)
    continue when not exists (select 1 from public.season_competitions where season_id = p_season and competition_id = r.upper_comp)
               or not exists (select 1 from public.season_competitions where season_id = p_season and competition_id = r.lower_comp);
    select array_agg(club_id order by club_id) into v_upper from public.season_participants where season_id = p_season and competition_id = r.upper_comp;
    select array_agg(club_id order by club_id) into v_lower from public.season_participants where season_id = p_season and competition_id = r.lower_comp;
    select count(*) into v_n from public.sim_standings(p_season, r.upper_comp, null);
    select array_agg(t.club_id order by t.pos) into v_down from public.sim_standings(p_season, r.upper_comp, null) t
     where t.pos > v_n - r.relegated;
    select array_agg(t.club_id order by t.pos) into v_up from public.sim_standings(p_season, r.lower_comp, null) t
     where t.pos <= r.promoted_direct;
    v_po := '{}';
    if r.promoted_playoff_phase is not null then
      select array_agg(f.tie_winner order by f.tie_no) into v_po from public.season_fixtures f
       where f.season_id = p_season and f.competition_id = r.lower_comp and f.stage = r.promoted_playoff_phase and f.tie_winner is not null;
      v_up := coalesce(v_up, '{}') || coalesce(v_po, '{}');
    end if;
    v_down := coalesce(v_down, '{}');
    v_up := coalesce(v_up, '{}');
    if cardinality(v_up) <> cardinality(v_down) then
      raise exception 'Acesso/rebaixamento desequilibrado em % / %: sobem %, caem %', r.upper_comp, r.lower_comp, cardinality(v_up), cardinality(v_down);
    end if;
    if exists (select 1 from unnest(v_up) u where u = any (v_down)) then raise exception 'Clube sobe e cai ao mesmo tempo'; end if;
    v_res := jsonb_set(v_res, array['leagues', r.upper_comp],
               to_jsonb(array(select x from unnest(v_upper) x where not x = any (v_down) union select unnest(v_up) order by 1)));
    v_res := jsonb_set(v_res, array['leagues', r.lower_comp],
               to_jsonb(array(select x from unnest(v_lower) x where not x = any (v_up) union select unnest(v_down) order by 1)));
    v_res := jsonb_set(v_res, array['promoted', r.upper_comp], to_jsonb(v_up));
    v_res := jsonb_set(v_res, array['relegated', r.lower_comp], to_jsonb(v_down));
  end loop;

  -- classificação continental: as vagas do país vão para os mais bem colocados da liga
  for c in select * from public.sim_competitions where region = v_s.region and active and kind = 'continental' loop
    v_from := c.rules #>> '{qualification,from}';
    continue when v_from is null
               or not exists (select 1 from public.season_competitions where season_id = p_season and competition_id = v_from);
    select count(*) into v_n from public.sim_competition_clubs cc join public.sim_clubs cl on cl.id = cc.club_id
     where cc.competition_id = c.id and cl.region = v_s.region;
    select array_agg(t.club_id order by t.pos) into v_q from public.sim_standings(p_season, v_from, null) t where t.pos <= v_n;
    v_res := jsonb_set(v_res, array['qualified', c.id], to_jsonb(coalesce(v_q, '{}')));
  end loop;

  insert into public.season_transitions (career_id, region, from_season, year, result)
  values (v_s.career_id, v_s.region, p_season, v_s.year, v_res)
  on conflict (from_season) do nothing;
  return (select result from public.season_transitions where from_season = p_season);
end;
$$;

-- ---------------------------------------------------------------------
-- 13) O clube ainda está vivo na competição? (participa e não foi eliminado; quem entra mais tarde conta como vivo)
-- ---------------------------------------------------------------------
create or replace function public.sim_club_alive(p_season uuid, p_comp text, p_club text)
returns boolean language sql stable set search_path = public as $$
  select exists (select 1 from public.season_participants where season_id = p_season and competition_id = p_comp and club_id = p_club)
     and coalesce((select status <> 'finished' from public.season_competitions where season_id = p_season and competition_id = p_comp), false)
     and not exists (
       select 1 from public.season_fixtures f
        where f.season_id = p_season and f.competition_id = p_comp and f.tie_winner is not null
          and (f.home_club = p_club or f.away_club = p_club) and f.tie_winner <> p_club)
     and not exists (   -- caiu na fase de liga/grupos (não aparece na fase atual de mata-mata)
       select 1 from public.season_competitions sc
        where sc.season_id = p_season and sc.competition_id = p_comp
          and public.sim_phase(p_comp, sc.stage) ->> 'type' = 'knockout'
          and exists (select 1 from public.season_fixtures f where f.season_id = p_season and f.competition_id = p_comp and f.stage = sc.stage)
          and not exists (select 1 from public.season_fixtures f where f.season_id = p_season and f.competition_id = p_comp and f.stage = sc.stage
                            and (f.home_club = p_club or f.away_club = p_club))
          and coalesce((select entry_phase from public.season_participants where season_id = p_season and competition_id = p_comp and club_id = p_club), '')
              not in (select x.ph ->> 'id' from jsonb_array_elements(public.sim_comp_phases(p_comp)) with ordinality as x(ph, o)
                       where x.o > public.sim_phase_index(p_comp, sc.stage)))
$$;
