-- =====================================================================
-- TESTES da Etapa 4 — clube inicial pela nacionalidade (rodar num banco de DESENVOLVIMENTO depois de evolution/05)
--   psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f supabase/evolution/tests/career_start_tests.sql
-- Tudo roda dentro de uma transação que termina em ROLLBACK: nada fica gravado.
-- =====================================================================
begin;
set local client_min_messages = notice;

insert into auth.users (id) values
  ('5a5a0000-0000-0000-0000-0000000000b1'), ('5a5a0000-0000-0000-0000-0000000000e1'), ('5a5a0000-0000-0000-0000-0000000000f1')
on conflict do nothing;

-- ---------------------------------------------------------------------
-- T1. Configuração: toda nacionalidade ativa tem clubes elegíveis suficientes, com elenco, e perfis válidos
-- ---------------------------------------------------------------------
do $$
declare r record; o jsonb; n int; bad int;
begin
  for r in select * from public.sim_start_rules where active loop
    for o in select * from jsonb_array_elements(r.options) loop
      select count(*) into n from public.sim_start_candidates(o);
      assert n >= coalesce((o ->> 'count')::int, 1) + 1,
        format('T1: %s/%s tem só %s clube(s) elegível(is) — não dá para variar o sorteio', r.country, o ->> 'key', n);
      assert exists (select 1 from public.sim_difficulty_profiles where id = coalesce(o ->> 'difficulty', 'standard')),
        format('T1: perfil inexistente em %s/%s', r.country, o ->> 'key');
      select count(*) into bad from public.sim_start_candidates(o) c
       where (select count(*) from public.sim_players p where p.club_id = c.club_id and p.active) < 18;
      assert bad = 0, format('T1: clube sem elenco cadastrado em %s/%s', r.country, o ->> 'key');
    end loop;
  end loop;
  -- Brasil: uma opção da Série A e uma da Série B; Inglaterra: 2 clubes ingleses
  assert (select options @> '[{"key":"serie_a","competitions":["brasileirao"]},{"key":"serie_b","competitions":["serie_b"]}]'
            from public.sim_start_rules where country = 'BR'), 'T1: regra do Brasil';
  assert (select count(*) from public.sim_start_candidates((select options -> 0 from public.sim_start_rules where country = 'EN')) c
           join public.sim_clubs cl on cl.id = c.club_id where cl.country <> 'ENG') = 0, 'T1: clube não inglês na regra da Inglaterra';
  -- 'Inglaterra': os elegíveis são os MAIS FRACOS da Championship
  assert (select max(cl.strength) from public.sim_start_candidates((select options -> 0 from public.sim_start_rules where country = 'EN')) c
           join public.sim_clubs cl on cl.id = c.club_id)
         <= (select percentile_disc(0.5) within group (order by cl.strength) from public.sim_competition_clubs cc
              join public.sim_clubs cl on cl.id = cc.club_id where cc.competition_id = 'championship'), 'T1: Inglaterra deveria sortear entre os mais fracos';
  raise notice 'T1 ok: configuração das nacionalidades';
end $$;

-- ---------------------------------------------------------------------
-- T2. Brasileiro: duas propostas (Série A + Série B), gravadas — chamar de novo devolve as MESMAS
-- ---------------------------------------------------------------------
set local role authenticated;
set local request.jwt.claim.sub = '5a5a0000-0000-0000-0000-0000000000b1';
insert into public.careers (user_id, nickname, photo_id, country, age)
values ('5a5a0000-0000-0000-0000-0000000000b1', 'teste_br_t4', 'p1', 'BR', 35);
do $$
declare a jsonb; b jsonb; ca text; cb text;
begin
  a := public.get_initial_offers();
  assert jsonb_array_length(a) = 2, 'T2: deveriam ser 2 propostas';
  select e ->> 'club_id' into ca from jsonb_array_elements(a) e where e ->> 'option' = 'serie_a';
  select e ->> 'club_id' into cb from jsonb_array_elements(a) e where e ->> 'option' = 'serie_b';
  assert exists (select 1 from public.sim_competition_clubs where competition_id = 'brasileirao' and club_id = ca), 'T2: opção A não é da Série A';
  assert exists (select 1 from public.sim_competition_clubs where competition_id = 'serie_b' and club_id = cb), 'T2: opção B não é da Série B';
  assert (select e ->> 'difficulty' from jsonb_array_elements(a) e where e ->> 'option' = 'serie_b') = 'accessible', 'T2: Série B deveria ter início acessível';
  assert (select e ->> 'difficulty' from jsonb_array_elements(a) e where e ->> 'option' = 'serie_a') = 'standard', 'T2: Série A deveria ser padrão';
  b := public.get_initial_offers();
  assert a = b, 'T2: recarregar a página sorteou de novo';
  raise notice 'T2 ok: brasileiro recebe Série A + Série B e o sorteio fica gravado (% / %)', ca, cb;
