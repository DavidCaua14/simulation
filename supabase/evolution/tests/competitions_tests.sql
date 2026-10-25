-- =====================================================================
-- TESTES DA EVOLUÇÃO — COMPETIÇÕES, ACESSO E REBAIXAMENTO (Etapas 2 e 3)
-- Rodar:  psql -v ON_ERROR_STOP=1 -f supabase/evolution/tests/competitions_tests.sql
-- Tudo acontece dentro de uma transação desfeita no final (ROLLBACK): não deixa lixo no banco.
-- Cada bloco levanta exceção ("FALHOU: ...") se a regra não for cumprida.
-- As temporadas de teste usam mode = 'player' (placar rápido, sem o motor de atributos) para simular
-- campeonatos inteiros em segundos; as REGRAS de formato, chave, desempate e acesso são as mesmas.
-- =====================================================================
begin;

create temp table t_ctx (k text primary key, v text);

-- carreira de teste
insert into auth.users (id) values ('99999999-9999-9999-9999-999999999999') on conflict do nothing;
insert into public.careers (id, user_id, nickname, club_id, country, age)
values ('99999999-0000-0000-0000-000000000001', '99999999-9999-9999-9999-999999999999', 'teste_evo', 'arsenal', 'ENG', 30);

-- ---------------------------------------------------------------------
-- T1) Dados de referência: quantidades, potes, fases de entrada, nenhum clube em duas divisões
-- ---------------------------------------------------------------------
do $$
declare v int;
begin
  select count(*) into v from sim_competition_clubs where competition_id = 'premier_league'; if v <> 20 then raise exception 'FALHOU T1: Premier League com % clubes', v; end if;
  select count(*) into v from sim_competition_clubs where competition_id = 'championship';   if v <> 24 then raise exception 'FALHOU T1: Championship com % clubes', v; end if;
  select count(*) into v from sim_competition_clubs where competition_id = 'serie_b';        if v <> 20 then raise exception 'FALHOU T1: Série B com % clubes', v; end if;
  select count(*) into v from sim_competition_clubs where competition_id = 'brasileirao';    if v <> 20 then raise exception 'FALHOU T1: Série A com % clubes', v; end if;
  select count(*) into v from sim_competition_clubs where competition_id = 'ucl';            if v <> 36 then raise exception 'FALHOU T1: UCL com % clubes', v; end if;
  select count(*) into v from (select seed from sim_competition_clubs where competition_id = 'ucl' group by seed having count(*) = 9) x;
  if v <> 4 then raise exception 'FALHOU T1: UCL sem 4 potes de 9'; end if;
  select count(*) into v from sim_competition_clubs where competition_id = 'fa_cup' and entry_phase = 'r3'; if v <> 24 then raise exception 'FALHOU T1: FA Cup r3 = %', v; end if;
  select count(*) into v from sim_competition_clubs where competition_id = 'fa_cup' and entry_phase = 'r4'; if v <> 20 then raise exception 'FALHOU T1: FA Cup r4 = %', v; end if;
  select count(*) into v from sim_competition_clubs where competition_id = 'efl_cup' and entry_phase = 'r1'; if v <> 24 then raise exception 'FALHOU T1: EFL Cup r1 = %', v; end if;
  select count(*) into v from (select club_id from sim_competition_clubs where competition_id in ('premier_league', 'championship') group by club_id having count(*) > 1) x;
  if v > 0 then raise exception 'FALHOU T1: clube em duas divisões inglesas'; end if;
  select count(*) into v from (select club_id from sim_competition_clubs where competition_id in ('brasileirao', 'serie_b') group by club_id having count(*) > 1) x;
  if v > 0 then raise exception 'FALHOU T1: clube em duas divisões brasileiras'; end if;
  -- todo clube de liga tem elenco
  select count(*) into v from sim_competition_clubs cc join sim_competitions c on c.id = cc.competition_id
   where c.kind = 'league' and not exists (select 1 from sim_players p where p.club_id = cc.club_id and p.active);
  if v > 0 then raise exception 'FALHOU T1: % clube(s) de liga sem elenco', v; end if;
  -- toda competição tem fases e fontes
  select count(*) into v from sim_competitions where active and (jsonb_array_length(coalesce(rules -> 'phases', '[]')) = 0 or jsonb_array_length(sources) = 0);
  if v > 0 then raise exception 'FALHOU T1: competição sem fases ou sem fonte'; end if;
  raise notice 'T1 ok: dados de referência';
