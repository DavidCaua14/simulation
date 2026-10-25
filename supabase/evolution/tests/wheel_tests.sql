-- =====================================================================
-- TESTES da Etapa 6 — roleta (banco de DESENVOLVIMENTO, depois de evolution/08)
--   psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f supabase/evolution/tests/wheel_tests.sql
-- Tudo roda dentro de uma transação que termina em ROLLBACK.
-- =====================================================================
begin;
set local client_min_messages = notice;

insert into auth.users (id) values ('7ee17ee1-0000-0000-0000-000000000001') on conflict do nothing;
insert into public.careers (id, user_id, nickname, photo_id, country, age, club_id, diamonds) values
  ('7ee17ee1-0000-0000-0000-0000000000c1', '7ee17ee1-0000-0000-0000-000000000001', 'teste_roleta', 'p1', 'BR', 30, 'sport', 25);

-- ---------------------------------------------------------------------
-- W1. Configuração: soma 100%, chances diferentes, Épica mais rara que qualquer fatia de Lenda, toda fatia tem cartas
-- ---------------------------------------------------------------------
do $$
declare g public.wheel_segments; n int;
begin
  assert (select sum(probability) from public.wheel_segments where active) = 100, 'W1: probabilidades não somam 100%';
  assert (select count(distinct probability) from public.wheel_segments where active) > 1, 'W1: probabilidades iguais';
  assert (select bool_and(tier in ('lenda', 'epica')) from public.wheel_segments where active), 'W1: prêmio fora de Lenda/Épica';
  assert (select max(probability) from public.wheel_segments where active and tier = 'epica')
       < (select min(probability) from public.wheel_segments where active and tier = 'lenda'), 'W1: Épica deveria ser a mais rara';
  for g in select * from public.wheel_segments where active loop
    select count(*) into n from public.wheel_segment_cards(g);
    assert n > 0, format('W1: fatia %s sem cartas', g.id);
  end loop;
  assert exists (select 1 from public.wheel_config c join public.wheel_segments s on s.id = c.pity_segment and s.active and s.tier = 'epica'),
    'W1: garantia aponta para fatia inválida';
  assert (select cost_diamonds from public.wheel_config) = 10, 'W1: giro deveria custar 10 diamantes';
  raise notice 'W1 ok: configuração (soma 100%%, Épica mais rara, todas as fatias com cartas)';
end $$;

-- W2. O banco recusa probabilidades que não somam 100%
do $$
declare ok boolean; msg text;
begin
  begin
    update public.wheel_segments set probability = probability + 1 where id = 'epica';
    set constraints public.wheel_segments_sum immediate;
    ok := true;
  exception when others then ok := false; msg := sqlerrm;
  end;
  assert not ok and msg like '%precisam somar 100%', 'W2: aceitou soma diferente de 100%: ' || coalesce(msg, '');
  set constraints public.wheel_segments_sum deferred;
  raise notice 'W2 ok: soma diferente de 100%% é recusada (%)', msg;
end $$;

-- ---------------------------------------------------------------------
-- W3–W5. Giros pelo app
-- ---------------------------------------------------------------------
set local role authenticated;
set local request.jwt.claim.sub = '7ee17ee1-0000-0000-0000-000000000001';
do $$
declare cat jsonb; r1 jsonb; r2 jsonb; d0 int; v_req uuid := gen_random_uuid(); ok boolean; msg text; n_sp int; n_cards int;
begin
  cat := public.wheel_catalog();
  assert (cat ->> 'probability_sum')::numeric = 100 and (cat -> 'pity' ->> 'remaining')::int = 40, 'W3: catálogo antes do giro';
  d0 := (select diamonds from public.careers where user_id = auth.uid() and status = 'active');

  r1 := public.wheel_spin(v_req);
  assert (r1 ->> 'ok')::boolean and (r1 ->> 'diamonds')::int = d0 - 10, 'W3: custo do giro';
  assert (select diamonds from public.careers where user_id = auth.uid() and status = 'active') = d0 - 10, 'W3: saldo';
  assert r1 -> 'card' ->> 'tier' in ('lenda', 'epica'), 'W3: prêmio fora de Lenda/Épica';
  assert exists (select 1 from public.user_cards uc join public.careers c on c.id = uc.career_id
                  where c.user_id = auth.uid() and uc.card_id = r1 -> 'card' ->> 'id'), 'W3: carta não entrou no inventário';
  assert exists (select 1 from public.wheel_spins where id = (r1 ->> 'spin_id')::uuid and card_id = r1 -> 'card' ->> 'id'), 'W3: giro não registrado';
  assert exists (select 1 from public.wallet_ledger where reason = 'wheel_spin' and ref = r1 ->> 'spin_id' and delta = -10), 'W3: giro fora do livro';
  assert jsonb_array_length(public.wheel_catalog() -> 'history') = 1, 'W3: histórico';

  -- W4: mesmo pedido = mesmo giro (sem cobrar nem entregar outra carta)
  r2 := public.wheel_spin(v_req);
  assert (r2 ->> 'replayed')::boolean and r2 ->> 'spin_id' = r1 ->> 'spin_id' and r2 -> 'card' = r1 -> 'card', 'W4: replay diferente';
  assert (select diamonds from public.careers where user_id = auth.uid() and status = 'active') = d0 - 10, 'W4: cobrou duas vezes';
  assert (select count(*) from public.wheel_spins ws join public.careers c on c.id = ws.career_id where c.user_id = auth.uid()) = 1, 'W4: dois giros';
  raise notice 'W3/W4 ok: giro cobrado uma vez, carta entregue, registrado; repetição idempotente (saiu %)', r1 ->> 'segment_label';

  -- W5: diamantes insuficientes (sobram 5) — nada muda
  perform public.wheel_spin(gen_random_uuid());   -- 15 → 5
  select count(*) into n_sp from public.wheel_spins ws join public.careers c on c.id = ws.career_id where c.user_id = auth.uid();
  select coalesce(sum(qty), 0) into n_cards from public.user_cards uc join public.careers c on c.id = uc.career_id where c.user_id = auth.uid();
  begin perform public.wheel_spin(gen_random_uuid()); ok := true; exception when others then ok := false; msg := sqlerrm; end;
  assert not ok and msg = 'Diamantes insuficientes.', 'W5: deveria recusar: ' || coalesce(msg, '');
  assert (select diamonds from public.careers where user_id = auth.uid() and status = 'active') = 5, 'W5: saldo mudou';
  assert (select count(*) from public.wheel_spins ws join public.careers c on c.id = ws.career_id where c.user_id = auth.uid()) = n_sp, 'W5: giro sem pagamento';
  assert (select coalesce(sum(qty), 0) from public.user_cards uc join public.careers c on c.id = uc.career_id where c.user_id = auth.uid()) = n_cards,
    'W5: carta sem pagamento';
  raise notice 'W5 ok: sem diamantes suficientes nada acontece';
