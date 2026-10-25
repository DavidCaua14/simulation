-- =====================================================================
-- TESTES da Etapa 8 — pacotes de energia (banco de DESENVOLVIMENTO, depois de evolution/10)
--   psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f supabase/evolution/tests/energy_tests.sql
-- =====================================================================
begin;
set local client_min_messages = notice;
insert into auth.users (id) values ('e4e40000-0000-0000-0000-000000000001') on conflict do nothing;
insert into public.careers (id, user_id, nickname, photo_id, country, age, club_id, diamonds, bonus_energy) values
  ('e4e40000-0000-0000-0000-0000000000c1', 'e4e40000-0000-0000-0000-000000000001', 'teste_energia', 'p1', 'BR', 30, 'sport', 30, 0);
set local role authenticated;
set local request.jwt.claim.sub = 'e4e40000-0000-0000-0000-000000000001';

do $$
declare cat jsonb; r jsonb; r2 jsonb; v_req uuid := gen_random_uuid(); ok boolean; msg text;
begin
  -- N1: catálogo mostra energia atual, limite, regra e pacotes com quantidade e preço
  cat := public.energy_catalog();
  assert jsonb_array_length(cat -> 'packs') >= 3 and (cat ->> 'bonus_cap')::int = 200 and cat ->> 'overflow_rule' = 'block', 'N1: catálogo';
  assert (cat ->> 'energy') is not null and (cat ->> 'next_reset_at') is not null, 'N1: energia atual e recarga';
  -- pacotes não podem render menos que a troca avulsa
  assert not exists (select 1 from jsonb_array_elements(cat -> 'packs') p where (p ->> 'energy')::numeric / (p ->> 'price')::numeric < (cat ->> 'exchange_rate')::numeric),
    'N1: pacote rende menos que a troca avulsa';
  raise notice 'N1 ok: catálogo (energia atual, limite %, regra %, % pacotes)', cat ->> 'bonus_cap', cat ->> 'overflow_rule', jsonb_array_length(cat -> 'packs');

  -- N2: compra: diamantes saem, energia bônus entra, uma vez só
  r := public.energy_buy('treino_extra', v_req);
  assert (r ->> 'diamonds')::int = 20 and (r ->> 'bonus_energy')::int = 22, 'N2: compra';
  r2 := public.energy_buy('treino_extra', v_req);
  assert (r2 ->> 'replayed')::boolean, 'N2: replay';
  assert (select diamonds = 20 and bonus_energy = 22 from public.careers where user_id = auth.uid() and status = 'active'), 'N2: cobrou/creditou duas vezes';
  assert (select count(*) from public.wallet_ledger l join public.careers c on c.id = l.career_id where c.user_id = auth.uid() and l.reason = 'energy_pack') = 2,
    'N2: livro (débito de diamantes + crédito de energia)';
  raise notice 'N2 ok: compra cobrada uma vez (−10 💎, +22 ⚡), idempotente, no livro';

  -- N3: diamantes insuficientes
  perform public.energy_buy('pre_temporada', gen_random_uuid());   -- 20 → 0 💎, 22 → 72 ⚡
  begin perform public.energy_buy('folego', gen_random_uuid()); ok := true; exception when others then ok := false; msg := sqlerrm; end;
  assert not ok and msg = 'Diamantes insuficientes.', 'N3: ' || coalesce(msg, '');
  assert (select bonus_energy from public.careers where user_id = auth.uid() and status = 'active') = 72, 'N3: energia sem pagamento';
  raise notice 'N3 ok: sem diamantes nada muda';
end $$;

-- N4: limite de energia bônus (recusa antes de cobrar) — também na troca avulsa
reset role;
update public.careers set diamonds = 100, bonus_energy = 190 where id = 'e4e40000-0000-0000-0000-0000000000c1';
set local role authenticated;
do $$
declare cat jsonb; ok boolean; msg text;
begin
  cat := public.energy_catalog();
  assert not ((select p from jsonb_array_elements(cat -> 'packs') p where p ->> 'id' = 'treino_extra') ->> 'fits')::boolean, 'N4: tela deveria avisar que não cabe';
  begin perform public.energy_buy('treino_extra', gen_random_uuid()); ok := true; exception when others then ok := false; msg := sqlerrm; end;
  assert not ok and msg like 'Este pacote passaria do limite%', 'N4: ' || coalesce(msg, '');
  begin perform public.diamonds_exchange_energy(10); ok := true; exception when others then ok := false; msg := sqlerrm; end;
  assert not ok and msg like 'Passaria do limite%', 'N4: troca avulsa ignorou o limite';
  assert (select diamonds = 100 and bonus_energy = 190 from public.careers where user_id = auth.uid() and status = 'active'), 'N4: recusa alterou saldo';
  perform public.energy_buy('folego', gen_random_uuid());           -- 190 + 10 = 200 (cabe exatamente)
  assert (select bonus_energy from public.careers where user_id = auth.uid() and status = 'active') = 200, 'N4: pacote que cabe exatamente';
  raise notice 'N4 ok: limite de energia bônus respeitado (pacotes e troca avulsa), aviso antes da compra';
end $$;

-- N5: permissões
do $$
declare ok boolean;
begin
  begin update public.energy_packs set price_diamonds = 1; ok := true; exception when insufficient_privilege then ok := false; end;
  assert not ok, 'N5: app alterou preço';
  begin update public.energy_config set bonus_cap = 99999; ok := true; exception when insufficient_privilege then ok := false; end;
  assert not ok, 'N5: app alterou limite';
  raise notice 'N5 ok: permissões';
end $$;

reset role;
do $$ begin raise notice ' TODOS OS TESTES DA ETAPA 8 PASSARAM'; end $$;
rollback;