end $$;

-- ---------------------------------------------------------------------
-- T2) Temporada inglesa: calendário de cada formato
-- ---------------------------------------------------------------------
do $$
declare
  v_s uuid;
  v int;
  r record;
begin
  v_s := sim_create_season('99999999-0000-0000-0000-000000000001', 'ENG');
  insert into t_ctx values ('eng1', v_s::text);
  select count(*) into v from season_fixtures where season_id = v_s and competition_id = 'premier_league'; if v <> 380 then raise exception 'FALHOU T2: PL com % jogos', v; end if;
  select count(*) into v from season_fixtures where season_id = v_s and competition_id = 'championship';   if v <> 552 then raise exception 'FALHOU T2: Championship com % jogos', v; end if;
  select count(*) into v from season_fixtures where season_id = v_s and competition_id = 'fa_cup';         if v <> 12 then raise exception 'FALHOU T2: FA Cup 3ª fase com % jogos', v; end if;
  select count(*) into v from season_fixtures where season_id = v_s and competition_id = 'efl_cup';        if v <> 12 then raise exception 'FALHOU T2: EFL Cup preliminar com % jogos', v; end if;
  select count(*) into v from season_fixtures where season_id = v_s and competition_id = 'ucl';            if v <> 144 then raise exception 'FALHOU T2: UCL fase de liga com % jogos', v; end if;
  -- só clubes da Championship na 3ª fase da FA Cup (Premier League entra na 4ª)
  select count(*) into v from season_fixtures f join season_participants sp on sp.season_id = f.season_id and sp.competition_id = 'premier_league'
     and sp.club_id in (f.home_club, f.away_club) where f.season_id = v_s and f.competition_id = 'fa_cup';
  if v > 0 then raise exception 'FALHOU T2: clube da Premier League na 3ª fase da FA Cup'; end if;
  -- UCL: 8 jogos por clube, 4 em casa, 2 adversários de cada pote, 1 jogo por rodada, sem repetir adversário
  for r in
    select sp.club_id,
           count(*) as games,
           count(*) filter (where f.home_club = sp.club_id) as home,
           count(distinct case when f.home_club = sp.club_id then f.away_club else f.home_club end) as opps,
           count(distinct f.round_no) as rounds
      from season_participants sp join season_fixtures f on f.season_id = sp.season_id and f.competition_id = 'ucl'
       and sp.club_id in (f.home_club, f.away_club)
     where sp.season_id = v_s and sp.competition_id = 'ucl' group by sp.club_id
  loop
    if r.games <> 8 or r.home <> 4 or r.opps <> 8 or r.rounds <> 8 then
      raise exception 'FALHOU T2: UCL % jogos=% casa=% adversários=% rodadas=%', r.club_id, r.games, r.home, r.opps, r.rounds;
    end if;
  end loop;
  select count(*) into v from (
    select sp.club_id, op.seed, count(*) c
      from season_participants sp
      join season_fixtures f on f.season_id = sp.season_id and f.competition_id = 'ucl' and sp.club_id in (f.home_club, f.away_club)
      join season_participants op on op.season_id = sp.season_id and op.competition_id = 'ucl'
       and op.club_id = case when f.home_club = sp.club_id then f.away_club else f.home_club end
     where sp.season_id = v_s and sp.competition_id = 'ucl' group by 1, 2) x where c <> 2;
  if v > 0 then raise exception 'FALHOU T2: UCL sem 2 adversários por pote'; end if;
  raise notice 'T2 ok: calendário inglês (PL 380, Championship 552, UCL 144, copas)';
end $$;

-- ---------------------------------------------------------------------
-- T3) Temporada inglesa completa: fases eliminatórias, campeões, playoff da Championship
-- ---------------------------------------------------------------------
update career_seasons set mode = 'player' where id = (select v::uuid from t_ctx where k = 'eng1');
do $$
declare
  v_s uuid := (select v::uuid from t_ctx where k = 'eng1');
  v int;
  c record;
  v_pos jsonb;
  r record;
