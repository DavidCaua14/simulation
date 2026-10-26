-- =====================================================================
-- TESTES da Etapa 13 — segurança e integridade (DESENVOLVIMENTO, depois de evolution/14)
--   psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f supabase/evolution/tests/security_tests.sql
-- Usuários: V (Vendedor_T13) e C (Comprador_T13). Tudo termina em ROLLBACK.
-- =====================================================================
begin;
set local client_min_messages = notice;
insert into auth.users (id) values ('5ec50000-0000-0000-0000-00000000000a'), ('5ec50000-0000-0000-0000-00000000000b') on conflict do nothing;
insert into public.careers (user_id, nickname, photo_id, country, age, club_id, coins, diamonds) values
  ('5ec50000-0000-0000-0000-00000000000a', 'Vendedor_T13', 'p1', 'BR', 30, 'sport', 0, 50),
  ('5ec50000-0000-0000-0000-00000000000b', 'Comprador_T13', 'p1', 'BR', 30, 'avai', 10000, 50);
insert into public.user_cards (career_id, card_id, qty)
select c.id, (select id from public.cards where tier = 'destaque' and active order by id limit 1), 2 from public.careers c where c.nickname = 'Vendedor_T13';
insert into public.user_cards (career_id, card_id, qty)
select c.id, (select id from public.cards where tier = 'basica' and active order by id limit 1), 3 from public.careers c where c.nickname = 'Vendedor_T13';
select public.card_grant_box(id, 'basica', 'test', 't13') from public.careers where nickname = 'Vendedor_T13';
create or replace function pg_temp.as_user(u text) returns void language sql as $$ select set_config('request.jwt.claim.sub', u, true) $$;
create or replace function pg_temp.car(n text) returns uuid language sql as $$ select id from public.careers where nickname = n $$;
set local role authenticated;

-- S1. Toda movimentação tem origem: funções antigas aparecem com motivo próprio (não "other")
do $$
declare v_box uuid;
begin
  perform pg_temp.as_user('5ec50000-0000-0000-0000-00000000000a');
  select id into v_box from public.reward_boxes where career_id = pg_temp.car('Vendedor_T13') and status = 'pending' limit 1;
  perform public.box_open(v_box);
  perform public.card_discard((select id from public.cards where tier = 'basica' and active order by id limit 1), 2);
  assert exists (select 1 from public.wallet_ledger where career_id = pg_temp.car('Vendedor_T13') and reason = 'box_open' and currency = 'coins' and delta > 0), 'S1: caixa sem motivo';
  assert exists (select 1 from public.wallet_ledger where career_id = pg_temp.car('Vendedor_T13') and reason = 'card_discard' and delta = 30), 'S1: descarte sem motivo';
  assert not exists (select 1 from public.wallet_ledger where career_id = pg_temp.car('Vendedor_T13') and reason = 'other'), 'S1: sobrou movimentação "other"';
  raise notice 'S1 ok: abrir caixa e descartar carta aparecem no extrato com a origem (box_open, card_discard)';
end $$;

-- S2. Mercado: os dois lados íntegros e o extrato mostra carta e contraparte (apelido), nunca ids
do $$
declare v_card text := (select id from public.cards where tier = 'destaque' and active order by id limit 1); r jsonb; h jsonb; c0 int;
begin
  perform pg_temp.as_user('5ec50000-0000-0000-0000-00000000000a');
  r := public.market_list_card(v_card, 1000, gen_random_uuid());
  perform pg_temp.as_user('5ec50000-0000-0000-0000-00000000000b');
  select coins into c0 from public.careers where id = pg_temp.car('Comprador_T13');
  perform public.market_buy((r ->> 'listing_id')::uuid, gen_random_uuid());
  assert (select coins from public.careers where id = pg_temp.car('Comprador_T13')) = c0 - 1000, 'S2: comprador';
  assert (select qty from public.user_cards where career_id = pg_temp.car('Comprador_T13') and card_id = v_card) = 1, 'S2: carta não chegou';
  h := public.wallet_history(5) -> 0;
  assert h ->> 'reason' = 'market_buy' and h -> 'detail' ->> 'other' = 'Vendedor_T13' and h -> 'detail' ->> 'card' is not null, 'S2: extrato do comprador: ' || h::text;
  perform pg_temp.as_user('5ec50000-0000-0000-0000-00000000000a');
  h := public.wallet_history(5) -> 0;
  assert h ->> 'reason' = 'market_sale' and (h ->> 'delta')::int = 950 and h -> 'detail' ->> 'other' = 'Comprador_T13', 'S2: extrato do vendedor: ' || h::text;
  assert (select qty from public.user_cards where career_id = pg_temp.car('Vendedor_T13') and card_id = v_card) = 1, 'S2: vendedor';
  raise notice 'S2 ok: venda com taxa de 5%%, carta transferida, extrato com origem e destino';
end $$;

