-- =====================================================================
-- TESTES da Etapa 7 — mercado entre jogadores (banco de DESENVOLVIMENTO, depois de evolution/09)
--   psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f supabase/evolution/tests/market_tests.sql
-- Dois usuários: A (vendedor) e B (comprador). Tudo dentro de uma transação que termina em ROLLBACK.
-- =====================================================================
begin;
set local client_min_messages = notice;

insert into auth.users (id) values ('3a3a0000-0000-0000-0000-00000000000a'), ('3a3a0000-0000-0000-0000-00000000000b') on conflict do nothing;
insert into public.careers (id, user_id, nickname, photo_id, country, age, club_id, coins) values
  ('3a3a0000-0000-0000-0000-0000000000ca', '3a3a0000-0000-0000-0000-00000000000a', 'vendedor_t7', 'p1', 'BR', 30, 'sport', 1000),
  ('3a3a0000-0000-0000-0000-0000000000cb', '3a3a0000-0000-0000-0000-00000000000b', 'comprador_t7', 'p1', 'BR', 30, 'goias', 3000);
-- A tem: 2 cópias de uma Lenda, 1 de um Destaque, 1 de uma Básica
create temp table t7 on commit drop as
select (select id from public.cards where tier = 'lenda' and active order by id limit 1) as lenda,
       (select id from public.cards where tier = 'destaque' and active order by id limit 1) as destaque,
       (select id from public.cards where tier = 'basica' and active order by id limit 1) as basica,
       gen_random_uuid() as req1;
grant select on t7 to authenticated;
insert into public.user_cards (career_id, card_id, qty)
select '3a3a0000-0000-0000-0000-0000000000ca', x, q from t7, lateral (values (t7.lenda, 2), (t7.destaque, 1), (t7.basica, 3)) v(x, q);

-- ---------------------------------------------------------------------
-- M1/M2. Regras e anúncio (vendedor A)
-- ---------------------------------------------------------------------
set local role authenticated;
set local request.jwt.claim.sub = '3a3a0000-0000-0000-0000-00000000000a';
do $$
declare t record; r jsonb; r2 jsonb; ok boolean; msg text; s jsonb;
begin
  select * into t from t7;
  assert (public.market_rules() ->> 'fee_pct')::numeric = 5, 'M1: taxa';
  s := public.market_sellable();
  assert jsonb_array_length(s) = 2 and not exists (select 1 from jsonb_array_elements(s) e where e -> 'card' ->> 'tier' = 'basica'),
    'M1: cartas vendáveis (Básica não pode)';

  r := public.market_list_card(t.lenda, 5000, t.req1);
  assert (r ->> 'ok')::boolean and (r ->> 'fee')::int = 250 and (r ->> 'seller_receives')::int = 4750, 'M2: taxa mostrada no anúncio';
  assert (select qty from public.user_cards uc join public.careers c on c.id = uc.career_id where c.user_id = auth.uid() and uc.card_id = t.lenda) = 1,
    'M2: cópia não saiu do inventário';
  r2 := public.market_list_card(t.lenda, 5000, t.req1);
  assert (r2 ->> 'replayed')::boolean and r2 ->> 'listing_id' = r ->> 'listing_id', 'M2: anúncio repetido não é idempotente';
  assert (select qty from public.user_cards uc join public.careers c on c.id = uc.career_id where c.user_id = auth.uid() and uc.card_id = t.lenda) = 1,
    'M2: repetição tirou outra cópia';

  begin perform public.market_list_card(t.lenda, 5000, gen_random_uuid()); ok := true; exception when others then ok := false; msg := sqlerrm; end;
  assert not ok and msg = 'Você já tem um anúncio ativo desta carta.', 'M2: anúncio duplicado: ' || coalesce(msg, '');
  begin perform public.market_list_card(t.destaque, 99999999, gen_random_uuid()); ok := true; exception when others then ok := false; msg := sqlerrm; end;
  assert not ok and msg like 'Preço fora do limite%', 'M2: limite de preço: ' || coalesce(msg, '');
  begin perform public.market_list_card(t.basica, 500, gen_random_uuid()); ok := true; exception when others then ok := false; msg := sqlerrm; end;
  assert not ok and msg like '%não podem ser vendidas%', 'M2: Básica não pode ser vendida';
  begin perform public.market_list_card((select id from public.cards where tier = 'epica' limit 1), 5000, gen_random_uuid()); ok := true;
  exception when others then ok := false; msg := sqlerrm; end;
  assert not ok and msg = 'Você não tem esta carta disponível para vender.', 'M2: vendeu carta que não tem';
  begin perform public.card_discard(t.lenda, 1); ok := true; exception when others then ok := false; end;
  assert not ok, 'M2: conseguiu descartar a cópia que está à venda (só sobrou 1)';
  raise notice 'M1/M2 ok: anúncio com taxa visível, cópia reservada, idempotente; duplicado, preço, raridade e carta alheia recusados';