begin
  for c in select competition_id from season_competitions where season_id = v_s loop
    perform sim_complete_competition(v_s, c.competition_id);
  end loop;
  select count(*) into v from season_competitions where season_id = v_s and (status <> 'finished' or champion_club is null);
  if v > 0 then raise exception 'FALHOU T3: competição sem campeão'; end if;
  -- FA Cup: 3ª fase 12 jogos, 4ª 16, 5ª 8, quartas 4, semi 2, final 1 (jogo único com prorrogação/pênaltis)
  for r in select * from (values ('fa_cup', 'r4', 16), ('fa_cup', 'r5', 8), ('fa_cup', 'qf', 4), ('fa_cup', 'sf', 2), ('fa_cup', 'final', 1),
                                 ('efl_cup', 'r3', 16), ('efl_cup', 'r4', 8), ('efl_cup', 'qf', 4), ('efl_cup', 'sf', 4), ('efl_cup', 'final', 1),
                                 ('ucl', 'po', 16), ('ucl', 'r16', 16), ('ucl', 'qf', 8), ('ucl', 'sf', 4), ('ucl', 'final', 1),
                                 ('championship', 'po_elim', 2), ('championship', 'po_sf', 4), ('championship', 'po_final', 1)) x(comp, stage, n) loop
    select count(*) into v from season_fixtures where season_id = v_s and competition_id = r.comp and stage = r.stage;
    if v <> r.n then raise exception 'FALHOU T3: % / % com % jogos (esperado %)', r.comp, r.stage, v, r.n; end if;
  end loop;
  -- UCL playoff: 9º-16º decidem em casa contra 17º-24º, nos pares oficiais
  select jsonb_object_agg(club_id, pos) into v_pos from sim_standings(v_s, 'ucl', null);
  for r in select * from season_fixtures where season_id = v_s and competition_id = 'ucl' and stage = 'po' and leg = 2 loop
    if (v_pos ->> r.home_club)::int not between 9 and 16 or (v_pos ->> r.away_club)::int not between 17 and 24
       or (v_pos ->> r.home_club)::int + (v_pos ->> r.away_club)::int not between 32 and 34 then
      raise exception 'FALHOU T3: playoff da UCL % (%) x % (%)', r.home_club, v_pos ->> r.home_club, r.away_club, v_pos ->> r.away_club;
    end if;
  end loop;
  -- oitavas: os 8 primeiros decidem em casa
  select count(*) into v from season_fixtures where season_id = v_s and competition_id = 'ucl' and stage = 'r16' and leg = 2 and (v_pos ->> home_club)::int > 8;
  if v > 0 then raise exception 'FALHOU T3: oitavas da UCL com mandante do 2º jogo fora do top 8'; end if;
  -- 25º a 36º eliminados: não aparecem no mata-mata
  select count(*) into v from season_fixtures where season_id = v_s and competition_id = 'ucl' and stage <> 'league'
     and ((v_pos ->> home_club)::int > 24 or (v_pos ->> away_club)::int > 24);
  if v > 0 then raise exception 'FALHOU T3: clube do 25º ao 36º no mata-mata'; end if;
  -- Championship: eliminatórias 5x8 e 6x7 na casa do mais bem colocado; semifinal com 3º e 4º decidindo em casa
  select jsonb_object_agg(club_id, pos) into v_pos from sim_standings(v_s, 'championship', null);
  for r in select * from season_fixtures where season_id = v_s and competition_id = 'championship' and stage = 'po_elim' loop
    if (v_pos ->> r.home_club)::int + (v_pos ->> r.away_club)::int <> 13 or (v_pos ->> r.home_club)::int > (v_pos ->> r.away_club)::int then
      raise exception 'FALHOU T3: eliminatória da Championship % x %', r.home_club, r.away_club;
    end if;
  end loop;
  select count(*) into v from season_fixtures where season_id = v_s and competition_id = 'championship' and stage = 'po_sf' and leg = 2
     and (v_pos ->> home_club)::int not in (3, 4);
  if v > 0 then raise exception 'FALHOU T3: semifinal do playoff sem o 3º/4º decidindo em casa'; end if;
  -- campeão da Championship é o 1º da liga (o playoff só define o 3º promovido)
  if (select champion_club from season_competitions where season_id = v_s and competition_id = 'championship')
     <> (select club_id from sim_standings(v_s, 'championship', null) where pos = 1) then
    raise exception 'FALHOU T3: campeão da Championship não é o 1º colocado';
  end if;
  raise notice 'T3 ok: temporada inglesa completa (copas, UCL e playoff)';
end $$;

-- ---------------------------------------------------------------------
-- T4) Acesso e rebaixamento (Inglaterra): quantidades, quem sobe/cai, idempotência
-- ---------------------------------------------------------------------
do $$
declare
  v_s  uuid := (select v::uuid from t_ctx where k = 'eng1');
  v_t  jsonb;
  v_t2 jsonb;
  v    int;
  v_up text[];
  v_down text[];
  v_pf text;
  v_new uuid;