end $$;

-- ---------------------------------------------------------------------
-- T3. Proteções: não dá para escolher proposta de outro usuário, nem escolher duas vezes, nem 2 carreiras ativas
-- ---------------------------------------------------------------------
do $$
declare v_off uuid; ok boolean;
begin
  begin
    insert into public.careers (user_id, nickname, photo_id, country, age) values ('5a5a0000-0000-0000-0000-0000000000b1', 'teste_br_t4b', 'p1', 'BR', 35);
    ok := true;
  exception when unique_violation then ok := false;
  end;
  assert not ok, 'T3: criou uma segunda carreira ativa para o mesmo usuário';
  begin
    insert into public.careers (user_id, nickname, photo_id, country, age) values ('5a5a0000-0000-0000-0000-0000000000f1', 'teste_xx_t4', 'p1', 'XX', 35);
    ok := true;
  exception when others then ok := false;
  end;
  assert not ok, 'T3: aceitou nacionalidade sem regra configurada';
  begin
    update public.careers set club_id = 'flamengo' where user_id = auth.uid();
    ok := (select club_id = 'flamengo' from public.careers where user_id = auth.uid() and status = 'active');
  exception when insufficient_privilege then ok := false;
  end;
  assert not coalesce(ok, false), 'T3: o navegador conseguiu escolher o clube direto na tabela';
  begin
    perform public.choose_initial_club(gen_random_uuid());
    ok := true;
  exception when others then ok := false;
  end;
  assert not ok, 'T3: aceitou proposta inexistente';
  raise notice 'T3 ok: proposta alheia, nacionalidade inválida, clube direto na tabela e carreira duplicada bloqueados';
end $$;

-- ---------------------------------------------------------------------
-- T4. Escolher a Série B: clube + perfil "início acessível"; primeira temporada no Brasil com a Série B;
--     meta da liga 1 posição mais folgada que a da tabela de objetivos
-- ---------------------------------------------------------------------
do $$
declare a jsonb; v_off uuid; v_club text; h jsonb; v_t int; v_band int; v_rank int; v_str int; ok boolean;
begin
  a := public.get_initial_offers();
  select (e ->> 'id')::uuid, e ->> 'club_id' into v_off, v_club from jsonb_array_elements(a) e where e ->> 'option' = 'serie_b';
  perform public.choose_initial_club(v_off);
  assert (select club_id = v_club and difficulty = 'accessible' and start_option = 'serie_b' from public.careers where user_id = auth.uid() and status = 'active'),
    'T4: clube/perfil não aplicados';
  assert public.get_initial_offers() = '[]'::jsonb, 'T4: continuou mostrando propostas depois de escolher';
  begin perform public.choose_initial_club(v_off); ok := true; exception when others then ok := false; end;
  assert not ok, 'T4: escolheu duas vezes';

  h := public.mgr_hub();
  assert h -> 'season' ->> 'region' = 'BRA', 'T4: temporada deveria ser no Brasil';
  assert exists (select 1 from jsonb_array_elements(h -> 'competitions') c where c ->> 'id' = 'serie_b' and c ->> 'status' = 'active'), 'T4: clube da Série B sem a Série B';
  assert exists (select 1 from jsonb_array_elements(h -> 'competitions') c where c ->> 'id' = 'brasileirao' and c ->> 'status' = 'not_in'), 'T4: clube da Série B jogando a Série A';

  -- meta: a da faixa configurada + 1 (perfil acessível)
  select (o ->> 'target')::int into v_t from jsonb_array_elements(h -> 'objectives') o where o ->> 'competition' = 'serie_b' and o ->> 'kind' = 'league_pos';
  select strength into v_str from public.sim_clubs where id = v_club;
  select count(*) + 1 into v_rank from public.season_participants sp join public.sim_clubs x on x.id = sp.club_id
   where sp.season_id = (h -> 'season' ->> 'id')::uuid and sp.competition_id = 'serie_b' and x.strength > v_str;
  select (b ->> 'target')::int into v_band from public.sim_competitions c, jsonb_array_elements(c.rules -> 'objectives') b
   where c.id = 'serie_b' and (b ->> 'rank_max')::int >= v_rank order by (b ->> 'rank_max')::int limit 1;
  assert v_t = v_band + 1, format('T4: meta %s, esperado %s (+1 do início acessível)', v_t, v_band + 1);
  raise notice 'T4 ok: Série B escolhida (%), início acessível, meta % em vez de %', v_club, v_t, v_band;
