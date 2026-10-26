-- =====================================================================
-- TESTES da Etapa 5 — livro de transações, idempotência e loja de cartas (banco de DESENVOLVIMENTO, depois de evolution/06)
--   psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f supabase/evolution/tests/economy_shop_tests.sql
-- Tudo roda dentro de uma transação que termina em ROLLBACK.
-- =====================================================================
begin;
set local client_min_messages = notice;

insert into auth.users (id) values ('ec0ec0ec-0000-0000-0000-000000000001'), ('ec0ec0ec-0000-0000-0000-000000000002') on conflict do nothing;
insert into public.careers (id, user_id, nickname, photo_id, country, age, club_id) values
  ('ec0ec0ec-0000-0000-0000-0000000000c1', 'ec0ec0ec-0000-0000-0000-000000000001', 'teste_econ_1', 'p1', 'BR', 30, 'fortaleza'),
  ('ec0ec0ec-0000-0000-0000-0000000000c2', 'ec0ec0ec-0000-0000-0000-000000000002', 'teste_econ_2', 'p1', 'BR', 30, 'sport');

-- ---------------------------------------------------------------------
-- E1. Livro: saldo de abertura, débito/crédito com motivo, saldo insuficiente não muda nada
-- ---------------------------------------------------------------------
do $$
declare v_car uuid := 'ec0ec0ec-0000-0000-0000-0000000000c1'; b int; ok boolean; st text;
begin
  assert (select count(*) from public.wallet_ledger where career_id = v_car and reason = 'opening_balance' and currency = 'coins' and delta = 1000) = 1,
    'E1: saldo de abertura não registrado';
  b := public.econ_apply(v_car, 'coins', 250, 'test_credit', 'r1');
  assert b = 1250, 'E1: crédito errado';
  b := public.econ_apply(v_car, 'coins', -50, 'test_debit', 'r2');
  assert b = 1200 and (select coins from public.careers where id = v_car) = 1200, 'E1: débito errado';
  assert (select array_agg(delta order by id) from public.wallet_ledger where career_id = v_car and currency = 'coins' and reason like 'test_%') = '{250,-50}',
    'E1: livro não registrou as duas operações';
  assert (select balance_after from public.wallet_ledger where career_id = v_car and ref = 'r2') = 1200, 'E1: saldo após errado';
  begin
    perform public.econ_apply(v_car, 'diamonds', -1, 'test_debit', 'r3');
    ok := true;
  exception when sqlstate 'P0402' then ok := false; st := sqlerrm;
  end;
  assert not ok and st = 'Diamantes insuficientes.', 'E1: deveria recusar saldo insuficiente';
  assert (select diamonds from public.careers where id = v_car) = 0 and not exists (select 1 from public.wallet_ledger where ref = 'r3'),
    'E1: saldo insuficiente alterou algo';
  -- alteração feita por função antiga (sem motivo) também entra no livro
  update public.careers set bonus_energy = bonus_energy + 3 where id = v_car;
  assert exists (select 1 from public.wallet_ledger where career_id = v_car and currency = 'bonus_energy' and delta = 3 and reason in ('other', 'manual_adjustment')),  -- evolução 14: SQL avulso = manual_adjustment
    'E1: alteração de saldo fora das funções novas não entrou no livro: ' || (select string_agg(reason, ',') from public.wallet_ledger where career_id = v_car and currency = 'bonus_energy');
  -- o livro sempre fecha com o saldo atual
  assert (select bool_and(l.balance_after = (to_jsonb(c) ->> l.currency)::int)
            from public.careers c cross join lateral (
              select distinct on (currency) currency, balance_after from public.wallet_ledger where career_id = c.id order by currency, id desc) l
           where c.id = v_car), 'E1: último saldo do livro diferente da carteira';
  raise notice 'E1 ok: livro de transações (abertura, crédito, débito, recusa, alteração antiga)';
end $$;

-- ---------------------------------------------------------------------
-- E2. Configuração: preços para todas as cartas da vitrine, vitrine do tamanho certo e igual para todos
-- ---------------------------------------------------------------------
do $$
declare s record; n int; a text[]; b text[];
begin
  for s in select * from public.shop_sections where active loop
    select count(*), array_agg(id order by id) into n, a from public.shop_showcase_cards(s.tier);
    assert n = s.slots, format('E2: vitrine de %s com %s cartas (esperado %s)', s.tier, n, s.slots);
    select array_agg(id order by id) into b from public.shop_showcase_cards(s.tier);
    assert a = b, 'E2: vitrine mudou entre duas consultas no mesmo rodízio';
    assert (select bool_and(public.shop_price(c, 'coins') > 0 and public.shop_price(c, 'diamonds') > 0) from public.shop_showcase_cards(s.tier) c),
      format('E2: carta sem preço em %s', s.tier);
  end loop;
  -- Lenda mais cara que Destaque, nas duas moedas
  assert (select min(public.shop_price(c, 'coins')) from public.cards c where c.tier = 'lenda' and c.active)
       > (select max(public.shop_price(c, 'coins')) from public.cards c where c.tier = 'destaque' and c.active), 'E2: Lenda deveria custar mais moedas';
  assert (select min(public.shop_price(c, 'diamonds')) from public.cards c where c.tier = 'lenda' and c.active)
       > (select max(public.shop_price(c, 'diamonds')) from public.cards c where c.tier = 'destaque' and c.active), 'E2: Lenda deveria custar mais diamantes';
  -- só Destaques e Lendas à venda
  assert not exists (select 1 from public.shop_sections where active and tier not in ('destaque', 'lenda')), 'E2: raridade inesperada na loja';
  raise notice 'E2 ok: vitrine e preços centralizados';