begin
  v_t := sim_season_transition(v_s);
  select array_agg(x) into v_up from jsonb_array_elements_text(v_t -> 'promoted' -> 'premier_league') x;
  select array_agg(x) into v_down from jsonb_array_elements_text(v_t -> 'relegated' -> 'championship') x;
  if cardinality(v_up) <> 3 or cardinality(v_down) <> 3 then raise exception 'FALHOU T4: sobem % / caem %', cardinality(v_up), cardinality(v_down); end if;
  -- caem os 3 últimos da Premier League
  select count(*) into v from sim_standings(v_s, 'premier_league', null) t where t.pos >= 18 and t.club_id = any (v_down);
  if v <> 3 then raise exception 'FALHOU T4: rebaixados não são os 3 últimos'; end if;
  -- sobem 1º, 2º e o vencedor da final do playoff
  select tie_winner into v_pf from season_fixtures where season_id = v_s and competition_id = 'championship' and stage = 'po_final';
  select count(*) into v from sim_standings(v_s, 'championship', null) t where t.pos <= 2 and t.club_id = any (v_up);
  if v <> 2 or not v_pf = any (v_up) then raise exception 'FALHOU T4: promovidos errados (%), final do playoff: %', v_up, v_pf; end if;
  if jsonb_array_length(v_t -> 'leagues' -> 'premier_league') <> 20 or jsonb_array_length(v_t -> 'leagues' -> 'championship') <> 24 then
    raise exception 'FALHOU T4: número de participantes mudou';
  end if;
  -- rodar de novo não aplica outra vez
  v_t2 := sim_season_transition(v_s);
  if v_t2 <> v_t then raise exception 'FALHOU T4: segunda execução mudou o resultado'; end if;
  select count(*) into v from season_transitions where from_season = v_s;
  if v <> 1 then raise exception 'FALHOU T4: transição gravada % vezes', v; end if;
  -- inserir a mesma transição de novo é barrado pela chave única
  begin
    insert into season_transitions (career_id, region, from_season, year, result) values ('99999999-0000-0000-0000-000000000001', 'ENG', v_s, 2026, '{}');
    raise exception 'FALHOU T4: chave única não barrou transição duplicada';
  exception when unique_violation then null;
  end;
  -- próxima temporada usa as divisões novas e os classificados para a UCL
  update career_seasons set status = 'finished' where id = v_s;
  v_new := sim_create_season('99999999-0000-0000-0000-000000000001', 'ENG');
  insert into t_ctx values ('eng2', v_new::text);
  select count(*) into v from season_participants where season_id = v_new and competition_id = 'premier_league' and club_id = any (v_up);
  if v <> 3 then raise exception 'FALHOU T4: promovidos não estão na Premier League nova'; end if;
  select count(*) into v from season_participants where season_id = v_new and competition_id = 'championship' and club_id = any (v_down);
  if v <> 3 then raise exception 'FALHOU T4: rebaixados não estão na Championship nova'; end if;
  select count(*) into v from season_participants sp join sim_clubs c on c.id = sp.club_id
   where sp.season_id = v_new and sp.competition_id = 'ucl' and c.region = 'ENG'
     and sp.club_id in (select x from jsonb_array_elements_text(v_t -> 'qualified' -> 'ucl') x);
  if v <> 5 then raise exception 'FALHOU T4: classificados ingleses na UCL = %', v; end if;
  select count(*) into v from season_participants where season_id = v_new and competition_id = 'ucl';
  if v <> 36 then raise exception 'FALHOU T4: UCL nova com % clubes', v; end if;
  -- um clube não pode estar em duas divisões na mesma temporada
  begin
    insert into season_participants (season_id, competition_id, club_id, division_key)
    values (v_new, 'championship', (select club_id from season_participants where season_id = v_new and competition_id = 'premier_league' limit 1), 'ENG:league');
    raise exception 'FALHOU T4: clube entrou em duas divisões';
  exception when unique_violation then null;
  end;
  -- histórico preservado: temporada anterior continua com seus jogos e campeões
  select count(*) into v from season_fixtures where season_id = v_s;
  if v < 1000 then raise exception 'FALHOU T4: histórico da temporada anterior perdido'; end if;
  raise notice 'T4 ok: acesso/rebaixamento inglês (3+3, playoff, idempotente, classificação para a UCL)';
end $$;