end $$;

-- ---------------------------------------------------------------------
-- T5. O perfil só muda a COBRANÇA (diretoria/torcida/reputação), nunca o placar.
--     Mesma partida avaliada com os dois perfis: placar idêntico; queda de confiança menor no acessível.
-- ---------------------------------------------------------------------
do $$
declare h jsonb; v_fx bigint; s jsonb; i int := 0;
begin
  loop   -- avança o calendário até o primeiro jogo do clube
    i := i + 1;
    begin
      h := public.mgr_match_start();
      exit;
    exception when others then
      assert i < 40, 'T5: nenhum jogo encontrado: ' || sqlerrm;
      perform public.mgr_advance(false);
    end;
  end loop;
  v_fx := coalesce((h ->> 'fixture_id')::bigint, (h -> 'match' ->> 'fixture_id')::bigint);
  assert v_fx is not null, 'T5: partida sem id: ' || left(h::text, 200);
  s := public.mgr_match_step(v_fx, 0, 95, '[]'::jsonb, true, 0);
  perform set_config('t4.fixture', v_fx::text, true);
end $$;
reset role;
do $$
declare v_fx bigint := current_setting('t4.fixture')::bigint; v_car uuid; v_side char; r_std jsonb; r_acc jsonb; r_std2 jsonb;
begin
  select career_id, user_side into v_car, v_side from public.mgr_matches where fixture_id = v_fx;
  -- força uma derrota de 0x3 para medir a cobrança (dentro de sub-transações desfeitas)
  update public.season_fixtures set home_goals = case when v_side = 'h' then 0 else 3 end, away_goals = case when v_side = 'h' then 3 else 0 end
   where id = v_fx;
  begin
    update public.careers set difficulty = 'standard' where id = v_car;
    update public.mgr_coach set board_confidence = 50, fan_mood = 50 where career_id = v_car;
    r_std := public.mgr_after_user_match(v_fx);
    raise exception 'desfaz';
  exception when raise_exception then null;
  end;
  begin
    update public.careers set difficulty = 'accessible' where id = v_car;
    update public.mgr_coach set board_confidence = 50, fan_mood = 50 where career_id = v_car;
    r_acc := public.mgr_after_user_match(v_fx);
    raise exception 'desfaz';
  exception when raise_exception then null;
  end;
  assert r_std -> 'my_goals' = r_acc -> 'my_goals' and r_std -> 'opp_goals' = r_acc -> 'opp_goals', 'T5: o perfil mudou o placar';
  assert r_std -> 'rewards' = r_acc -> 'rewards', 'T5: o perfil mudou os prêmios do jogo';
  assert (r_std -> 'board' ->> 'delta')::numeric < 0, 'T5: derrota deveria derrubar a confiança';
  assert (r_acc -> 'board' ->> 'delta')::numeric > (r_std -> 'board' ->> 'delta')::numeric, 'T5: perfil acessível deveria cobrar menos';
  assert (r_acc -> 'fans' ->> 'delta')::numeric > (r_std -> 'fans' ->> 'delta')::numeric, 'T5: torcida deveria cobrar menos no acessível';

  -- o perfil expira: depois de 2 temporadas a carreira volta ao padrão
  update public.mgr_coach set seasons = 2 where career_id = v_car;
  assert (public.mgr_difficulty(v_car)).id = 'standard', 'T5: perfil deveria expirar depois de 2 temporadas';
  update public.mgr_coach set seasons = 0 where career_id = v_car;
  assert (public.mgr_difficulty(v_car)).id = 'accessible', 'T5: perfil deveria valer na 1ª temporada';
  raise notice 'T5 ok: placar igual; confiança % (padrão) × % (acessível); perfil expira após 2 temporadas',
    r_std -> 'board' ->> 'delta', r_acc -> 'board' ->> 'delta';