end $$;

-- ---------------------------------------------------------------------
-- M3. Comprador B vê o anúncio e filtra
-- ---------------------------------------------------------------------
set local request.jwt.claim.sub = '3a3a0000-0000-0000-0000-00000000000b';
do $$
declare t record; b jsonb; it jsonb;
begin
  select * into t from t7;
  b := public.market_browse();
  select e into it from jsonb_array_elements(b -> 'items') e where e -> 'card' ->> 'id' = t.lenda;
  assert it is not null and it ->> 'seller' = 'vendedor_t7' and (it ->> 'price')::int = 5000 and not (it ->> 'mine')::boolean, 'M3: anúncio na vitrine';
  assert it ->> 'expires_at' is not null and it -> 'card' ->> 'tier' = 'lenda', 'M3: dados do anúncio';
  assert exists (select 1 from jsonb_array_elements(public.market_browse(p_tier => 'lenda') -> 'items') e where e ->> 'id' = it ->> 'id'), 'M3: filtro raridade';
  assert not exists (select 1 from jsonb_array_elements(public.market_browse(p_tier => 'destaque') -> 'items') e where e ->> 'id' = it ->> 'id'), 'M3: filtro raridade (fora)';
  assert exists (select 1 from jsonb_array_elements(public.market_browse(p_q => left((it -> 'card' ->> 'name'), 4)) -> 'items') e where e ->> 'id' = it ->> 'id'), 'M3: filtro nome';
  assert not exists (select 1 from jsonb_array_elements(public.market_browse(p_max => 4999) -> 'items') e where e ->> 'id' = it ->> 'id'), 'M3: filtro preço máximo';
  assert exists (select 1 from jsonb_array_elements(public.market_browse(p_min => 5000, p_max => 5000) -> 'items') e where e ->> 'id' = it ->> 'id'), 'M3: faixa de preço';
  perform set_config('t7.listing', it ->> 'id', true);
  raise notice 'M3 ok: vitrine com vendedor, preço, validade e filtros (raridade, nome, preço)';
end $$;

-- ---------------------------------------------------------------------
-- M4/M5. Compra: sem saldo (nada muda) e com saldo (atômica, taxa, livro, idempotente)
-- ---------------------------------------------------------------------
do $$
declare t record; v_l uuid := current_setting('t7.listing')::uuid; ok boolean; msg text; r jsonb; r2 jsonb; v_req uuid := gen_random_uuid();
begin
  select * into t from t7;
  begin perform public.market_buy(v_l, gen_random_uuid()); ok := true; exception when others then ok := false; msg := sqlerrm; end;
  assert not ok and msg = 'Moedas insuficientes.', 'M4: deveria recusar (B tem 3000, preço 5000): ' || coalesce(msg, '');
  assert (select coins from public.careers where user_id = auth.uid() and status = 'active') = 3000, 'M4: saldo do comprador mudou';
  raise notice 'M4 ok: sem saldo a compra é recusada e nada muda';