-- ---------------------------------------------------------------------
-- T5) Brasil: Série A + Série B, playoff do acesso (empate no agregado classifica o mais bem colocado), 4 sobem e 4 caem
-- ---------------------------------------------------------------------
update careers set club_id = 'goias' where id = '99999999-0000-0000-0000-000000000001';
update career_seasons set status = 'finished' where id = (select v::uuid from t_ctx where k = 'eng2');   -- volta a ficar ativa no T6
do $$
declare
  v_s uuid;
  v   int;
  c   record;
  v_t jsonb;
  v_po text[];
  r   record;
  v_pos jsonb;
begin
  v_s := sim_create_season('99999999-0000-0000-0000-000000000001', 'BRA');
  insert into t_ctx values ('bra1', v_s::text);
  update career_seasons set mode = 'player' where id = v_s;
  select count(*) into v from season_fixtures where season_id = v_s and competition_id = 'serie_b'; if v <> 380 then raise exception 'FALHOU T5: Série B com % jogos', v; end if;
  -- Copa do Brasil: confrontos de referência (T1..T8), seed 1 manda o jogo de ida
  select count(*) into v from season_fixtures f join sim_competition_clubs cc on cc.competition_id = 'copa_brasil' and cc.club_id = f.home_club and cc.seed = 1
   where f.season_id = v_s and f.competition_id = 'copa_brasil' and f.stage = 'r16' and f.leg = 1;
  if v <> 8 then raise exception 'FALHOU T5: oitavas da Copa do Brasil fora da chave de referência'; end if;

  -- força um empate no agregado do playoff para testar o critério "mais bem colocado"
  perform sim_complete_competition(v_s, 'brasileirao');
  perform sim_complete_competition(v_s, 'copa_brasil');
  perform sim_complete_competition(v_s, 'libertadores');
  -- joga só a liga da Série B
  for v in 1 .. 38 loop perform sim_play_round(v_s, 'serie_b', 'league', v); end loop;
  perform sim_advance(v_s, 'serie_b');
  select jsonb_object_agg(club_id, pos) into v_pos from sim_standings(v_s, 'serie_b', null);
  for r in select * from season_fixtures where season_id = v_s and competition_id = 'serie_b' and stage = 'po_sf' and leg = 2 loop
    if (v_pos ->> r.home_club)::int > (v_pos ->> r.away_club)::int then raise exception 'FALHOU T5: pior colocado decide em casa no playoff'; end if;
  end loop;
  update season_fixtures set home_goals = 1, away_goals = 1, status = 'played', played_at = now()
   where season_id = v_s and competition_id = 'serie_b' and stage = 'po_sf';
  perform sim_advance(v_s, 'serie_b');
  for r in select * from season_fixtures where season_id = v_s and competition_id = 'serie_b' and stage = 'po_sf' and leg = 2 loop
    if r.tie_winner <> r.home_club then raise exception 'FALHOU T5: empate no agregado não classificou o mais bem colocado'; end if;
    if r.home_pens is not null then raise exception 'FALHOU T5: playoff da Série B foi aos pênaltis'; end if;
  end loop;
  if (select status from season_competitions where season_id = v_s and competition_id = 'serie_b') <> 'finished' then
    raise exception 'FALHOU T5: Série B não encerrou depois do playoff';
  end if;

  v_t := sim_season_transition(v_s);
  if jsonb_array_length(v_t -> 'promoted' -> 'brasileirao') <> 4 or jsonb_array_length(v_t -> 'relegated' -> 'serie_b') <> 4 then
    raise exception 'FALHOU T5: Brasil sobem % / caem %', v_t -> 'promoted' -> 'brasileirao', v_t -> 'relegated' -> 'serie_b';
  end if;
  select array_agg(tie_winner) into v_po from season_fixtures where season_id = v_s and competition_id = 'serie_b' and stage = 'po_sf' and leg = 2;
  select count(*) into v from jsonb_array_elements_text(v_t -> 'promoted' -> 'brasileirao') x where x = any (v_po) or x in (select club_id from sim_standings(v_s, 'serie_b', null) where pos <= 2);
  if v <> 4 then raise exception 'FALHOU T5: promovidos não são top 2 + vencedores do playoff'; end if;
  select count(*) into v from jsonb_array_elements_text(v_t -> 'relegated' -> 'serie_b') x where x in (select club_id from sim_standings(v_s, 'brasileirao', null) where pos >= 17);
  if v <> 4 then raise exception 'FALHOU T5: rebaixados não são os 4 últimos da Série A'; end if;
  raise notice 'T5 ok: Série A/Série B (playoff com critério do mais bem colocado, 4 sobem e 4 caem)';
