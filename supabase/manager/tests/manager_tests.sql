-- =====================================================================
-- TESTES do modo treinador (rodar num banco de DESENVOLVIMENTO depois de 01..06)
--   psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f supabase/manager/tests/manager_tests.sql
-- Tudo roda dentro de uma transação que termina em ROLLBACK: nada fica gravado.
-- Cada teste usa ASSERT: se algo falhar, o script para com a mensagem do teste.
-- =====================================================================
begin;
set local client_min_messages = notice;

-- usuário/carreira de teste
insert into auth.users (id) values ('7e57c0de-0000-0000-0000-000000000001') on conflict do nothing;
insert into public.careers (id, user_id, nickname, club_id, country, bonus_energy)
values ('7e57c0de-0000-0000-0000-0000000000ca', '7e57c0de-0000-0000-0000-000000000001', 'teste', 'palmeiras', 'BR', 500);

-- ---------------------------------------------------------------------
-- T0. Dados: elencos importados, sem jogador repetido em dois clubes, atributos na faixa
-- ---------------------------------------------------------------------
do $$
declare n int;
begin
  select count(*) into n from public.sim_players where active;
  assert n > 1000, 'T0: elencos não importados (rode 02_players_seed.sql)';
  select count(*) into n from (select id from public.sim_players where active group by id having count(distinct club_id) > 1) x;
  assert n = 0, 'T0: jogador ativo em mais de um clube';
  select count(*) into n from public.sim_player_attrs a where least(a.finishing, a.passing, a.tackling, a.pace) < 1 or greatest(a.finishing, a.passing, a.tackling, a.pace) > 99;
  assert n = 0, 'T0: atributo fora de 1..99';
  select count(*) into n from (select club_id from public.sim_players where active and club_id is not null group by club_id having count(*) filter (where position = 'GOL') = 0) x;
  assert n = 0, 'T0: clube sem goleiro';
  raise notice 'T0 ok: dados dos elencos';
end $$;

-- ---------------------------------------------------------------------
-- T1. Início da carreira (via RPC, como o app): treinador empregado, temporada ativa, escalação válida
-- ---------------------------------------------------------------------
set local role authenticated;
set local request.jwt.claim.sub = '7e57c0de-0000-0000-0000-000000000001';
do $$
declare h jsonb;
begin
  h := public.mgr_hub();
  assert h -> 'coach' ->> 'status' = 'employed', 'T1: treinador deveria começar empregado';
  assert h -> 'coach' ->> 'club_id' = 'palmeiras', 'T1: clube inicial errado';
  assert h -> 'season' ->> 'status' = 'active', 'T1: temporada deveria estar ativa';
  assert jsonb_array_length(h -> 'objectives') > 0, 'T1: diretoria sem objetivos';
  raise notice 'T1 ok: carreira criada';
end $$;

-- ---------------------------------------------------------------------
-- T2. Partida ao vivo: energia cobrada uma vez, etapas idempotentes, substituição e tática no meio do jogo
-- ---------------------------------------------------------------------
do $$
declare
  h jsonb; p jsonb; p2 jsonb; e0 int; e1 int; fx bigint; n1 int; n2 int; sub_out text; sub_in text; ev jsonb;