end $$;
reset role;
update public.careers set coins = 8000 where id = '3a3a0000-0000-0000-0000-0000000000cb';
set local role authenticated;
do $$
declare t record; v_l uuid := current_setting('t7.listing')::uuid; ok boolean; msg text; r jsonb; r2 jsonb; v_req uuid := gen_random_uuid();
begin
  select * into t from t7;
  r := public.market_buy(v_l, v_req);
  assert (r ->> 'ok')::boolean and (r ->> 'coins')::int = 3000 and r ->> 'seller' = 'vendedor_t7', 'M5: compra';
  assert (select qty from public.user_cards uc join public.careers c on c.id = uc.career_id where c.user_id = auth.uid() and uc.card_id = t.lenda) = 1,
    'M5: carta não chegou ao comprador';
  r2 := public.market_buy(v_l, v_req);
  assert (r2 ->> 'replayed')::boolean and (select coins from public.careers where user_id = auth.uid() and status = 'active') = 3000, 'M5: replay cobrou de novo';
  begin perform public.market_buy(v_l, gen_random_uuid()); ok := true; exception when others then ok := false; msg := sqlerrm; end;
  assert not ok and msg = 'Este anúncio já foi vendido.', 'M5: comprou anúncio vendido: ' || coalesce(msg, '');
  raise notice 'M5 ok: compra atômica; repetição idempotente; anúncio vendido não vende de novo';
end $$;
reset role;
do $$
declare v_l uuid := current_setting('t7.listing')::uuid;
begin
  assert (select coins from public.careers where id = '3a3a0000-0000-0000-0000-0000000000ca') = 1000 + 4750, 'M5: vendedor deveria receber 4750 (5000 − 5%)';
  assert (select status = 'sold' and fee = 250 and seller_received = 4750 and buyer_career = '3a3a0000-0000-0000-0000-0000000000cb'
            from public.market_listings where id = v_l), 'M5: anúncio não fechado corretamente';
  assert (select count(*) from public.wallet_ledger where ref = v_l::text and reason = 'market_buy' and delta = -5000) = 1
     and (select count(*) from public.wallet_ledger where ref = v_l::text and reason = 'market_sale' and delta = 4750) = 1, 'M5: livro de transações';
  assert (select array_agg(event order by id) from public.market_events where listing_id = v_l) = '{created,sold}', 'M5: auditoria';
  raise notice 'M5 ok: vendedor recebeu 4.750 (taxa 250), livro e auditoria registrados';
end $$;
set local role authenticated;

-- M6. Histórico nos dois lados
do $$
declare h jsonb;
begin
  h := public.market_mine() -> 'history';
  assert exists (select 1 from jsonb_array_elements(h) e where e ->> 'role' = 'bought' and e ->> 'other' = 'vendedor_t7' and (e ->> 'price')::int = 5000), 'M6: compra no histórico do comprador';
  perform set_config('request.jwt.claim.sub', '3a3a0000-0000-0000-0000-00000000000a', true);
  h := public.market_mine() -> 'history';
  assert exists (select 1 from jsonb_array_elements(h) e where e ->> 'role' = 'sold' and e ->> 'other' = 'comprador_t7' and (e ->> 'received')::int = 4750 and (e ->> 'fee')::int = 250),
    'M6: venda no histórico do vendedor';
  raise notice 'M6 ok: histórico de compra e venda para as duas partes';
end $$;

-- ---------------------------------------------------------------------
-- M7. Cancelar (A) e proteções
-- ---------------------------------------------------------------------
do $$
declare t record; r jsonb; c jsonb; ok boolean; msg text;
begin
  select * into t from t7;
  r := public.market_list_card(t.destaque, 900, gen_random_uuid());
  assert (select qty from public.user_cards uc join public.careers ca on ca.id = uc.career_id where ca.user_id = auth.uid() and uc.card_id = t.destaque) = 0, 'M7: reserva';
  -- B não consegue cancelar o anúncio de A
  perform set_config('request.jwt.claim.sub', '3a3a0000-0000-0000-0000-00000000000b', true);
  begin perform public.market_cancel((r ->> 'listing_id')::uuid); ok := true; exception when others then ok := false; msg := sqlerrm; end;
  assert not ok and msg = 'Anúncio não encontrado.', 'M7: outro usuário cancelou o anúncio';
  perform set_config('request.jwt.claim.sub', '3a3a0000-0000-0000-0000-00000000000a', true);
  begin perform public.market_buy((r ->> 'listing_id')::uuid, gen_random_uuid()); ok := true; exception when others then ok := false; msg := sqlerrm; end;
  assert not ok and msg = 'Você não pode comprar o seu próprio anúncio.', 'M7: comprou o próprio anúncio';
  perform set_config('t7.listing2', r ->> 'listing_id', true);
  raise notice 'M7 ok: só o dono cancela; ninguém compra o próprio anúncio';