end $$;

-- ---------------------------------------------------------------------
-- E3–E7. Compras pelo app (papel authenticated)
-- ---------------------------------------------------------------------
set local role authenticated;
set local request.jwt.claim.sub = 'ec0ec0ec-0000-0000-0000-000000000001';
reset role;
update public.careers set coins = 30000, diamonds = 200 where id = 'ec0ec0ec-0000-0000-0000-0000000000c1';
set local role authenticated;

do $$
declare
  cat jsonb; it jsonb; v_card text; v_price int; r1 jsonb; r2 jsonb; c0 int; c1 int; q int; ok boolean; msg text;
  v_req uuid := gen_random_uuid();
begin
  cat := public.shop_catalog();
  assert (cat -> 'diamond_store' ->> 'available')::boolean = false and cat -> 'diamond_store' ->> 'label' = 'EM BREVE', 'E3: comprar diamantes deveria estar EM BREVE';
  it := cat -> 'sections' -> 0 -> 'items' -> 0;
  v_card := it -> 'card' ->> 'id'; v_price := (it -> 'prices' ->> 'coins')::int;
  c0 := (select coins from public.careers where user_id = auth.uid() and status = 'active');

  -- E3: compra com moedas
  r1 := public.shop_buy_card(v_card, 'coins', v_req);
  c1 := (select coins from public.careers where user_id = auth.uid() and status = 'active');
  assert (r1 ->> 'ok')::boolean and (r1 ->> 'replayed')::boolean = false, 'E3: compra falhou';
  assert c1 = c0 - v_price and (r1 ->> 'balance')::int = c1, format('E3: cobrança errada (%s → %s, preço %s)', c0, c1, v_price);
  assert (select qty from public.user_cards uc join public.careers c on c.id = uc.career_id where c.user_id = auth.uid() and uc.card_id = v_card) = 1,
    'E3: carta não entrou no inventário';
  assert (select count(*) from public.wallet_ledger l where l.reason = 'shop_card' and l.ref = r1 ->> 'purchase_id' and l.delta = -v_price) = 1,
    'E3: compra não ficou no livro';
  raise notice 'E3 ok: compra de % por % moedas', v_card, v_price;

  -- E4: o mesmo pedido de novo (clique duplo / atualizar a página): mesma resposta, nada cobrado nem entregue de novo
  r2 := public.shop_buy_card(v_card, 'coins', v_req);
  assert (r2 ->> 'replayed')::boolean and r2 ->> 'purchase_id' = r1 ->> 'purchase_id', 'E4: pedido repetido não devolveu o mesmo resultado';
  assert (select coins from public.careers where user_id = auth.uid() and status = 'active') = c1, 'E4: cobrou duas vezes';
  assert (select qty from public.user_cards uc join public.careers c on c.id = uc.career_id where c.user_id = auth.uid() and uc.card_id = v_card) = 1,
    'E4: entregou duas cartas';
  assert (select count(*) from public.shop_purchases sp join public.careers c on c.id = sp.career_id where c.user_id = auth.uid()) = 1, 'E4: duas compras gravadas';
  raise notice 'E4 ok: pedido repetido é idempotente';

  -- E5: limite por rodízio (pedido NOVO para a mesma carta)
  begin perform public.shop_buy_card(v_card, 'coins', gen_random_uuid()); ok := true; exception when others then ok := false; msg := sqlerrm; end;
  assert not ok and msg like 'Você já comprou esta carta hoje%', 'E5: deveria respeitar o limite por rodízio: ' || coalesce(msg, '');
  assert (select coins from public.careers where user_id = auth.uid() and status = 'active') = c1, 'E5: recusa alterou o saldo';
  assert (public.shop_catalog() -> 'sections' -> 0 -> 'items' -> 0 ->> 'available')::int = 0, 'E5: vitrine deveria mostrar 0 disponível';
  raise notice 'E5 ok: limite por usuário no rodízio';

  -- E6: compra com diamantes
  it := public.shop_catalog() -> 'sections' -> 1 -> 'items' -> 0;
  r1 := public.shop_buy_card(it -> 'card' ->> 'id', 'diamonds', gen_random_uuid());
  assert (r1 ->> 'currency') = 'diamonds' and (r1 ->> 'balance')::int = 200 - (it -> 'prices' ->> 'diamonds')::int, 'E6: compra com diamantes';
  assert (select diamonds from public.careers where user_id = auth.uid() and status = 'active') = 200 - (it -> 'prices' ->> 'diamonds')::int, 'E6: saldo de diamantes';
  raise notice 'E6 ok: Lenda comprada por % diamantes', it -> 'prices' ->> 'diamonds';

  -- E7: recusas sem efeito colateral
  c0 := (select coins from public.careers where user_id = auth.uid() and status = 'active');
  q := (select coalesce(sum(qty), 0) from public.user_cards uc join public.careers c on c.id = uc.career_id where c.user_id = auth.uid());
  begin perform public.shop_buy_card((select id from public.cards where tier = 'basica' limit 1), 'coins', gen_random_uuid()); ok := true;
  exception when others then ok := false; msg := sqlerrm; end;
  assert not ok, 'E7: vendeu carta básica (fora da loja)';
  begin perform public.shop_buy_card(v_card, 'gold', gen_random_uuid()); ok := true; exception when others then ok := false; end;
  assert not ok, 'E7: aceitou moeda inválida';
  begin perform public.shop_buy_card((select id from public.cards c where c.tier = 'lenda' and c.active
                                       and c.id not in (select i -> 'card' ->> 'id' from jsonb_array_elements(public.shop_catalog() -> 'sections' -> 1 -> 'items') i)
                                     limit 1), 'coins', gen_random_uuid());
        ok := true; exception when others then ok := false; msg := sqlerrm; end;
  assert not ok and msg like '%não está mais na vitrine%', 'E7: vendeu Lenda fora da vitrine do dia';
  assert (select coins from public.careers where user_id = auth.uid() and status = 'active') = c0
     and (select coalesce(sum(qty), 0) from public.user_cards uc join public.careers c on c.id = uc.career_id where c.user_id = auth.uid()) = q,
    'E7: recusa alterou saldo ou inventário';
  raise notice 'E7 ok: recusas (fora da loja, moeda inválida, fora da vitrine) sem efeito colateral';