end $$;

-- W6. Garantia: depois de 39 giros sem Épica, o 40º é Épica; o contador zera
reset role;
update public.careers set diamonds = 100 where id = '7ee17ee1-0000-0000-0000-0000000000c1';
update public.wheel_state set spins_since_epic = 39 where career_id = '7ee17ee1-0000-0000-0000-0000000000c1';
set local role authenticated;
do $$
declare r jsonb;
begin
  assert (public.wheel_catalog() -> 'pity' ->> 'remaining')::int = 1, 'W6: a tela deveria mostrar 1 giro para a garantia';
  r := public.wheel_spin(gen_random_uuid());
  assert r ->> 'tier' = 'epica' and (r ->> 'pity')::boolean, 'W6: garantia não entregou Épica';
  assert (r ->> 'pity_since')::int = 0 and (r ->> 'pity_remaining')::int = 40, 'W6: contador da garantia não zerou';
  raise notice 'W6 ok: garantia entrega Épica no 40º giro sem Épica e zera o contador';
end $$;

-- W7. Distribuição real em 2.000 giros (garantia desligada só para medir as chances puras)
reset role;
update public.wheel_config set pity_enabled = false;
update public.careers set diamonds = 20000 where id = '7ee17ee1-0000-0000-0000-0000000000c1';
set local role authenticated;
do $$
declare i int; t0 timestamptz := clock_timestamp(); s record; n int; lo numeric; hi numeric; sd numeric; v_before uuid[];
begin
  select array_agg(ws.id) into v_before from public.wheel_spins ws join public.careers c on c.id = ws.career_id where c.user_id = auth.uid();
  for i in 1..2000 loop perform public.wheel_spin(gen_random_uuid()); end loop;
  for s in select * from public.wheel_segments where active order by sort_order loop
    select count(*) into n from public.wheel_spins ws join public.careers c on c.id = ws.career_id
     where c.user_id = auth.uid() and ws.segment_id = s.id and not ws.pity and not (ws.id = any (v_before));
    sd := sqrt(2000 * s.probability / 100 * (1 - s.probability / 100));
    lo := 2000 * s.probability / 100 - 4.5 * sd; hi := 2000 * s.probability / 100 + 4.5 * sd;   -- 4,5 desvios: falso alarme ~1 em 100 mil
    assert n between lo and hi, format('W7: %s saiu %s vezes (esperado %s ± %s)', s.id, n, 2000 * s.probability / 100, round(4.5 * sd));
    raise notice '   % — % de 2000 (% %%) · esperado % %%', rpad(s.label, 15), n, round(n / 20.0, 2), s.probability;
  end loop;
  raise notice 'W7 ok: 2000 giros em % s, distribuição dentro do esperado', round(extract(epoch from clock_timestamp() - t0), 1);
end $$;

-- W8. Permissões: o app não grava giros, estado, fatias nem chama funções internas
do $$
declare ok boolean;
begin
  begin update public.wheel_segments set probability = 50 where id = 'epica'; ok := true; exception when insufficient_privilege then ok := false; end;
  assert not ok, 'W8: app alterou as chances';
  begin update public.wheel_state set spins_since_epic = 39; ok := true; exception when insufficient_privilege then ok := false; end;
  assert not ok, 'W8: app alterou a garantia';
  begin insert into public.wheel_spins (career_id, request_id, segment_id, card_id, cost)
        select id, gen_random_uuid(), 'epica', (select id from public.cards where tier = 'epica' limit 1), 0 from public.careers where user_id = auth.uid();
        ok := true; exception when insufficient_privilege then ok := false; end;
  assert not ok, 'W8: app gravou giro';
  begin perform public.wheel_segment_cards((select s from public.wheel_segments s limit 1)); ok := true; exception when insufficient_privilege then ok := false; end;
  assert not ok, 'W8: app chamou função interna';
  raise notice 'W8 ok: permissões';
end $$;

reset role;
do $$ begin raise notice ' TODOS OS TESTES DA ETAPA 6 PASSARAM'; end $$;
rollback;