begin
  -- avança até o dia de jogo do seu clube
  for i in 1 .. 20 loop
    h := public.mgr_hub();
    exit when h -> 'next_event' ->> 'kind' = 'mine';
    perform public.mgr_advance(false);
  end loop;
  assert h -> 'next_event' ->> 'kind' = 'mine', 'T2: não chegou ao jogo do clube';
  e0 := (h -> 'career' ->> 'energy')::int + (h -> 'career' ->> 'bonus_energy')::int;
  p := public.mgr_match_start();
  fx := (p ->> 'fixture_id')::bigint;
  p2 := public.mgr_match_start();                       -- retomar não cobra de novo
  h := public.mgr_hub();
  e1 := (h -> 'career' ->> 'energy')::int + (h -> 'career' ->> 'bonus_energy')::int;
  assert e0 - e1 = 1, format('T2: energia cobrada %s vezes', e0 - e1);
  assert (p2 ->> 'fixture_id')::bigint = fx, 'T2: retomar abriu outra partida';

  p := public.mgr_match_step(fx, 0, 20, null, false, 0);
  n1 := jsonb_array_length(p -> 'events');
  p2 := public.mgr_match_step(fx, 0, 20, null, false, 0); -- mesma etapa de novo (rede caiu): replay, nada muda
  n2 := jsonb_array_length(p2 -> 'events');
  assert n1 = n2 and (p2 ->> 'minute')::int = (p ->> 'minute')::int, 'T2: etapa repetida alterou a partida';
  assert p -> 'score' = p2 -> 'score', 'T2: placar mudou no replay';

  -- substituição + postura ofensiva a partir do minuto atual
  select x ->> 'id' into sub_out from jsonb_array_elements(p -> 'players') x
   where x ->> 'side' = p ->> 'user_side' and x ->> 'status' = 'on' and x ->> 'pos' <> 'GOL' limit 1;
  select x ->> 'id' into sub_in from jsonb_array_elements(p -> 'players') x
   where x ->> 'side' = p ->> 'user_side' and x ->> 'status' = 'bench' limit 1;
  if (p ->> 'minute')::int < 45 and (p ->> 'status') = 'live' then
    p := public.mgr_match_step(fx, (p ->> 'minute')::int, (p ->> 'minute')::int + 5,
           jsonb_build_object('subs', jsonb_build_array(jsonb_build_object('out', sub_out, 'in', sub_in)),
                              'tactics', jsonb_build_object('mentality', 2)), false, 0);
    select x into ev from jsonb_array_elements(p -> 'players') x where x ->> 'id' = sub_in;
    assert ev ->> 'status' = 'on', 'T2: reserva não entrou';
    select x into ev from jsonb_array_elements(p -> 'players') x where x ->> 'id' = sub_out;
    assert ev ->> 'status' = 'off', 'T2: titular não saiu';
    assert (p -> 'tactics' -> (p ->> 'user_side') ->> 'mentality')::int = 2, 'T2: tática não aplicada';
  end if;

  -- termina (o auxiliar decide o resto) e confere o pós-jogo
  p := public.mgr_match_step(fx, (p ->> 'minute')::int, 120, null, true, 0);
  assert p ->> 'status' = 'finished', 'T2: partida não terminou';
  assert p -> 'summary' ? 'board' and p -> 'summary' ? 'fans' and p -> 'summary' ? 'reputation', 'T2: pós-jogo sem consequências';
  assert (select status from public.season_fixtures where id = fx) = 'played', 'T2: jogo não gravado';
  assert (select count(*) from public.season_fixtures where id = fx and coach_club is not null and player_match), 'T2: jogo sem o clube do treinador';
  raise notice 'T2 ok: partida ao vivo (energia, replay idempotente, substituição, tática, fim)';
end $$;

reset role;

-- ---------------------------------------------------------------------
-- T3. Táticas mudam o jogo: postura ofensiva gera mais finalizações do que a retranca (mesmo confronto)
-- ---------------------------------------------------------------------
do $$
declare
  v_car uuid := '7e57c0de-0000-0000-0000-0000000000ca';
  fx bigint; club text; lu jsonb; v_side char; sh_att numeric := 0; sh_def numeric := 0; ga_att numeric := 0; ga_def numeric := 0;
  n int := 24; m int;
begin
  select c.club_id into club from public.mgr_coach c where c.career_id = v_car;
  select f.id, case when f.home_club = club then 'h' else 'a' end into fx, v_side
    from public.season_fixtures f join public.career_seasons s on s.id = f.season_id
   where s.career_id = v_car and f.status = 'pending' and (f.home_club = club or f.away_club = club) order by f.round_no limit 1;
  select jsonb_build_object('formation', l.formation, 'slots', l.slots, 'bench', to_jsonb(l.bench)) into lu
    from public.mgr_lineups l where l.career_id = v_car and l.club_id = club;
  for m in 1 .. 2 * n loop
    delete from public.mgr_match_events where fixture_id = fx;
    delete from public.mgr_match_players where fixture_id = fx;
    delete from public.mgr_matches where fixture_id = fx;
    perform public.mgr_match_create(fx, v_car, v_side, lu || jsonb_build_object('tactics',
      case when m <= n then '{"mentality": 2, "pressing": "high", "tempo": "fast", "line": "high"}'::jsonb
           else '{"mentality": -2, "pressing": "low", "tempo": "slow", "line": "deep"}'::jsonb end));
    perform public.mgr_engine_run(fx, 90, null);
    if m <= n then
      sh_att := sh_att + (select coalesce(sum(shots), 0) from public.mgr_match_players where fixture_id = fx and side = v_side);
      ga_att := ga_att + (select (state -> 'score' ->> (case when v_side = 'h' then 1 else 0 end))::int from public.mgr_matches where fixture_id = fx);
    else
      sh_def := sh_def + (select coalesce(sum(shots), 0) from public.mgr_match_players where fixture_id = fx and side = v_side);
      ga_def := ga_def + (select (state -> 'score' ->> (case when v_side = 'h' then 1 else 0 end))::int from public.mgr_matches where fixture_id = fx);
    end if;
  end loop;
  delete from public.mgr_match_events where fixture_id = fx;
  delete from public.mgr_match_players where fixture_id = fx;
  delete from public.mgr_matches where fixture_id = fx;
  raise notice 'T3: finalizações/jogo ofensivo % × retranca %; gols sofridos/jogo % × %',
    round(sh_att / n, 1), round(sh_def / n, 1), round(ga_att / n, 2), round(ga_def / n, 2);
  assert sh_att > sh_def * 1.1, 'T3: postura ofensiva deveria finalizar mais';
  raise notice 'T3 ok: táticas afetam o motor';