end $$;

-- E8: saldo insuficiente — explica o motivo e não muda saldo, inventário nem compras
reset role;
update public.careers set coins = 100 where id = 'ec0ec0ec-0000-0000-0000-0000000000c1';
set local role authenticated;
do $$
declare it jsonb; ok boolean; msg text; n0 int;
begin
  it := (select i from jsonb_array_elements(public.shop_catalog() -> 'sections' -> 0 -> 'items') i where (i ->> 'available')::int > 0 limit 1);
  n0 := (select count(*) from public.shop_purchases);
  begin perform public.shop_buy_card(it -> 'card' ->> 'id', 'coins', gen_random_uuid()); ok := true; exception when others then ok := false; msg := sqlerrm; end;
  assert not ok and msg = 'Moedas insuficientes.', 'E8: mensagem de saldo insuficiente: ' || coalesce(msg, '');
  assert (select coins from public.careers where user_id = auth.uid() and status = 'active') = 100, 'E8: saldo mudou';
  assert (select count(*) from public.shop_purchases) = n0, 'E8: compra gravada sem pagamento';
  assert not exists (select 1 from public.user_cards uc join public.careers c on c.id = uc.career_id
                      where c.user_id = auth.uid() and uc.card_id = it -> 'card' ->> 'id'), 'E8: carta entregue sem pagamento';
  raise notice 'E8 ok: saldo insuficiente recusado sem alterar nada';
end $$;

-- E9: permissões — o app não mexe em saldo, livro, compras nem chama as funções internas; só vê o próprio livro
do $$
declare ok boolean;
begin
  begin perform public.econ_apply((select id from public.careers where user_id = auth.uid() and status = 'active'), 'coins', 99999, 'hack'); ok := true;
  exception when insufficient_privilege then ok := false; end;
  assert not ok, 'E9: app conseguiu chamar econ_apply';
  begin update public.careers set coins = 99999 where user_id = auth.uid(); ok := true; exception when insufficient_privilege then ok := false; end;
  assert not ok, 'E9: app conseguiu alterar o saldo direto';
  begin insert into public.wallet_ledger (career_id, currency, delta, balance_after, reason)
        select id, 'coins', 1, 1, 'x' from public.careers where user_id = auth.uid(); ok := true;
  exception when insufficient_privilege then ok := false; end;
  assert not ok, 'E9: app conseguiu escrever no livro';
  begin insert into public.shop_purchases (career_id, card_id, currency, price, period_key, request_id)
        select id, 'x', 'coins', 1, 'x', gen_random_uuid() from public.careers where user_id = auth.uid(); ok := true;
  exception when insufficient_privilege then ok := false; end;
  assert not ok, 'E9: app conseguiu gravar compra';
  assert not exists (select 1 from public.wallet_ledger l join public.careers c on c.id = l.career_id where c.user_id <> auth.uid()),
    'E9: app vê o livro de outro usuário';
  assert jsonb_array_length(public.wallet_history(10)) > 0, 'E9: histórico da carteira vazio';
  raise notice 'E9 ok: permissões';
end $$;

reset role;
do $$ begin raise notice ' TODOS OS TESTES DA ETAPA 5 PASSARAM'; end $$;
rollback;