end $$;
do $$
declare t record; v_l uuid := current_setting('t7.listing2')::uuid; c jsonb; c2 jsonb;
begin
  select * into t from t7;
  c := public.market_cancel(v_l);
  assert (c ->> 'ok')::boolean and c ->> 'status' = 'cancelled', 'M7: cancelar';
  c2 := public.market_cancel(v_l);
  assert (c2 ->> 'replayed')::boolean, 'M7: cancelar de novo deveria ser idempotente';
  assert (select qty from public.user_cards uc join public.careers ca on ca.id = uc.career_id where ca.user_id = auth.uid() and uc.card_id = t.destaque) = 1,
    'M7: carta não voltou';
  raise notice 'M7 ok: cancelar devolve a carta e é idempotente';
end $$;

-- M8. Expiração: anúncio vencido some da vitrine, a carta volta e não pode ser comprado
do $$
declare t record; r jsonb; ok boolean; msg text;
begin
  select * into t from t7;
  r := public.market_list_card(t.lenda, 7000, gen_random_uuid());
  perform set_config('t7.listing3', r ->> 'listing_id', true);
end $$;
reset role;
update public.market_listings set expires_at = now() - interval '1 minute' where id = current_setting('t7.listing3')::uuid;
set local role authenticated;
set local request.jwt.claim.sub = '3a3a0000-0000-0000-0000-00000000000b';
do $$
declare v_l uuid := current_setting('t7.listing3')::uuid; ok boolean; msg text;
begin
  assert not exists (select 1 from jsonb_array_elements(public.market_browse() -> 'items') e where e ->> 'id' = v_l::text), 'M8: anúncio vencido na vitrine';
  begin perform public.market_buy(v_l, gen_random_uuid()); ok := true; exception when others then ok := false; msg := sqlerrm; end;
  assert not ok, 'M8: comprou anúncio vencido';
  raise notice 'M8 ok: anúncio vencido some da vitrine e não pode ser comprado (%)', msg;
end $$;
reset role;
do $$
begin
  assert (select status from public.market_listings where id = current_setting('t7.listing3')::uuid) = 'expired', 'M8: status expirado';
  assert (select qty from public.user_cards where career_id = '3a3a0000-0000-0000-0000-0000000000ca'
           and card_id = (select card_id from public.market_listings where id = current_setting('t7.listing3')::uuid)) = 1, 'M8: carta não voltou ao vendedor';
  raise notice 'M8 ok: expirado e carta devolvida ao vendedor';
end $$;

-- M9. Limite de anúncios ativos (configurável)
update public.market_config set max_active_listings = 1;
set local role authenticated;
set local request.jwt.claim.sub = '3a3a0000-0000-0000-0000-00000000000a';
do $$
declare t record; ok boolean; msg text;
begin
  select * into t from t7;
  perform public.market_list_card(t.lenda, 7000, gen_random_uuid());
  begin perform public.market_list_card(t.destaque, 900, gen_random_uuid()); ok := true;
  exception when others then ok := false; msg := sqlerrm; end;
  assert not ok, 'M9: passou do limite de anúncios ativos';
  raise notice 'M9 ok: limite de anúncios ativos (%)', msg;
end $$;

-- M10. Permissões
do $$
declare ok boolean;
begin
  begin perform 1 from public.market_listings limit 1; ok := true; exception when insufficient_privilege then ok := false; end;
  assert not ok, 'M10: app lê a tabela de anúncios direto';
  begin insert into public.market_listings (seller_career, card_id, price, fee_pct, expires_at)
        select id, 'x', 1, 0, now() from public.careers where user_id = auth.uid(); ok := true;
  exception when insufficient_privilege then ok := false; end;
  assert not ok, 'M10: app cria anúncio direto';
  begin perform public.market_expire_due(); ok := true; exception when insufficient_privilege then ok := false; end;
  assert not ok, 'M10: app chama função interna';
  begin update public.market_config set fee_pct = 0; ok := true; exception when insufficient_privilege then ok := false; end;
  assert not ok, 'M10: app mudou a taxa';
  raise notice 'M10 ok: permissões';
end $$;

reset role;
do $$ begin raise notice ' TODOS OS TESTES DA ETAPA 7 PASSARAM'; end $$;
rollback;