end $$;

-- ---------------------------------------------------------------------
-- T6) Regras da fase chegam ao motor da partida (mando neutro, prorrogação, critério de empate)
-- ---------------------------------------------------------------------
do $$
declare
  v_s uuid := (select v::uuid from t_ctx where k = 'eng2');
  v_f bigint;
  v_st jsonb;
begin
  update career_seasons set status = 'finished' where id = (select v::uuid from t_ctx where k = 'bra1');
  update career_seasons set mode = 'coach', status = 'active' where id = v_s;
  perform mgr_init_world('99999999-0000-0000-0000-000000000001');
  -- 3ª fase da FA Cup: jogo único, decide o confronto, prorrogação e pênaltis
  select id into v_f from season_fixtures where season_id = v_s and competition_id = 'fa_cup' limit 1;
  perform mgr_match_create(v_f, '99999999-0000-0000-0000-000000000001', null, null);
  select state into v_st from mgr_matches where fixture_id = v_f;
  if not (v_st ->> 'decisive')::boolean or not (v_st ->> 'extra_time_rule')::boolean or (v_st ->> 'neutral')::boolean then
    raise exception 'FALHOU T6: FA Cup 3ª fase com estado %', v_st;
  end if;
  -- fase preliminar da EFL Cup: pênaltis direto (sem prorrogação)
  select id into v_f from season_fixtures where season_id = v_s and competition_id = 'efl_cup' limit 1;
  perform mgr_match_create(v_f, '99999999-0000-0000-0000-000000000001', null, null);
  select state into v_st from mgr_matches where fixture_id = v_f;
  if not (v_st ->> 'decisive')::boolean or (v_st ->> 'extra_time_rule')::boolean then raise exception 'FALHOU T6: EFL Cup preliminar com estado %', v_st; end if;
  -- fase de liga da UCL: não decide confronto
  select id into v_f from season_fixtures where season_id = v_s and competition_id = 'ucl' limit 1;
  perform mgr_match_create(v_f, '99999999-0000-0000-0000-000000000001', null, null);
  select state into v_st from mgr_matches where fixture_id = v_f;
  if (v_st ->> 'decisive')::boolean then raise exception 'FALHOU T6: jogo da fase de liga marcado como decisivo'; end if;
  -- banco da Premier League: 9 reservas (regulamento)
  select id into v_f from season_fixtures where season_id = v_s and competition_id = 'premier_league' limit 1;
  perform mgr_match_create(v_f, '99999999-0000-0000-0000-000000000001', null, null);
  if (select count(*) from mgr_match_players where fixture_id = v_f and side = 'h' and status = 'bench') > 9 then
    raise exception 'FALHOU T6: banco da Premier League com mais de 9';
  end if;
  raise notice 'T6 ok: regras da fase no motor da partida';
end $$;

-- ---------------------------------------------------------------------
-- T7) Configuração dos campeonatos antigos equivale ao comportamento anterior
-- ---------------------------------------------------------------------
do $$
begin
  if (sim_phase('copa_brasil', 'final') ->> 'legs')::int <> 1 or (sim_phase('copa_brasil', 'final') ->> 'extra_time')::boolean
     or not (sim_phase('copa_brasil', 'final') ->> 'neutral')::boolean then raise exception 'FALHOU T7: final da Copa do Brasil'; end if;
  if not (sim_phase('libertadores', 'final') ->> 'extra_time')::boolean then raise exception 'FALHOU T7: final da Libertadores sem prorrogação'; end if;
  if (sim_phase('copa_brasil', 'r16') ->> 'legs')::int <> 2 or (sim_phase('copa_brasil', 'r16') ->> 'extra_time')::boolean then
    raise exception 'FALHOU T7: oitavas da Copa do Brasil';
  end if;
  if mgr_stage_rank('libertadores', 'qf') <> mgr_stage_rank('qf') or mgr_stage_rank('copa_brasil', 'final') <> mgr_stage_rank('final') then
    raise exception 'FALHOU T7: ranking de fases mudou';
  end if;
  raise notice 'T7 ok: Brasileirão, Copa do Brasil e Libertadores com as mesmas regras de antes';
end $$;

select 'TODOS OS TESTES DE COMPETIÇÕES PASSARAM' as resultado;
rollback;