end $$;

-- ---------------------------------------------------------------------
-- T4. Rodadas simuladas: classificação com os critérios oficiais e mata-mata coerente
-- ---------------------------------------------------------------------
set local role authenticated;
set local request.jwt.claim.sub = '7e57c0de-0000-0000-0000-000000000001';
do $$
declare h jsonb; i int;
begin
  -- joga ~12 eventos do calendário (jogos do usuário no automático + dias livres)
  for i in 1 .. 30 loop
    h := public.mgr_hub();
    exit when h -> 'season' ->> 'status' <> 'active';
    if h ->> 'live_match' is not null then
      perform public.mgr_match_step((h ->> 'live_match')::bigint, 0, 120, null, true, 0);
    elsif h -> 'next_event' ->> 'kind' = 'mine' then
      if (h -> 'lineup' ->> 'errors')::int > 0 then perform public.mgr_lineup_auto(null); end if;
      perform public.mgr_match_start();
    else
      perform public.mgr_advance(false);
    end if;
  end loop;
  -- não deixa partida pela metade para os próximos testes
  h := public.mgr_hub();
  if h ->> 'live_match' is not null then
    perform public.mgr_match_step((h ->> 'live_match')::bigint, 0, 120, null, true, 0);
  end if;
end $$;
reset role;

do $$
declare
  v_s uuid; r record; prev record; n int := 0; bad int; first boolean := true;
begin
  select id into v_s from public.career_seasons where career_id = '7e57c0de-0000-0000-0000-0000000000ca' and mode = 'coach' order by season_no desc limit 1;
  -- ordem: pontos desc; empatados em pontos -> vitórias desc; empatados em pontos e vitórias -> saldo desc (antes de gols/confronto)
  for r in select * from public.sim_standings(v_s, 'brasileirao', null) order by pos loop
    if not first then
      assert prev.points >= r.points, 'T4: tabela fora da ordem de pontos';
      if prev.points = r.points then assert prev.wins >= r.wins, 'T4: desempate por vitórias violado'; end if;
      if prev.points = r.points and prev.wins = r.wins then assert prev.gd >= r.gd, 'T4: desempate por saldo violado'; end if;
    end if;
    prev := r; first := false; n := n + 1;
  end loop;
  assert n = 20, 'T4: Brasileirão deveria ter 20 clubes';
  -- soma de pontos = 3*vitórias + empates de todos os jogos disputados
  assert (select sum(points) from public.sim_standings(v_s, 'brasileirao', null)) =
         (select coalesce(sum(case when home_goals = away_goals then 2 else 3 end), 0) from public.season_fixtures
           where season_id = v_s and competition_id = 'brasileirao' and status = 'played'), 'T4: pontos não batem com os resultados';
  -- mata-mata: vencedor do confronto = agregado (ou pênaltis quando empatado)
  select count(*) into bad from (
    select f2.tie_winner,
           (case when f1.home_club = f2.home_club then f1.home_goals else f1.away_goals end) + f2.home_goals as agg_home2,
           (case when f1.home_club = f2.away_club then f1.home_goals else f1.away_goals end) + f2.away_goals as agg_away2,
           f2.home_club, f2.away_club, f2.home_pens, f2.away_pens
      from public.season_fixtures f1 join public.season_fixtures f2
        on f2.season_id = f1.season_id and f2.competition_id = f1.competition_id and f2.stage = f1.stage and f2.tie_no = f1.tie_no and f2.leg = 2
     where f1.season_id = v_s and f1.leg = 1 and f1.status = 'played' and f2.status = 'played') t
   where t.tie_winner is distinct from case when agg_home2 > agg_away2 then home_club when agg_away2 > agg_home2 then away_club
                                             when home_pens > away_pens then home_club else away_club end;
  assert bad = 0, format('T4: %s confronto(s) com vencedor errado', bad);
  -- nenhum time joga duas vezes na mesma rodada
  select count(*) into bad from (
    select competition_id, stage, round_no, c from (
      select competition_id, stage, round_no, home_club c from public.season_fixtures where season_id = v_s
      union all select competition_id, stage, round_no, away_club from public.season_fixtures where season_id = v_s) x
    group by 1, 2, 3, 4 having count(*) > 1) y;
  assert bad = 0, 'T4: clube escalado duas vezes na mesma rodada';
  raise notice 'T4 ok: classificação e mata-mata';