-- S3. Permissões: funções internas e escrita direta fora do alcance do app
do $$
declare ok boolean; f text;
begin
  perform pg_temp.as_user('5ec50000-0000-0000-0000-00000000000a');
  foreach f in array array['sim_create_season(uuid,text)', 'sim_season_transition(uuid)', 'sim_participants_build(uuid)',
                           'mgr_make_offer(uuid,uuid,integer,boolean,boolean)', 'mgr_region_league_clubs(uuid,text)',
                           'econ_apply(uuid,text,integer,text,text)', 'event_track(uuid,text,integer,jsonb)', 'card_grant_box(uuid,text,text,text)', 'rl_hit(text)'] loop
    if to_regprocedure('public.' || f) is not null then
      assert not has_function_privilege('authenticated', ('public.' || f)::regprocedure, 'execute'), 'S3: app executa ' || f;
    end if;
  end loop;
  assert not exists (select 1 from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prosecdef
                      and has_function_privilege('anon', p.oid, 'execute')
                      and not exists (select 1 from pg_depend d where d.objid = p.oid and d.deptype = 'e')), 'S3: visitante sem login executa função privilegiada';
  begin update public.careers set coins = 999999 where id = pg_temp.car('Vendedor_T13'); ok := true; exception when insufficient_privilege then ok := false; end;
  assert not ok, 'S3: app alterou moedas direto';
  begin insert into public.user_cards (career_id, card_id, qty) values (pg_temp.car('Vendedor_T13'), (select id from public.cards limit 1), 5); ok := true;
  exception when insufficient_privilege then ok := false; end;
  assert not ok, 'S3: app criou carta direto';
  begin insert into public.wallet_ledger (career_id, currency, delta, balance_after, reason) values (pg_temp.car('Vendedor_T13'), 'coins', 1, 1, 'x'); ok := true;
  exception when insufficient_privilege then ok := false; end;
  assert not ok, 'S3: app escreveu no extrato';
  assert not has_table_privilege('authenticated', 'public.careers', 'truncate') and not has_table_privilege('anon', 'public.careers', 'update'), 'S3: grants largos em careers';
  assert has_column_privilege('authenticated', 'public.careers', 'nickname', 'insert') and not has_column_privilege('authenticated', 'public.careers', 'coins', 'insert'),
         'S3: criação de carreira (só colunas do formulário)';
  raise notice 'S3 ok: funções internas e escrita direta bloqueadas; criar carreira continua possível só com as colunas do formulário';
end $$;

-- S4. Limites de requisição: foto de perfil e compras; mensagem clara; nada é cobrado quando recusa
reset role;
update public.rate_limit_rules set max_hits = 3 where action in ('avatar', 'economy');
set local role authenticated;
do $$
declare ok boolean; msg text; st text; i int; d0 int;
begin
  perform pg_temp.as_user('5ec50000-0000-0000-0000-00000000000b');
  for i in 1..3 loop perform public.profile_set_avatar('preset:p' || i); end loop;
  begin perform public.profile_set_avatar('preset:p4'); ok := true; exception when others then ok := false; msg := sqlerrm; get stacked diagnostics st = returned_sqlstate; end;
  assert not ok and st = 'P0429' and msg like 'Muitas trocas de foto em pouco tempo. Tente de novo em %', 'S4: limite de foto: ' || coalesce(msg, '');
  -- compras: o Comprador já fez 1 (S2); mais 2 passam, a 4ª é recusada sem cobrar
  perform public.energy_buy('folego', gen_random_uuid());
  perform public.energy_buy('folego', gen_random_uuid());
  select diamonds into d0 from public.careers where id = pg_temp.car('Comprador_T13');
  begin perform public.energy_buy('folego', gen_random_uuid()); ok := true; exception when others then ok := false; msg := sqlerrm; get stacked diagnostics st = returned_sqlstate; end;
  assert not ok and st = 'P0429', 'S4: limite de compras: ' || coalesce(msg, '');
  assert (select diamonds from public.careers where id = pg_temp.car('Comprador_T13')) = d0, 'S4: cobrou mesmo recusando';
  -- o limite é por usuário: o Vendedor continua comprando
  perform pg_temp.as_user('5ec50000-0000-0000-0000-00000000000a');
  perform public.energy_buy('folego', gen_random_uuid());
  raise notice 'S4 ok: limites por usuário (foto e compras) com código P0429 e mensagem clara; recusa não cobra';
end $$;

-- S5. Rotinas internas (sem usuário logado) não são limitadas
reset role;
do $$
begin
  perform set_config('request.jwt.claim.sub', '', true);
  perform public.rl_hit('economy'); perform public.rl_hit('economy'); perform public.rl_hit('economy'); perform public.rl_hit('economy');
  raise notice 'S5 ok: tarefas do servidor não passam pelo limite';
end $$;

do $$ begin raise notice ' TODOS OS TESTES DA ETAPA 13 PASSARAM'; end $$;
rollback;