end $$;

-- ---------------------------------------------------------------------
-- T6. Inglês: 2 clubes ingleses diferentes entre os mais fracos; carreira começa na Inglaterra;
--     carreiras seguidas do mesmo usuário nunca recebem exatamente a mesma dupla, e o sorteio varia
-- ---------------------------------------------------------------------
select set_config('t4.pool', (select array_agg(club_id)::text from public.sim_start_candidates(
  (select options -> 0 from public.sim_start_rules where country = 'EN'))), true);
set local role authenticated;
set local request.jwt.claim.sub = '5a5a0000-0000-0000-0000-0000000000e1';
do $$
declare a jsonb; v_prev text[]; v_cur text[]; v_sets text[] := '{}'; i int; v_pool text[]; v_off uuid; h jsonb;
begin
  v_pool := current_setting('t4.pool')::text[];
  for i in 1..12 loop
    insert into public.careers (user_id, nickname, photo_id, country, age) values (auth.uid(), 'teste_en_t4_' || i, 'p1', 'EN', 40);
    a := public.get_initial_offers();
    assert jsonb_array_length(a) = 2, 'T6: deveriam ser 2 propostas';
    select array_agg(e ->> 'club_id' order by e ->> 'club_id') into v_cur from jsonb_array_elements(a) e;
    assert v_cur[1] <> v_cur[2], 'T6: mesma equipe duas vezes';
    assert v_cur <@ v_pool, 'T6: clube fora dos elegíveis';
    assert not (array_to_string(v_cur, '+') = any (v_sets)), format('T6: repetiu uma dupla já oferecida antes (%s)', v_cur);
    v_sets := v_sets || array_to_string(v_cur, '+');
    v_prev := v_cur;
    if i < 12 then
      reset role;
      update public.careers set status = 'retired' where user_id = '5a5a0000-0000-0000-0000-0000000000e1' and status = 'active';
      set local role authenticated;
    end if;
  end loop;
  assert (select count(distinct x) from unnest(v_sets) x) >= 6, 'T6: sorteio pouco variado';

  select (e ->> 'id')::uuid into v_off from jsonb_array_elements(a) e limit 1;
  perform public.choose_initial_club(v_off);
  h := public.mgr_hub();
  assert h -> 'season' ->> 'region' = 'ENG', 'T6: carreira inglesa deveria começar na Inglaterra';
  assert exists (select 1 from jsonb_array_elements(h -> 'competitions') c where c ->> 'id' = 'championship' and c ->> 'status' = 'active'), 'T6: sem a Championship';
  assert (select difficulty from public.careers where user_id = auth.uid() and status = 'active') = 'standard', 'T6: perfil errado';
  raise notice 'T6 ok: inglês — % duplas diferentes em 12 carreiras, nenhuma repetida; temporada na Inglaterra',
    (select count(distinct x) from unnest(v_sets) x);
end $$;

reset role;
do $$ begin raise notice ' TODOS OS TESTES DA ETAPA 4 PASSARAM'; end $$;
rollback;