end $$;

-- ---------------------------------------------------------------------
-- T5. Demissão no meio da temporada, espera por propostas e troca de clube SEM reiniciar a temporada
-- ---------------------------------------------------------------------
do $$
declare
  v_car uuid := '7e57c0de-0000-0000-0000-0000000000ca'; v_s0 uuid; v_day0 int; v_played0 int; v_old text;
begin
  select id, day_no into v_s0, v_day0 from public.career_seasons where career_id = v_car and status = 'active';
  if v_s0 is null then raise notice 'T5 pulado (temporada já encerrada)'; return; end if;
  select club_id into v_old from public.mgr_coach where career_id = v_car;
  select count(*) into v_played0 from public.season_fixtures where season_id = v_s0 and status = 'played';
  perform public.mgr_fire(v_car, 'desempenho muito ruim e pressão da torcida');
  assert (select status from public.mgr_coach where career_id = v_car) = 'unemployed', 'T5: não ficou desempregado';
  assert (select end_reason from public.mgr_spells where career_id = v_car and club_id = v_old order by created_at desc limit 1) = 'fired', 'T5: passagem não marcada como demissão';
end $$;

set local role authenticated;
set local request.jwt.claim.sub = '7e57c0de-0000-0000-0000-000000000001';
do $$
declare h jsonb; r jsonb; v_s0 uuid; i int; v_new text; v_played0 int;
begin
  h := public.mgr_hub();
  if h -> 'coach' ->> 'status' <> 'unemployed' then return; end if;
  v_s0 := (h -> 'season' ->> 'id')::uuid;
  select count(*) into v_played0 from public.season_fixtures where season_id = v_s0 and status = 'played';
  begin
    perform public.mgr_match_start();
    assert false, 'T5: desempregado não pode jogar';
  exception when others then
    if sqlerrm like 'T5:%' then raise; end if;
  end;
  for i in 1 .. 12 loop
    h := public.mgr_hub();
    exit when jsonb_array_length(h -> 'offers') > 0 or h -> 'season' ->> 'status' <> 'active';
    perform public.mgr_advance(true);   -- um dia por vez até chegar proposta
  end loop;
  h := public.mgr_hub();
  if h -> 'season' ->> 'status' <> 'active' then raise notice 'T5: temporada acabou antes da proposta'; return; end if;
  assert jsonb_array_length(h -> 'offers') > 0, 'T5: nenhuma proposta em 12 dias (deveria vir até o 6º)';
  assert (select count(*) from public.season_fixtures where season_id = v_s0 and status = 'played') > v_played0, 'T5: o campeonato não andou com o passar dos dias';
  r := public.mgr_offer_respond((h -> 'offers' -> 0 ->> 'id')::uuid, true);
  v_new := r ->> 'club_id';
  h := public.mgr_hub();
  assert h -> 'coach' ->> 'status' = 'employed' and h -> 'coach' ->> 'club_id' = v_new, 'T5: não assumiu o novo clube';
  assert (h -> 'season' ->> 'id')::uuid = v_s0, 'T5: a temporada foi reiniciada (não deveria)';
  assert (select count(*) from public.season_fixtures where season_id = v_s0 and status = 'played') >= v_played0, 'T5: resultados perdidos';
  assert jsonb_array_length((public.mgr_history()) -> 'spells') >= 2, 'T5: histórico de clubes não registrou as duas passagens';
  raise notice 'T5 ok: demissão, propostas com o passar dos dias e troca de clube no meio da temporada';
end $$;
reset role;

-- ---------------------------------------------------------------------
-- T6. Segurança: funções internas do motor não podem ser chamadas pelo app
-- ---------------------------------------------------------------------
do $$
begin
  assert not has_function_privilege('authenticated', 'public.mgr_engine_run(bigint, int, char)', 'execute'), 'T6: motor exposto ao app';
  assert not has_function_privilege('authenticated', 'public.mgr_fire(uuid, text)', 'execute'), 'T6: demissão exposta ao app';
  assert not has_function_privilege('anon', 'public.mgr_hub()', 'execute'), 'T6: anon não deveria chamar o hub';
  assert has_function_privilege('authenticated', 'public.mgr_match_step(bigint, int, int, jsonb, boolean, int)', 'execute'), 'T6: app sem acesso à partida';
  raise notice 'T6 ok: permissões';
end $$;

rollback;
